const mongoose = require("mongoose");
const RideRequest = require("../schema/RideRequest");
const Driver = require("../schema/Driver");
const Customer = require("../schema/user");
const CustomerNotification = require("../schema/CustomerNotification");

// 1. Create a new Monthly Ride Booking (Customer Mobile App)
exports.createMonthlyRide = async (req, res) => {
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
      scheduleType,
      scheduleTime,
      customSchedule,
      vehicleTypeSelection,
      seatingArrangement,
      vehicleType,
      acPreference,
      passengersCount,
      fare,
      notes,
      customerId,
      tripType,
      genderPreference
    } = req.body;

    if (!passengerName || !passengerPhone || !pickupLocation || !dropoffLocation || !startingFrom) {
      return res.status(400).json({
        success: false,
        message: "Please provide all required ride details (Name, Phone, Pickup, Drop-off, Starting Date)"
      });
    }

    const newRide = new RideRequest({
      customerId: customerId || null,
      passengerName: passengerName.trim(),
      passengerPhone: passengerPhone.trim(),
      passengerEmail: passengerEmail ? passengerEmail.trim().toLowerCase() : null,
      pickupLocation: pickupLocation.trim(),
      dropoffLocation: dropoffLocation.trim(),
      startingFrom: startingFrom.trim(),
      timeToReach: timeToReach || "08:30 AM",
      timeToLeave: timeToLeave || "05:00 PM",
      scheduleType: scheduleType || "Mon - Fri",
      scheduleTime: scheduleTime || "9:00 AM",
      customSchedule: customSchedule || {},
      vehicleTypeSelection: vehicleTypeSelection || "Separate",
      seatingArrangement: seatingArrangement || "Sedan Executive",
      vehicleType: vehicleType || "Sedan",
      acPreference: acPreference || "AC",
      passengersCount: Number(passengersCount) || 1,
      fare: Number(fare) || 9500,
      notes: notes || "",
      tripType: tripType || customSchedule?.tripType || "One Way",
      genderPreference: genderPreference || "Both",
      status: "Pending Dispatch"
    });

    const savedRide = await newRide.save();

    // Emit real-time event to Admin Portal via Socket.IO
    try {
      const io = req.app.get("io");
      if (io) {
        const ridePayload = {
          _id: savedRide._id,
          id: savedRide._id,
          mongoId: savedRide._id,
          requestId: savedRide.requestId,
          passengerName: savedRide.passengerName,
          passengerPhone: savedRide.passengerPhone,
          passengerEmail: savedRide.passengerEmail,
          passenger: {
            name: savedRide.passengerName,
            phone: savedRide.passengerPhone,
            email: savedRide.passengerEmail
          },
          pickupLocation: savedRide.pickupLocation,
          dropoffLocation: savedRide.dropoffLocation,
          route: {
            pickup: savedRide.pickupLocation,
            dropoff: savedRide.dropoffLocation,
            summary: `${savedRide.pickupLocation} -> ${savedRide.dropoffLocation}`,
            passengers: savedRide.passengersCount || 1
          },
          scheduledTime: `${savedRide.startingFrom} ${savedRide.timeToReach || "08:00 AM"}`,
          timeToReach: savedRide.timeToReach,
          timeToLeave: savedRide.timeToLeave,
          startingFrom: savedRide.startingFrom,
          scheduleType: savedRide.scheduleType,
          scheduleTime: savedRide.scheduleTime,
          customSchedule: savedRide.customSchedule || {},
          selectedDays: (savedRide.customSchedule?.selectedDays && savedRide.customSchedule.selectedDays.length > 0)
            ? savedRide.customSchedule.selectedDays.join(', ')
            : savedRide.scheduleType || "Mon - Fri",
          tripType: savedRide.tripType || savedRide.customSchedule?.tripType || "One Way",
          genderPreference: savedRide.genderPreference || "Both",
          vehicleTypeSelection: savedRide.vehicleTypeSelection || "Separate",
          seatingArrangement: savedRide.seatingArrangement || "Sedan Executive",
          vehicle: {
            type: savedRide.vehicleType || "Sedan",
            seating: savedRide.seatingArrangement || "Sedan Executive",
            selection: savedRide.vehicleTypeSelection || "Separate",
            ac: savedRide.acPreference || "AC",
            label: `${savedRide.vehicleType || "Sedan"} • ${savedRide.acPreference || "AC"}`
          },
          vehicleType: savedRide.vehicleType || "Sedan",
          acPreference: savedRide.acPreference || "AC",
          passengersCount: savedRide.passengersCount || 1,
          fare: savedRide.fare || 9500,
          fareFormatted: `Rs. ${(savedRide.fare || 9500).toLocaleString()}`,
          notes: savedRide.notes || "",
          cnic: savedRide.cnic || "",
          status: savedRide.status,
          statusLabel: savedRide.status,
          isPending: savedRide.status === "Pending Dispatch",
          createdAt: savedRide.createdAt
        };

        io.emit("new-ride", ridePayload);
        io.emit("ride-update", { type: "NEW_RIDE", ride: ridePayload });
        console.log("📡 Real-time event emitted: new-ride", savedRide.requestId);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(201).json({
      success: true,
      message: "Monthly ride booking submitted successfully. Awaiting dispatch.",
      ride: savedRide
    });
  } catch (err) {
    console.error("Create Ride Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to submit monthly ride booking",
      error: err.message
    });
  }
};

