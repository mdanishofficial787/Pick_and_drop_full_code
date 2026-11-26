const mongoose = require("mongoose");
const TravelTourismRequest = require("../schema/TravelTourismRequest");
const Driver = require("../schema/Driver");

// 1. Create Travel & Tourism Request (Customer App)
exports.createTravelRequest = async (req, res) => {
  try {
    const {
      passengerName,
      passengerPhone,
      passengerEmail,
      cnic,
      pickupLocation,
      dropoffLocation,
      travelDate,
      travelTime,
      returnDate,
      returnTime,
      returnPickupLocation,
      returnDropoffLocation,
      vehicleType,
      acPreference,
      passengersCount,
      fare,
      notes,
      customerId,
      customSchedule
    } = req.body;

    if (!passengerName || !passengerPhone || !cnic || !pickupLocation || !dropoffLocation || !travelDate) {
      return res.status(400).json({
        success: false,
        message: "Please provide all required fields (Name, Phone, CNIC, Pickup, Dropoff, Travel Date)"
      });
    }

    const newRequest = new TravelTourismRequest({
      customerId: customerId || null,
      passengerName: passengerName.trim(),
      passengerPhone: passengerPhone.trim(),
      passengerEmail: passengerEmail ? passengerEmail.trim().toLowerCase() : null,
      cnic: cnic.trim(),
      pickupLocation: pickupLocation.trim(),
      dropoffLocation: dropoffLocation.trim(),
      travelDate: travelDate.trim(),
      travelTime: travelTime || customSchedule?.travelTime || "09:00 AM",
      returnDate: returnDate || customSchedule?.returnDate || "",
      returnTime: returnTime || customSchedule?.returnTime || "",
      returnPickupLocation: returnPickupLocation || customSchedule?.returnPickupLocation || "",
      returnDropoffLocation: returnDropoffLocation || customSchedule?.returnDropoffLocation || "",
      vehicleType: vehicleType || "SUV",
      acPreference: acPreference || "AC",
      passengersCount: Number(passengersCount) || 4,
      fare: Number(fare) || 15000,
      notes: notes || "",
      status: "Pending Dispatch",
      requestType: "Travel & Tourism"
    });

    const saved = await newRequest.save();

    // Emit Socket.IO event to Admin Portal
    try {
      const io = req.app.get("io");
      if (io) {
        const payload = {
          _id: saved._id,
          id: saved._id,
          mongoId: saved._id,
          requestId: saved.requestId,
          requestType: "Travel & Tourism",
          passengerName: saved.passengerName,
          passengerPhone: saved.passengerPhone,
          passengerEmail: saved.passengerEmail,
          cnic: saved.cnic,
          pickupLocation: saved.pickupLocation,
          dropoffLocation: saved.dropoffLocation,
          travelDate: saved.travelDate,
          travelTime: saved.travelTime,
          returnDate: saved.returnDate,
          returnTime: saved.returnTime,
          returnPickupLocation: saved.returnPickupLocation,
          returnDropoffLocation: saved.returnDropoffLocation,
          vehicleType: saved.vehicleType,
          acPreference: saved.acPreference,
          passengersCount: saved.passengersCount,
          fare: saved.fare,
          fareFormatted: `Rs. ${Number(saved.fare).toLocaleString()}`,
          notes: saved.notes,
          status: saved.status,
          createdAt: saved.createdAt
        };
        io.emit("new-travel-request", payload);
        io.emit("travel-request-update", { type: "NEW_TRAVEL_REQUEST", request: payload });
        io.emit("new-ride", { ...payload, category: "Travel & Tourism" });
        io.emit("ride-update", { type: "NEW_TRAVEL_REQUEST", ride: payload });
        console.log("ðŸ“¡ Real-time event emitted: new-travel-request", saved.requestId);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(201).json({
      success: true,
      message: "Travel & Tourism request submitted successfully. Awaiting dispatch.",
      ride: saved,
      request: saved,
      requestId: saved.requestId
    });
  } catch (err) {
    console.error("Create Travel Request Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to submit travel request",
      error: err.message
    });
  }
};

// 2. Get All Travel & Tourism Requests (Admin Console)
exports.getAllTravelRequests = async (req, res) => {
  try {
    const { status, search } = req.query;
    let query = {};

    if (status) {
      query.status = status.toLowerCase() === "pending" ? "Pending Dispatch" : status;
    }

    if (search) {
      query.$or = [
        { requestId: { $regex: search, $options: "i" } },
        { passengerName: { $regex: search, $options: "i" } },
        { passengerPhone: { $regex: search, $options: "i" } },
        { cnic: { $regex: search, $options: "i" } },
        { pickupLocation: { $regex: search, $options: "i" } },
        { dropoffLocation: { $regex: search, $options: "i" } }
      ];
    }

    const requests = await TravelTourismRequest.find(query).sort({ createdAt: -1 }).lean();
    const pendingCount = await TravelTourismRequest.countDocuments({ status: "Pending Dispatch" });
    const assignedCount = await TravelTourismRequest.countDocuments({ status: "ASSIGNED" });

    const formatted = requests.map((r) => ({
      _id: r._id,
      id: r.requestId || r._id,
      mongoId: r._id,
      requestId: r.requestId,
      requestType: r.requestType || "Travel & Tourism",
      passengerName: r.passengerName,
      passengerPhone: r.passengerPhone,
      passengerEmail: r.passengerEmail,
      cnic: r.cnic,
      pickupLocation: r.pickupLocation,
      dropoffLocation: r.dropoffLocation,
      travelDate: r.travelDate,
      travelTime: r.travelTime,
      returnDate: r.returnDate,
      returnTime: r.returnTime,
      returnPickupLocation: r.returnPickupLocation,
      returnDropoffLocation: r.returnDropoffLocation,
      vehicleType: r.vehicleType,
      acPreference: r.acPreference,
      passengersCount: r.passengersCount || 4,
      fare: r.fare || 15000,
      fareFormatted: `Rs. ${(r.fare || 15000).toLocaleString()}`,
      notes: r.notes,
      status: r.status,
      assignedDriver: r.assignedDriverName || r.assignedDriver || null,
      assignedDriverName: r.assignedDriverName || r.assignedDriver || null,
      assignedDriverId: r.assignedDriverId || r.driverId || r.driver || null,
      driverId: r.driverId || r.assignedDriverId || r.driver || null,
      createdAt: r.createdAt
    }));

    return res.status(200).json({
      success: true,
      count: requests.length,
      pendingCount,
      assignedCount,
      data: formatted,
      requests: formatted
    });
  } catch (err) {
    console.error("Get Travel Requests Error:", err);
    return res.status(500).json({ success: false, message: "Failed to fetch travel requests", error: err.message });
  }
};

// 3. Get Customer's Travel Requests
exports.getCustomerTravelRequests = async (req, res) => {
  try {
    const { customerId, phone, email } = req.query;
    let query = {};
    if (customerId) query.customerId = customerId;
    if (phone) query.passengerPhone = phone;
    if (email) query.passengerEmail = email.toLowerCase();

    const requests = await TravelTourismRequest.find(query).sort({ createdAt: -1 }).lean();
    return res.status(200).json({ success: true, count: requests.length, requests });
  } catch (err) {
    return res.status(500).json({ success: false, message: "Failed to fetch customer travel requests", error: err.message });
  }
};

// 4. Dispatch / Assign Driver (Admin Action)
exports.dispatchTravelRequest = async (req, res) => {
  try {
    const { driverId, driverName } = req.body;
    const reqId = req.params.id;

    let existing = null;
    if (mongoose.Types.ObjectId.isValid(reqId)) {
      existing = await TravelTourismRequest.findById(reqId).catch(() => null);
    }
    if (!existing) {
      existing = await TravelTourismRequest.findOne({ requestId: reqId }).catch(() => null);
    }
    if (!existing) {
      return res.status(404).json({ success: false, message: `Travel request '${reqId}' not found` });
    }

    let assignedName = driverName;
    if (driverId && !assignedName) {
      try {
        const driverObj = mongoose.Types.ObjectId.isValid(driverId)
          ? await Driver.findById(driverId).catch(() => null)
          : await Driver.findOne({ driverReferenceId: driverId }).catch(() => null);
        if (driverObj) {
          assignedName = driverObj.Name || `${driverObj.firstName || ""} ${driverObj.lastName || ""}`.trim();
        }
      } catch (_) {}
    }

    const updated = await TravelTourismRequest.findByIdAndUpdate(
      existing._id,
      { status: "ASSIGNED", assignedDriverId: driverId || null, assignedDriverName: assignedName || "Assigned Driver" },
      { returnDocument: "after", new: true }
    );

    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("travel-request-dispatched", updated);
        io.emit("travel-request-update", { type: "TRAVEL_REQUEST_DISPATCHED", request: updated });
        console.log("ðŸ“¡ Real-time event emitted: travel-request-dispatched", updated.requestId);
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Travel request ${updated.requestId} successfully dispatched`,
      request: updated
    });
  } catch (err) {
    console.error("Dispatch Travel Request Error:", err);
    return res.status(500).json({ success: false, message: "Failed to dispatch travel request", error: err.message });
  }
};

// 5. Update Travel Request (Admin)
exports.updateTravelRequest = async (req, res) => {
  try {
    const reqId = req.params.id;
    const { fare, status, notes, driverId, driverName } = req.body;

    let request = null;
    if (mongoose.Types.ObjectId.isValid(reqId)) {
      request = await TravelTourismRequest.findById(reqId).catch(() => null);
    }
    if (!request) request = await TravelTourismRequest.findOne({ requestId: reqId }).catch(() => null);
    if (!request) return res.status(404).json({ success: false, message: `Travel request ${reqId} not found` });

    const isFareUpdated = (fare !== undefined && fare !== null && !isNaN(Number(fare)) && Number(fare) >= 0 && (Number(fare) !== Number(request.fare) || status === "PRICE_UPDATED" || req.body.fareStatus === "PRICE_UPDATED"));
    if (isFareUpdated) {
      request.fare = Number(fare);
      if (!status || status === "PRICE_UPDATED") {
        if (request.status !== "COMPLETED" && request.status !== "Completed" && request.status !== "PAID") {
          request.status = "PRICE_UPDATED";
        }
      }
      request.fareResponseStatus = "Pending";
      request.fareStatus = "PRICE_UPDATED";
    }
    if (status) request.status = status;
    if (notes !== undefined) request.notes = notes;
    if (driverId) request.assignedDriverId = driverId;
    if (driverName) request.assignedDriverName = driverName;

    await request.save();

    // Persist CustomerNotification & Payment if COMPLETED
    if (request.status === "COMPLETED" || request.status === "Completed") {
      try {
        const Payment = require("../schema/Payment");
        const numericFare = Number(request.fare || 0);
        await Payment.findOneAndUpdate(
          { rideId: request.requestId || request._id.toString() },
          {
            $setOnInsert: {
              rideId: request.requestId || request._id.toString(),
              paymentProofUrl: "",
              paymentProofId: "",
              uploadedAt: new Date(),
            },
            $set: {
              customerId: request.customerId || null,
              customerName: request.passengerName || "Customer",
              customerPhone: request.passengerPhone || "",
              customerEmail: request.passengerEmail || "",
              pickup: request.pickupLocation || "",
              destination: request.destination || request.dropoffLocation || "",
              driverName: request.assignedDriverName || "Driver",
              fare: numericFare,
              amount: numericFare,
              status: "PENDING PAYMENT",
            }
          },
          { upsert: true, new: true }
        );
        console.log(`✅ Auto-created Payment record (PENDING PAYMENT) for completed travel request ${request.requestId}`);
      } catch (payErr) {
        console.warn("Auto-create Payment record on travel completion error:", payErr.message);
      }

      try {
        const CustomerNotification = require("../schema/CustomerNotification");
        const numericFare = Number(request.fare || 0);
        const fareFormatted = `Rs. ${numericFare.toLocaleString()}`;
        const notifId = `${request.requestId}_completed`;

        await CustomerNotification.findOneAndUpdate(
          { notificationId: notifId },
          {
            customerId: request.customerId || request.passengerPhone,
            passengerPhone: request.passengerPhone,
            passengerEmail: request.passengerEmail || "",
            rideId: request.requestId,
            mongoId: request._id ? request._id.toString() : request.requestId,
            notificationId: notifId,
            title: "💳 Ride Completed - Pay Fare",
            subtitle: `Your travel tour has ended. Please tap to pay ${fareFormatted} to complete your ride.`,
            status: "COMPLETED",
            fareResponseStatus: "Pending Payment",
            fareFormatted: fareFormatted,
            pickup: request.pickupLocation || "Pickup Point",
            destination: request.destination || request.dropoffLocation || "Destination Point",
            isRead: false,
            isDismissed: false
          },
          { upsert: true, new: true }
        );
      } catch (notifErr) {
        console.warn("Failed saving customer notification for completed travel ride:", notifErr.message);
      }
    }
    if (isFareUpdated && request.status !== "COMPLETED") {
      try {
        const CustomerNotification = require("../schema/CustomerNotification");
        const fareFormatted = `Rs. ${Number(request.fare || 0).toLocaleString()}`;
        const notifId = `${request.requestId}_price_updated`;

        await CustomerNotification.findOneAndUpdate(
          { notificationId: notifId },
          {
            customerId: request.customerId || request.passengerPhone,
            passengerPhone: request.passengerPhone,
            passengerEmail: request.passengerEmail || "",
            rideId: request.requestId,
            mongoId: request._id ? request._id.toString() : request.requestId,
            notificationId: notifId,
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has updated your travel tour fare to ${fareFormatted}. Tap to review and accept.`,
            status: "PRICE_UPDATED",
            fareResponseStatus: "Pending",
            fareFormatted: fareFormatted,
            pickup: request.pickupLocation || "Pickup Point",
            destination: request.destination || request.dropoffLocation || "Destination Point",
            isRead: false,
            isDismissed: false
          },
          { upsert: true, new: true }
        );
        console.log(`✅ CustomerNotification [PRICE_UPDATED] saved for travel request ${request.requestId}: ${fareFormatted}`);
      } catch (fareNotifErr) {
        console.warn("Failed saving customer notification for updated travel fare:", fareNotifErr.message);
      }
    }

    const notifyPayload = {
      requestId: request.requestId,
      customerId: request.customerId,
      requestType: "Travel & Tourism",
      passengerName: request.passengerName,
      passengerPhone: request.passengerPhone,
      fareFormatted: `Rs. ${Number(request.fare || 0).toLocaleString()}`,
      fare: request.fare,
      status: request.status
    };

    try {
      const io = req.app.get("io");
      if (io) {
        if (isFareUpdated && request.status !== "COMPLETED") {
          const farePayload = {
            ...notifyPayload,
            type: "PRICE_UPDATED",
            status: "PRICE_UPDATED",
            fareUpdated: true,
            fareResponseStatus: "Pending",
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has updated your tour fare to ${notifyPayload.fareFormatted}.`
          };
          const custId = request.customerId ? String(request.customerId) : "";
          const custPhone = request.passengerPhone ? String(request.passengerPhone) : "";
          const rId = String(request.requestId);

          if (custId) {
            io.to(`customer_${custId}`).emit("ride-updated", farePayload);
            io.to(`customer_${custId}`).emit("fare-updated", farePayload);
            io.to(`customer_${custId}`).emit("customer-notification", farePayload);
          }
          if (custPhone) {
            io.to(`customer_${custPhone}`).emit("ride-updated", farePayload);
            io.to(`customer_${custPhone}`).emit("fare-updated", farePayload);
            io.to(`customer_${custPhone}`).emit("customer-notification", farePayload);
          }
          io.to(`ride_${rId}`).emit("ride-updated", farePayload);
          io.to(`ride_${rId}`).emit("fare-updated", farePayload);
          io.emit("ride-updated", farePayload);
          io.emit("fare-updated", farePayload);
          io.emit("customer-notification", farePayload);
          console.log(`📡 Real-time fare update emitted to customer for travel request ${rId}: ${notifyPayload.fareFormatted}`);
        }
        if (request.status === "COMPLETED" || request.status === "Completed") {
          const completedPayload = {
            ...notifyPayload,
            type: "COMPLETED",
            status: "COMPLETED",
            fareFormatted: notifyPayload.fareFormatted,
            fare: request.fare,
            pickup: request.pickupLocation,
            destination: request.destination || request.dropoffLocation,
            title: "💳 Ride Completed - Pay Fare",
            subtitle: `Your travel tour has ended. Please tap to pay ${notifyPayload.fareFormatted} to complete your ride.`
          };
          const custId = request.customerId ? String(request.customerId) : "";
          const custPhone = request.passengerPhone ? String(request.passengerPhone) : "";
          const rId = String(request.requestId);

          if (custId) {
            io.to(`customer_${custId}`).emit("ride-completed", completedPayload);
            io.to(`customer_${custId}`).emit("ride-updated", completedPayload);
            io.to(`customer_${custId}`).emit("customer-notification", completedPayload);
          }
          if (custPhone) {
            io.to(`customer_${custPhone}`).emit("ride-completed", completedPayload);
            io.to(`customer_${custPhone}`).emit("ride-updated", completedPayload);
            io.to(`customer_${custPhone}`).emit("customer-notification", completedPayload);
          }
          io.to(`ride_${rId}`).emit("ride-completed", completedPayload);
          io.to(`ride_${rId}`).emit("ride-updated", completedPayload);
          io.emit("ride-completed", completedPayload);
          io.emit("ride-updated", completedPayload);
          io.emit("customer-notification", completedPayload);
          console.log(`📡 Real-time ride-completed emitted for travel request ${rId}`);
        }
        io.emit("travel-request-updated", notifyPayload);
        io.emit("ride-updated", { ...notifyPayload, id: request.requestId });
        console.log(`ðŸ“¡ Emitted [travel-request-updated] for ${request.requestId}`);
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Travel request ${request.requestId} updated`,
      request,
      notificationPayload: notifyPayload
    });
  } catch (err) {
    console.error("Update Travel Request Error:", err);
    return res.status(500).json({ success: false, message: "Failed to update travel request", error: err.message });
  }
};
