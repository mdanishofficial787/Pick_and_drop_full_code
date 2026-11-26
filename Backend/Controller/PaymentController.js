const Payment = require("../schema/Payment");
const mongoose = require("mongoose");
const { uploadToCloudinary, deleteFromCloudinary } = require("../utils/cloudinary");

const resolveCustomerId = (req) => {
  if (req.user) {
    return req.user.id || req.user.customerId || req.user.userId || req.user._id || null;
  }
  if (req.body && req.body.customerId) return req.body.customerId;
  if (req.query && req.query.customerId) return req.query.customerId;
  return null;
};

// 1. Submit Payment Proof (Customer)
exports.submitPayment = async (req, res) => {
  try {
    const customerId = resolveCustomerId(req);
    const { rideId, fare } = req.body;

    if (!customerId || !mongoose.Types.ObjectId.isValid(customerId)) {
      return res.status(401).json({ success: false, message: "Valid Customer ID required" });
    }
    if (!rideId || !fare) {
      return res.status(400).json({ success: false, message: "rideId and fare are required" });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, message: "Please attach a payment proof image" });
    }

    // Upload to Cloudinary
    const cloudResult = await uploadToCloudinary(req.file.buffer, "Payments");

    // Fetch customer details
    let customerName = "Unknown";
    let customerPhone = "Unknown";
    try {
      const Customer = require("../schema/user");
      const customer = await Customer.findById(customerId);
      if (customer) {
        customerName = customer.fullName || "Unknown";
        customerPhone = customer.PhoneNumber || customer.phone || "Unknown";
      }
    } catch (_) {}

    const payment = await Payment.findOneAndUpdate(
      { rideId: rideId },
      {
        customerId,
        customerName,
        customerPhone,
        rideId,
        fare,
        paymentProofUrl: cloudResult.secure_url || cloudResult.url,
        paymentProofId: cloudResult.public_id,
        status: "PENDING VERIFICATION"
      },
      { upsert: true, new: true }
    );

    // 1. Mark ride as Paid in RideRequest and ScheduleRide collections
    try {
      const RideRequest = require("../schema/RideRequest");
      await RideRequest.updateMany(
        { $or: [{ requestId: rideId }, { _id: mongoose.Types.ObjectId.isValid(rideId) ? rideId : null }] },
        { paymentStatus: "Paid", isPaid: true }
      ).catch(() => {});

      const ScheduleRide = require("../schema/ScheduleRide");
      await ScheduleRide.updateMany(
        { $or: [{ requestId: rideId }, { _id: mongoose.Types.ObjectId.isValid(rideId) ? rideId : null }] },
        { paymentStatus: "Paid", isPaid: true }
      ).catch(() => {});
    } catch (_) {}

    // 2. Dismiss all customer notifications for this ride (e.g. Ride Completed - Pay Fare)
    try {
      const CustomerNotification = require("../schema/CustomerNotification");
      await CustomerNotification.updateMany(
        {
          $or: [
            { rideId: rideId },
            { notificationId: `${rideId}_COMPLETED` },
            { notificationId: `${rideId}_completed` },
            { notificationId: `${rideId}_ACCEPTED` },
            { notificationId: `${rideId}_accepted` }
          ]
        },
        { isDismissed: true, isRead: true }
      ).catch(() => {});

      // Record permanent dismissal entry for this ride's completed notification
      await CustomerNotification.findOneAndUpdate(
        { notificationId: `${rideId}_completed_dismissed` },
        {
          notificationId: `${rideId}_completed_dismissed`,
          rideId: rideId,
          status: "DISMISSED",
          title: "Payment Submitted",
          subtitle: "",
          isDismissed: true,
          isRead: true,
          customerId: customerId,
          passengerPhone: customerPhone
        },
        { upsert: true }
      ).catch(() => {});
    } catch (_) {}

    // 3. Emit real-time Socket.IO notification to customer
    try {
      const io = req.app.get("io");
      if (io) {
        const payload = {
          rideId,
          customerId,
          status: "PAID",
          title: "Payment Submitted",
          message: `Your payment of Rs. ${fare} for ride #${rideId} has been submitted.`
        };
        io.to(`customer_${customerId}`).emit("payment-status-updated", payload);
        io.to(String(customerId)).emit("payment-status-updated", payload);
        io.emit("payment-status-updated", payload);
      }
    } catch (_) {}

    return res.status(201).json({
      success: true,
      message: "Payment submitted successfully",
      data: payment
    });
  } catch (error) {
    console.error("Payment Submission Error:", error);
    return res.status(500).json({ success: false, message: "Server Error", error: error.message });
  }
};