// 2. Get All Rides (For Admin Dispatch Console & Live Trips)
exports.getAllRides = async (req, res) => {
  try {
    const { status, search } = req.query;
    let query = {};

    if (status) {
      if (status.toLowerCase() === "pending") {
        query.status = "Pending Dispatch";
      } else if (status.toLowerCase() === "assigned") {
        query.status = "ASSIGNED";
      } else {
        query.status = status;
      }
    }

    if (req.query.driverId) {
      query.$or = [
        { assignedDriverId: req.query.driverId },
        { assignedDriverId: new RegExp(req.query.driverId, "i") }
      ];
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

    const rides = await RideRequest.find(query).sort({ createdAt: -1 });

    const pendingCount = await RideRequest.countDocuments({ status: "Pending Dispatch" });
    const assignedCount = await RideRequest.countDocuments({ status: "ASSIGNED" });

    // Format rides to match any Admin Dispatch table structure directly
    const formattedRides = rides.map((ride) => ({
      _id: ride.requestId || ride._id,
      id: ride.requestId || ride._id,
      mongoId: ride._id,
      requestId: ride.requestId,
      passengerName: ride.passengerName,
      passengerPhone: ride.passengerPhone,
      passengerEmail: ride.passengerEmail,
      passenger: {
        name: ride.passengerName,
        phone: ride.passengerPhone,
        email: ride.passengerEmail
      },
      pickupLocation: ride.pickupLocation,
      dropoffLocation: ride.dropoffLocation,
      route: {
        pickup: ride.pickupLocation,
        dropoff: ride.dropoffLocation,
        summary: `${ride.pickupLocation} -> ${ride.dropoffLocation}`,
        passengers: ride.passengersCount || 1
      },
      scheduledTime: `${ride.startingFrom} ${ride.timeToReach || ride.scheduleTime || "08:00 AM"}`,
      timeToReach: ride.timeToReach,
      timeToLeave: ride.timeToLeave,
      startingFrom: ride.startingFrom,
      scheduleType: ride.scheduleType,
      scheduleTime: ride.scheduleTime,
      customSchedule: ride.customSchedule || {},
      selectedDays: (ride.customSchedule?.selectedDays && ride.customSchedule.selectedDays.length > 0)
        ? ride.customSchedule.selectedDays.join(', ')
        : ride.scheduleType || "Mon - Fri",
      vehicle: {
        type: ride.vehicleType || "Sedan",
        seating: ride.seatingArrangement || "Sedan Executive",
        selection: ride.vehicleTypeSelection || "Separate",
        ac: ride.acPreference || "AC",
        label: `${ride.vehicleType || "Sedan"} • ${ride.acPreference || "AC"}`
      },
      vehicleType: ride.vehicleType || "Sedan",
      acPreference: ride.acPreference || "AC",
      tripType: ride.tripType || ride.customSchedule?.tripType || "One Way",
      genderPreference: ride.genderPreference || "Both",
      vehicleTypeSelection: ride.vehicleTypeSelection || "Separate",
      seatingArrangement: ride.seatingArrangement || "Sedan Executive",
      passengersCount: ride.passengersCount || 1,
      fare: ride.fare || 9500,
      fareFormatted: `Rs. ${(ride.fare || 9500).toLocaleString()}`,
      notes: ride.notes || "",
      cnic: ride.cnic || "",
      status: ride.status,
      statusLabel: ride.status,
      isPending: ride.status === 'Pending Dispatch',
      isAssigned: ride.status === 'ASSIGNED',
      assignedDriver: ride.assignedDriverName || null,
      assignedDriverName: ride.assignedDriverName || null,
      createdAt: ride.createdAt
    }));

    return res.status(200).json({
      success: true,
      count: rides.length,
      pendingCount,
      assignedCount,
      data: formattedRides,
      rides: formattedRides,
      requests: formattedRides
    });
  } catch (err) {
    console.error("Get Rides Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch ride requests",
      error: err.message
    });
  }
};

