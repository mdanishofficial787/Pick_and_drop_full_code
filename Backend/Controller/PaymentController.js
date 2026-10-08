const Payment = require("../schema/Payment");
const mongoose = require("mongoose");
const { uploadToCloudinary, deleteFromCloudinary } = require("../utils/cloudinary");

const resolveCustomerId = (req) => {
  if (req.user) {
    return req.user.id || req.user.customerId || req.user.userId || req.user._id || null;
  }
  if (req.body.customerId) return req.body.customerId;
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
    const Customer = require("../schema/user");
    const customer = await Customer.findById(customerId);
    const customerName = customer ? (customer.fullName || "Unknown") : "Unknown";
    const customerPhone = customer ? (customer.PhoneNumber || "Unknown") : "Unknown";

    const payment = new Payment({
      customerId,
      customerName,
      customerPhone,
      rideId,
      fare,
      paymentProofUrl: cloudResult.secure_url || cloudResult.url,
      paymentProofId: cloudResult.public_id,
      status: "PENDING VERIFICATION"
    });

    await payment.save();

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
    const customerId = resolveCustomerId(req);
    if (!customerId) return res.status(401).json({ success: false, message: "Unauthorized" });

    const payments = await Payment.find({ customerId }).sort({ createdAt: -1 }).lean();
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

    return res.status(200).json({ success: true, message: "Payment status updated", data: payment });
  } catch (error) {
    return res.status(500).json({ success: false, message: "Server Error", error: error.message });
  }
};