// 2. Get Customer Payment History (Customer)
exports.getCustomerPayments = async (req, res) => {
  try {
    const customerId = resolveCustomerId(req) || req.query.customerId;
    const phone = req.query?.phone || (req.user ? req.user.phone || req.user.PhoneNumber : null);
    
    let conds = [];
    if (customerId) {
      conds.push({ customerId: customerId });
      if (mongoose.Types.ObjectId.isValid(customerId)) {
        conds.push({ customerId: new mongoose.Types.ObjectId(customerId) });
      }
    }
    if (phone) {
      const cleanPhone = String(phone).replace(/[^0-9]/g, "");
      conds.push({ customerPhone: phone });
      conds.push({ customerPhone: cleanPhone });
      if (cleanPhone.length >= 7) {
        conds.push({ customerPhone: new RegExp(cleanPhone.slice(-9), "i") });
      }
    }

    if (conds.length === 0) {
      return res.status(200).json({ success: true, count: 0, data: [] });
    }

    const payments = await Payment.find({ $or: conds }).sort({ createdAt: -1 }).lean();
    return res.status(200).json({ success: true, count: payments.length, data: payments });
  } catch (error) {
    return res.status(500).json({ success: false, message: "Server Error", error: error.message });
  }
};

// 3. Get All Payments (Admin)
exports.getAllPayments = async (req, res) => {
  try {
    const { status } = req.query;
    let query = {};
    if (status) query.status = status;

    const payments = await Payment.find(query).sort({ createdAt: -1 }).populate('customerId', 'fullName PhoneNumber Email').lean();
    return res.status(200).json({ success: true, count: payments.length, data: payments });
  } catch (error) {
    return res.status(500).json({ success: false, message: "Server Error", error: error.message });
  }
};

// 4. Update Payment Status (Admin)
exports.updatePaymentStatus = async (req, res) => {
  try {
    const paymentId = req.params.id;
    const { status, adminRemarks } = req.body;

    const payment = await Payment.findByIdAndUpdate(
      paymentId,
      { status, adminRemarks },
      { new: true }
    );

    if (!payment) return res.status(404).json({ success: false, message: "Payment not found" });

    if (status === "VERIFIED") {
      try {
        const RideRequest = require("../schema/RideRequest");
        await RideRequest.updateMany(
          { $or: [{ requestId: payment.rideId }, { _id: mongoose.Types.ObjectId.isValid(payment.rideId) ? payment.rideId : null }] },
          { paymentStatus: "Paid", isPaid: true }
        ).catch(() => {});

        const ScheduleRide = require("../schema/ScheduleRide");
        await ScheduleRide.updateMany(
          { $or: [{ requestId: payment.rideId }, { _id: mongoose.Types.ObjectId.isValid(payment.rideId) ? payment.rideId : null }] },
          { paymentStatus: "Paid", isPaid: true }
        ).catch(() => {});

        const CustomerNotification = require("../schema/CustomerNotification");
        await CustomerNotification.updateMany(
          {
            $or: [
              { rideId: payment.rideId },
              { notificationId: `${payment.rideId}_COMPLETED` },
              { notificationId: `${payment.rideId}_completed` }
            ]
          },
          { isDismissed: true, isRead: true }
        ).catch(() => {});
      } catch (_) {}
    }

    try {
      const io = req.app.get("io");
      if (io && payment.customerId) {
        const payload = {
          rideId: payment.rideId,
          customerId: payment.customerId,
          status,
          title: status === "VERIFIED" ? "Payment Verified" : "Payment Update",
          message: status === "VERIFIED"
            ? `Your payment of Rs. ${payment.fare} for ride #${payment.rideId} has been verified.`
            : `Your payment status is now: ${status}`
        };
        io.to(`customer_${payment.customerId}`).emit("payment-status-updated", payload);
        io.to(String(payment.customerId)).emit("payment-status-updated", payload);
        io.emit("payment-status-updated", payload);
      }
    } catch (_) {}

    return res.status(200).json({ success: true, message: "Payment status updated", data: payment });
  } catch (error) {
    return res.status(500).json({ success: false, message: "Server Error", error: error.message });
  }
};