// 3. Get Single Ride Details
exports.getRideById = async (req, res) => {
  try {
    const ride = await RideRequest.findById(req.params.id);
    if (!ride) {
      return res.status(404).json({
        success: false,
        message: "Ride request not found"
      });
    }

    return res.status(200).json({
      success: true,
      ride
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: "Failed to fetch ride details",
      error: err.message
    });
  }
};

// 4. Dispatch / Assign Driver to Ride (Admin Action)
exports.dispatchRide = async (req, res) => {
  try {
    const { driverId, driverName } = req.body;
    const rideId = req.params.id;

    // Step 1: Find the ride using either MongoDB _id or requestId string (e.g. REQ-8034)
    let existingRide = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      existingRide = await RideRequest.findById(rideId).catch(() => null);
    }
    if (!existingRide) {
      existingRide = await RideRequest.findOne({ requestId: rideId }).catch(() => null);
    }

    if (!existingRide) {
      return res.status(404).json({
        success: false,
        message: `Ride request '${rideId}' not found`
      });
    }

    // Step 2: Resolve driver name
    let assignedName = driverName;
    if (driverId && !assignedName) {
      try {
        let driverObj = null;
        if (mongoose.Types.ObjectId.isValid(driverId)) {
          driverObj = await Driver.findById(driverId).catch(() => null);
        }
        if (!driverObj) {
          driverObj = await Driver.findOne({ driverReferenceId: driverId }).catch(() => null);
        }
        if (driverObj) {
          assignedName = driverObj.Name || `${driverObj.firstName || ''} ${driverObj.lastName || ''}`.trim();
        }
      } catch (_) { /* ignore */ }
    }

    // Step 3: Update using actual MongoDB _id (not the requestId string)
    const updatedRide = await RideRequest.findByIdAndUpdate(
      existingRide._id,
      {
        status: "ASSIGNED",
        assignedDriverId: driverId || null,
        assignedDriverName: assignedName || "Assigned Driver"
      },
      { returnDocument: 'after', new: true }
    );

    if (!updatedRide) {
      return res.status(404).json({
        success: false,
        message: "Ride request not found after update"
      });
    }

    // Emit real-time update for dispatch
    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("ride-dispatched", updatedRide);
        io.emit("ride-update", { type: "RIDE_DISPATCHED", ride: updatedRide });
        console.log("📡 Real-time event emitted: ride-dispatched", updatedRide.requestId);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: `Ride ${updatedRide.requestId} successfully dispatched to driver`,
      ride: updatedRide
    });
  } catch (err) {
    console.error("Dispatch Ride Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to dispatch ride",
      error: err.message
    });
  }
};

// 5. Get Customer's Own Rides
exports.getCustomerRides = async (req, res) => {
  try {
    const { customerId, phone, email } = req.query;
    let query = {};

    if (customerId) query.customerId = customerId;
    if (phone) query.passengerPhone = phone;
    if (email) query.passengerEmail = email.toLowerCase();

    const rides = await RideRequest.find(query).sort({ createdAt: -1 });

    return res.status(200).json({
      success: true,
      count: rides.length,
      rides
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: "Failed to fetch customer rides",
      error: err.message
    });
  }
};

