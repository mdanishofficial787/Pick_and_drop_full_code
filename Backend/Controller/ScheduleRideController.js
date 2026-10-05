const mongoose = require("mongoose");
const ScheduleRide = require("../schema/ScheduleRide");
const Driver = require("../schema/Driver");

// 1. Create Schedule Ride Request (Customer App)
exports.createScheduleRide = async (req, res) => {
  try {
    const {
      passengerName,
      passengerPhone,
      passengerEmail,
      pickupLocation,
      dropoffLocation,
      startingFrom,
      timeToReach,
      timeToLeave,
      rideType,
      vehicleType,
      acPreference,
      genderPreference,
      fare,
      notes,
      customerId,
      customSchedule
    } = req.body;

    if (!passengerName || !passengerPhone || !pickupLocation || !dropoffLocation || !startingFrom) {
      return res.status(400).json({
        success: false,
        message: "Please provide all required fields (Name, Phone, Pickup, Dropoff, Date)"
      });
    }

    const newRide = new ScheduleRide({
      customerId: customerId || null,
      passengerName: passengerName.trim(),
      passengerPhone: passengerPhone.trim(),
      passengerEmail: passengerEmail ? passengerEmail.trim().toLowerCase() : null,
      pickupLocation: pickupLocation.trim(),
      dropoffLocation: dropoffLocation.trim(),
      startingFrom: startingFrom.trim(),
      timeToReach: timeToReach || "08:30 AM",
      timeToLeave: timeToLeave || "05:00 PM",
      rideType: rideType || customSchedule?.rideType || "One Way",
      vehicleType: vehicleType || customSchedule?.vehicleType || "Sedan Executive",
      acPreference: acPreference || customSchedule?.acPreference || "AC",
      genderPreference: genderPreference || customSchedule?.genderPreference || "Both",
      fare: Number(fare) || 7500,
      notes: notes || "",
      customSchedule: customSchedule || {},
      status: "Pending Dispatch",
      requestType: "Schedule Ride"
    });

    const saved = await newRide.save();

    // Emit Socket.IO event to Admin Portal
    try {
      const io = req.app.get("io");
      if (io) {
        const payload = {
          _id: saved._id,
          id: saved._id,
          mongoId: saved._id,
          requestId: saved.requestId,
          requestType: "Schedule Ride",
          passengerName: saved.passengerName,
          passengerPhone: saved.passengerPhone,
          passengerEmail: saved.passengerEmail,
          pickupLocation: saved.pickupLocation,
          dropoffLocation: saved.dropoffLocation,
          startingFrom: saved.startingFrom,
          timeToReach: saved.timeToReach,
          timeToLeave: saved.timeToLeave,
          rideType: saved.rideType,
          vehicleType: saved.vehicleType,
          acPreference: saved.acPreference,
          genderPreference: saved.genderPreference,
          fare: saved.fare,
          fareFormatted: `Rs. ${Number(saved.fare).toLocaleString()}`,
          notes: saved.notes,
          customSchedule: saved.customSchedule,
          status: saved.status,
          createdAt: saved.createdAt
        };
        io.emit("new-schedule-ride", payload);
        io.emit("schedule-ride-update", { type: "NEW_SCHEDULE_RIDE", ride: payload });
        io.emit("new-ride", { ...payload, category: "Schedule Ride" });
        io.emit("ride-update", { type: "NEW_SCHEDULE_RIDE", ride: payload });
        console.log("📡 Real-time event emitted: new-schedule-ride", saved.requestId);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(201).json({
      success: true,
      message: "Schedule ride request submitted successfully. Awaiting dispatch.",
      ride: saved,
      requestId: saved.requestId
    });
  } catch (err) {
    console.error("Create Schedule Ride Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to submit schedule ride request",
      error: err.message
    });
  }
};

// 2. Get All Schedule Ride Requests (Admin Console)
exports.getAllScheduleRides = async (req, res) => {
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
        { pickupLocation: { $regex: search, $options: "i" } },
        { dropoffLocation: { $regex: search, $options: "i" } }
      ];
    }

    const rides = await ScheduleRide.find(query).sort({ createdAt: -1 });
    const pendingCount = await ScheduleRide.countDocuments({ status: "Pending Dispatch" });
    const assignedCount = await ScheduleRide.countDocuments({ status: "ASSIGNED" });

    const formatted = rides.map((r) => ({
      _id: r._id,
      id: r.requestId || r._id,
      mongoId: r._id,
      requestId: r.requestId,
      requestType: r.requestType || "Schedule Ride",
      passengerName: r.passengerName,
      passengerPhone: r.passengerPhone,
      passengerEmail: r.passengerEmail,
      pickupLocation: r.pickupLocation,
      dropoffLocation: r.dropoffLocation,
      startingFrom: r.startingFrom,
      timeToReach: r.timeToReach,
      timeToLeave: r.timeToLeave,
      rideType: r.rideType,
      vehicleType: r.vehicleType,
      acPreference: r.acPreference,
      genderPreference: r.genderPreference,
      fare: r.fare || 7500,
      fareFormatted: `Rs. ${(r.fare || 7500).toLocaleString()}`,
      notes: r.notes,
      customSchedule: r.customSchedule,
      status: r.status,
      assignedDriverName: r.assignedDriverName || null,
      createdAt: r.createdAt
    }));

    return res.status(200).json({
      success: true,
      count: rides.length,
      pendingCount,
      assignedCount,
      data: formatted,
      rides: formatted,
      requests: formatted
    });
  } catch (err) {
    console.error("Get Schedule Rides Error:", err);
    return res.status(500).json({ success: false, message: "Failed to fetch schedule rides", error: err.message });
  }
};