// 6. Update Ride Details / Fare / Driver Status (Admin & Driver Action)
exports.updateRide = async (req, res) => {
  try {
    const rideId = req.params.id;
    const { fare, status, notes, driverId, driverName } = req.body;

    let updatedRide = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      updatedRide = await RideRequest.findById(rideId).catch(() => null);
    }
    if (!updatedRide) {
      updatedRide = await RideRequest.findOne({ requestId: rideId }).catch(() => null);
    }

    if (!updatedRide) {
      return res.status(404).json({
        success: false,
        message: `Ride request ${rideId} not found`
      });
    }

    if (fare !== undefined) updatedRide.fare = Number(fare);
    if (status) updatedRide.status = status;
    if (notes !== undefined) updatedRide.notes = notes;

    const targetDriverId = driverId || req.body.assignedDriverId;
    if (targetDriverId) {
      updatedRide.assignedDriverId = targetDriverId;
      try {
        let driverObj = null;
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

          updatedRide.assignedDriverName = dName;
          updatedRide.assignedDriverDetails = {
            driverId: driverObj._id,
            driverCode: driverObj.driverReferenceId || driverObj.driverCode || `DRV-${Date.now()}`,
            name: dName,
            phone: driverObj.PhoneNumber || driverObj.phone || "+92 3000000000",
            rating: driverObj.rating || 4.9,
            vehicle: `${vMake} ${vModel}${vColor}`.trim(),
            registrationNumber: vDetails.registrationNumber || vDetails.numberPlate || "REGISTERED"
          };
        } else if (driverName) {
          updatedRide.assignedDriverName = driverName;
        }
      } catch (_) {
        if (driverName) updatedRide.assignedDriverName = driverName;
      }
    }

    await updatedRide.save();

    // Prepare complete payload for real-time customer notification
    const dDetails = updatedRide.assignedDriverDetails || {};
    const driverDetails = {
      driverId: updatedRide.assignedDriverId || dDetails.driverId || "",
      driverCode: dDetails.driverCode || "DRV-1001",
      name: updatedRide.assignedDriverName || dDetails.name || "Driver",
      phone: dDetails.phone || "",
      rating: dDetails.rating ? `⭐ ${dDetails.rating} (Verified Driver)` : "⭐ 4.9 (Verified Driver)",
      vehicle: dDetails.vehicle ? `🚗 ${dDetails.vehicle}` : "🚗 Vehicle",
      numberPlate: dDetails.registrationNumber ? `🔢 ${dDetails.registrationNumber}` : "🔢 Registered"
    };

    const notifyPayload = {
      requestId: updatedRide.requestId,
      customerName: updatedRide.passengerName,
      passengerName: updatedRide.passengerName,
      passengerPhone: updatedRide.passengerPhone,
      passengerEmail: updatedRide.passengerEmail,
      fareFormatted: `Rs. ${Number(updatedRide.fare || 0).toLocaleString()}`,
      fare: updatedRide.fare,
      status: updatedRide.status,
      pickup: updatedRide.pickupLocation,
      destination: updatedRide.dropoffLocation,
      driverDetails: driverDetails,
      driver: driverDetails
    };

    // Emit Real-time Socket.IO notification ONLY when Driver ACCEPTS
    try {
      const io = req.app.get("io");
      if (io) {
        if (updatedRide.status === "ACCEPTED") {
          io.emit("ride_accepted", notifyPayload);
          io.emit("ride-accepted", notifyPayload);
          console.log(`📡 Real-time event [ride_accepted] emitted for ${updatedRide.requestId} by driver ${driverDetails.name}`);
        }
        io.emit("ride-updated", notifyPayload);
      }
    } catch (socketErr) {
      console.warn("Socket emit error:", socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: `Ride ${updatedRide.requestId} status updated to ${updatedRide.status}`,
      ride: updatedRide,
      notificationPayload: notifyPayload
    });
  } catch (err) {
    console.error("Update Ride Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to update ride",
      error: err.message
    });
  }
};

// 7. Report Driver Unavailable (Admin / Driver / Test Trigger)
exports.reportDriverUnavailable = async (req, res) => {
  try {
    const rideId = req.params.id || req.body.rideId;
    const { reportedReason, affectedDate, affectedTime, additionalDetails } = req.body;

    let ride = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      ride = await RideRequest.findById(rideId).catch(() => null);
    }
    if (!ride) {
      ride = await RideRequest.findOne({ requestId: rideId }).catch(() => null);
    }
    if (!ride) {
      // Fallback: pick latest assigned or pending ride
      ride = await RideRequest.findOne().sort({ createdAt: -1 });
    }

    if (!ride) {
      return res.status(404).json({
        success: false,
        message: "No active ride found to report driver unavailable"
      });
    }

    const defaultReason = reportedReason || "Vehicle Issue";
    const defaultDate = affectedDate || ride.startingFrom || "May 21, 2026";
    const defaultTime = affectedTime || `${ride.timeToReach || "08:00 AM"} - ${ride.timeToLeave || "10:00 AM"}`;
    const defaultDetails = additionalDetails || "Driver is unavailable due to a sudden mechanical issue with the vehicle. We apologize for the inconvenience and are working to find a replacement driver immediately. The issue is severe enough to prevent the ride.";

    ride.status = "Driver Unavailable";
    ride.driverIssue = {
      reportedReason: defaultReason,
      affectedDate: defaultDate,
      affectedTime: defaultTime,
      additionalDetails: defaultDetails,
      reportedAt: new Date()
    };

    await ride.save();

    const notifyPayload = {
      title: "Driver Unavailable",
      subtitle: "Your assigned driver is unavailable for this ride.",
      rideId: ride.requestId || ride._id,
      mongoId: ride._id,
      customerId: ride.customerId || "",
      passengerName: ride.passengerName,
      passengerPhone: ride.passengerPhone,
      passengerEmail: ride.passengerEmail,
      affectedDate: defaultDate,
      affectedTime: defaultTime,
      reportedReason: defaultReason,
      additionalDetails: defaultDetails,
      status: "Driver Unavailable",
      createdAt: new Date().toISOString()
    };

    try {
      const io = req.app.get("io");
      if (io) {
        if (ride.customerId) {
          io.to(`customer_${ride.customerId}`).emit("driver-unavailable", notifyPayload);
          io.to(String(ride.customerId)).emit("driver-unavailable", notifyPayload);
        }
        if (ride.passengerPhone) {
          io.to(`customer_${ride.passengerPhone}`).emit("driver-unavailable", notifyPayload);
          io.to(String(ride.passengerPhone)).emit("driver-unavailable", notifyPayload);
        }
        io.to(`ride_${ride._id}`).emit("driver-unavailable", notifyPayload);
        io.to(`ride_${ride.requestId}`).emit("driver-unavailable", notifyPayload);
        io.emit("driver-unavailable", notifyPayload);
        console.log(`📡 Emitted [driver-unavailable] for Ride ${ride.requestId}`);
      }
    } catch (socketErr) {
      console.warn("Socket emit error:", socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: `Driver unavailable issue reported for Ride ${ride.requestId}`,
      ride,
      notification: notifyPayload
    });
  } catch (err) {
    console.error("Report Driver Unavailable Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to report driver unavailable issue",
      error: err.message
    });
  }
};

// 8. Request Replacement Driver (Customer Mobile App)
exports.requestReplacementDriver = async (req, res) => {
  try {
    const rideId = req.params.id || req.body.rideId;
    const { vehicleArrangement, vehicleType, genderPreference, acPreference, additionalNotes } = req.body;

    let ride = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      ride = await RideRequest.findById(rideId).catch(() => null);
    }
    if (!ride) {
      ride = await RideRequest.findOne({ requestId: rideId }).catch(() => null);
    }
    if (!ride) {
      ride = await RideRequest.findOne({ status: "Driver Unavailable" }).sort({ updatedAt: -1 });
    }

    if (!ride) {
      return res.status(404).json({
        success: false,
        message: "Ride request not found for replacement request"
      });
    }

    ride.status = "Replacement Requested";
    ride.replacementPreferences = {
      vehicleArrangement: vehicleArrangement || "Separate",
      vehicleType: vehicleType || "Sedan Executive",
      genderPreference: genderPreference || "Male Only",
      acPreference: acPreference || "AC",
      additionalNotes: additionalNotes || "",
      requestedAt: new Date()
    };

    await ride.save();

    const adminPayload = {
      rideId: ride.requestId || ride._id,
      mongoId: ride._id,
      passengerName: ride.passengerName,
      passengerPhone: ride.passengerPhone,
      status: "Replacement Requested",
      preferences: ride.replacementPreferences,
      affectedDate: ride.driverIssue?.affectedDate || ride.startingFrom || "May 21, 2026",
      affectedTime: ride.driverIssue?.affectedTime || `${ride.timeToReach || "08:00 AM"} - ${ride.timeToLeave || "10:00 AM"}`,
      createdAt: new Date().toISOString()
    };

    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("replacement-requested", adminPayload);
        io.emit("ride-update", { type: "REPLACEMENT_REQUESTED", ride: adminPayload });
        console.log(`📡 Emitted [replacement-requested] for Ride ${ride.requestId}`);
      }
    } catch (socketErr) {
      console.warn("Socket emit error:", socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: "Replacement driver request submitted successfully to Admin Console",
      ride
    });
  } catch (err) {
    console.error("Request Replacement Driver Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to submit replacement request",
      error: err.message
    });
  }
};