// 3. Get Schedule Rides for a specific customer
exports.getCustomerScheduleRides = async (req, res) => {
  try {
    const { customerId, phone, email } = req.query;
    let query = {};
    if (customerId) query.customerId = customerId;
    if (phone) query.passengerPhone = phone;
    if (email) query.passengerEmail = email.toLowerCase();

    const rides = await ScheduleRide.find(query).sort({ createdAt: -1 });
    return res.status(200).json({ success: true, count: rides.length, rides });
  } catch (err) {
    return res.status(500).json({ success: false, message: "Failed to fetch customer schedule rides", error: err.message });
  }
};

// 4. Dispatch / Assign Driver (Admin Action)
exports.dispatchScheduleRide = async (req, res) => {
  try {
    const { driverId, driverName } = req.body;
    const rideId = req.params.id;

    let existingRide = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      existingRide = await ScheduleRide.findById(rideId).catch(() => null);
    }
    if (!existingRide) {
      existingRide = await ScheduleRide.findOne({ requestId: rideId }).catch(() => null);
    }
    if (!existingRide) {
      return res.status(404).json({ success: false, message: `Schedule ride '${rideId}' not found` });
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

    const updated = await ScheduleRide.findByIdAndUpdate(
      existingRide._id,
      { status: "ASSIGNED", assignedDriverId: driverId || null, assignedDriverName: assignedName || "Assigned Driver" },
      { returnDocument: "after", new: true }
    );

    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("schedule-ride-dispatched", updated);
        io.emit("schedule-ride-update", { type: "SCHEDULE_RIDE_DISPATCHED", ride: updated });
        console.log("📡 Real-time event emitted: schedule-ride-dispatched", updated.requestId);
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Schedule ride ${updated.requestId} successfully dispatched`,
      ride: updated
    });
  } catch (err) {
    console.error("Dispatch Schedule Ride Error:", err);
    return res.status(500).json({ success: false, message: "Failed to dispatch schedule ride", error: err.message });
  }
};

// 5. Update Schedule Ride (Admin - set fare, status, etc.)
exports.updateScheduleRide = async (req, res) => {
  try {
    const rideId = req.params.id;
    const { fare, status, notes, driverId, driverName } = req.body;

    let ride = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      ride = await ScheduleRide.findById(rideId).catch(() => null);
    }
    if (!ride) ride = await ScheduleRide.findOne({ requestId: rideId }).catch(() => null);
    if (!ride) return res.status(404).json({ success: false, message: `Schedule ride ${rideId} not found` });

    if (fare !== undefined) ride.fare = Number(fare);
    if (status) ride.status = status;
    if (notes !== undefined) ride.notes = notes;
    const targetDriverId = driverId || ride.assignedDriverId;
    if (targetDriverId) {
      ride.assignedDriverId = targetDriverId;
      try {
        let driverObj = null;
        const Driver = require("../schema/Driver");
        if (mongoose.Types.ObjectId.isValid(targetDriverId)) {
          driverObj = await Driver.findById(targetDriverId).catch(() => null);
        }
        if (!driverObj) {
          driverObj = await Driver.findOne({ driverReferenceId: targetDriverId }).catch(() => null);
        }

        if (driverObj) {
          const dName = driverObj.Name || `${driverObj.firstName || ''} ${driverObj.lastName || ''}`.trim() || driverName || "Assigned Driver";
          const vDetails = driverObj.VehicleDetails || driverObj.vehicle || {};
          const vMake = vDetails.make || vDetails.makeModel || "Vehicle";
          const vModel = vDetails.model || "";
          const vColor = vDetails.color ? ` (${vDetails.color})` : "";

          ride.assignedDriverName = dName;
          ride.assignedDriverDetails = {
            driverId: driverObj._id,
            driverCode: driverObj.driverReferenceId || driverObj.driverCode || `DRV-${Date.now()}`,
            name: dName,
            phone: driverObj.PhoneNumber || driverObj.phone || "+92 3000000000",
            rating: driverObj.rating || 4.9,
            vehicle: `${vMake} ${vModel}${vColor}`.trim(),
            registrationNumber: vDetails.registrationNumber || vDetails.numberPlate || "REGISTERED"
          };
        } else if (driverName) {
          ride.assignedDriverName = driverName;
        }
      } catch (_) {
        if (driverName) ride.assignedDriverName = driverName;
      }
    }

    await ride.save();

    const dDetails = ride.assignedDriverDetails || {};
    const driverDetails = {
      driverId: ride.assignedDriverId || dDetails.driverId || "",
      driverCode: dDetails.driverCode || "DRV-1001",
      name: ride.assignedDriverName || dDetails.name || "Driver",
      phone: dDetails.phone || "",
      rating: dDetails.rating ? `⭐ ${dDetails.rating} (Verified Driver)` : "⭐ 4.9 (Verified Driver)",
      vehicle: dDetails.vehicle ? `🚗 ${dDetails.vehicle}` : "🚗 Vehicle",
      numberPlate: dDetails.registrationNumber ? `🔢 ${dDetails.registrationNumber}` : "🔢 Registered"
    };

    const notifyPayload = {
      requestId: ride.requestId,
      requestType: "Schedule Ride",
      customerName: ride.passengerName,
      passengerName: ride.passengerName,
      passengerPhone: ride.passengerPhone,
      passengerEmail: ride.passengerEmail,
      fareFormatted: `Rs. ${Number(ride.fare || 0).toLocaleString()}`,
      fare: ride.fare,
      status: ride.status,
      pickup: ride.pickupLocation,
      destination: ride.dropoffLocation,
      driverDetails: driverDetails,
      driver: driverDetails
    };

    try {
      const io = req.app.get("io");
      if (io) {
        if (ride.status === "ACCEPTED") {
          io.emit("ride_accepted", notifyPayload);
          io.emit("ride-accepted", notifyPayload);
          console.log(`📡 Real-time event [ride_accepted] emitted for ${ride.requestId} by driver ${driverDetails.name}`);
        }
        io.emit("schedule-ride-updated", notifyPayload);
        // Also emit ride-updated so customer app can catch fare update
        io.emit("ride-updated", { ...notifyPayload, id: ride.requestId });
        console.log(`📡 Emitted [schedule-ride-updated] for ${ride.requestId}`);
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Schedule ride ${ride.requestId} updated`,
      ride,
      notificationPayload: notifyPayload
    });
  } catch (err) {
    console.error("Update Schedule Ride Error:", err);
    return res.status(500).json({ success: false, message: "Failed to update schedule ride", error: err.message });
  }
};