// 9. Get Customer Notifications (Include Driver Unavailable Issues & Persistent History)
exports.getCustomerNotifications = async (req, res) => {
  try {
    const { customerId, phone, email } = req.query;

    let queryConds = [];
    if (customerId) queryConds.push({ customerId: customerId });
    if (phone) queryConds.push({ passengerPhone: phone });
    if (email) queryConds.push({ passengerEmail: email });

    const query = queryConds.length > 0 ? { $or: queryConds } : {};

    // 1. Fetch persistent notifications from CustomerNotification collection
    const storedNotifs = await CustomerNotification.find(query).sort({ createdAt: -1 }).lean().catch(() => []);

    // 2. Also fetch active rides for customer from RideRequest collection
    const customerRides = await RideRequest.find(query).sort({ updatedAt: -1 }).lean().catch(() => []);

    // 3. Generate notifications dynamically for any rides that exist
    const generatedNotifs = [];
    for (const r of customerRides) {
      const rId = r.requestId || r._id.toString();
      const fareText = r.fare ? `Rs. ${Number(r.fare).toLocaleString()}` : "Rs. 9,500";

      // Driver Issue / Unavailable
      if (r.status === "Driver Unavailable" || r.status === "Replacement Requested" || r.driverIssue) {
        generatedNotifs.push({
          title: "Driver Unavailable",
          subtitle: "Your assigned driver is unavailable for this ride.",
          rideId: rId,
          requestId: rId,
          mongoId: r._id,
          customerId: r.customerId,
          passengerPhone: r.passengerPhone,
          affectedDate: r.driverIssue?.affectedDate || r.startingFrom || "May 21, 2026",
          affectedTime: r.driverIssue?.affectedTime || `${r.timeToReach || "08:00 AM"} - ${r.timeToLeave || "10:00 AM"}`,
          reportedReason: r.driverIssue?.reportedReason || "Vehicle Issue",
          additionalDetails: r.driverIssue?.additionalDetails || "Driver is unavailable due to a sudden mechanical issue with the vehicle.",
          status: "Driver Unavailable",
          isDriverUnavailable: true,
          pickup: r.pickupLocation,
          destination: r.dropoffLocation,
          createdAt: r.updatedAt || r.createdAt
        });
      }

      // Fare / Price Update
      if (r.fare || r.status === "Pending Dispatch" || r.status === "Fare Accepted" || r.status === "Fare Rejected") {
        generatedNotifs.push({
          title: "💰 Ride Price Updated!",
          subtitle: `Admin has set your ride price to ${fareText}.`,
          rideId: rId,
          requestId: rId,
          mongoId: r._id,
          customerId: r.customerId,
          passengerPhone: r.passengerPhone,
          fareFormatted: fareText,
          pickup: r.pickupLocation,
          destination: r.dropoffLocation,
          status: "PRICE_UPDATED",
          fareResponseStatus: r.status === "Fare Accepted" ? "Fare Accepted" : r.status === "Fare Rejected" ? "Fare Rejected" : "Pending",
          createdAt: r.updatedAt || r.createdAt
        });
      }
    }

    // Merge stored and generated notifications, deduplicating by rideId + status + fare
    const allNotifs = [...storedNotifs, ...generatedNotifs];
    const seenKeys = new Set();
    const finalNotifications = [];

    for (const n of allNotifs) {
      const rId = n.rideId || n.requestId || n.id || "";
      const st = n.status || "";
      const fare = n.fareFormatted || "";
      const key = `${rId}_${st}_${fare}`;

      if (!seenKeys.has(key)) {
        seenKeys.add(key);
        finalNotifications.push({
          id: rId,
          requestId: rId,
          rideId: rId,
          mongoId: n.mongoId || rId,
          title: n.title || "Ride Notification",
          subtitle: n.subtitle || "",
          status: st,
          fareFormatted: fare,
          pickup: n.pickup || n.pickupLocation || "Pickup Point",
          destination: n.destination || n.dropoffLocation || "Destination Point",
          isDriverUnavailable: n.isDriverUnavailable || false,
          driverName: n.driverName || "",
          driverPhone: n.driverPhone || "",
          driverCode: n.driverCode || "",
          rating: n.rating || "",
          vehicle: n.vehicle || "",
          numberPlate: n.numberPlate || "",
          affectedDate: n.affectedDate || "",
          affectedTime: n.affectedTime || "",
          reportedReason: n.reportedReason || "",
          additionalDetails: n.additionalDetails || "",
          createdAt: n.createdAt || new Date().toISOString()
        });
      }
    }

    // Sort newest first
    finalNotifications.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));

    return res.status(200).json({
      success: true,
      count: finalNotifications.length,
      notifications: finalNotifications,
      data: finalNotifications
    });
  } catch (err) {
    console.error("Get Customer Notifications Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch customer notifications",
      error: err.message
    });
  }
};

// 10. Respond to Fare Update (Customer accepts or rejects updated price)
exports.respondToFare = async (req, res) => {
  try {
    const { rideId, action, customerName } = req.body;

    if (!rideId || !action) {
      return res.status(400).json({
        success: false,
        message: "Ride ID and action (ACCEPT/REJECT) are required."
      });
    }

    let ride = null;
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      ride = await RideRequest.findById(rideId).catch(() => null);
    }
    if (!ride) {
      ride = await RideRequest.findOne({ requestId: rideId }).catch(() => null);
    }
    if (!ride) {
      return res.status(404).json({
        success: false,
        message: `Ride ${rideId} not found.`
      });
    }

    const isAccepted = action.toUpperCase() === "ACCEPT";
    const newStatus = isAccepted ? "Fare Accepted" : "Fare Rejected";
    const name = customerName || ride.passengerName || "Customer";
    const fareFormatted = ride.fare ? `Rs. ${ride.fare.toLocaleString()}` : "Rs. 9,500";

    ride.status = newStatus;
    ride.fareStatus = newStatus;
    await ride.save();

    // Prepare socket notification payload specifically for Admin Portal
    const adminNotification = {
      rideId: ride.requestId || ride._id,
      requestId: ride.requestId || ride._id,
      mongoId: ride._id,
      customerName: name,
      passengerPhone: ride.passengerPhone,
      action: isAccepted ? "ACCEPTED" : "REJECTED",
      status: newStatus,
      fare: ride.fare,
      fareFormatted: fareFormatted,
      title: isAccepted ? "✅ Fare Approved by Customer" : "❌ Fare Rejected by Customer",
      message: isAccepted
        ? `Customer ${name} has ACCEPTED the updated ride price (${fareFormatted}). Ready for driver assignment.`
        : `Customer ${name} has REJECTED the updated ride price (${fareFormatted}).`,
      createdAt: new Date().toISOString()
    };

    // Emit real-time Socket.IO events to Admin Portal
    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("customer-fare-response", adminNotification);
        io.emit("admin-notification", adminNotification);
        io.emit("new-admin-notification", adminNotification);
        io.emit("ride-update", { type: "FARE_RESPONSE", ride: adminNotification });
        console.log(`📡 Real-time event [customer-fare-response] emitted to Admin Console for Ride ${ride.requestId}: ${adminNotification.action}`);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: isAccepted
        ? `Fare accepted successfully. Admin notified!`
        : `Fare rejected. Admin notified!`,
      ride,
      notification: adminNotification
    });
  } catch (err) {
    console.error("Respond To Fare Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to respond to fare update",
      error: err.message
    });
  }
};


