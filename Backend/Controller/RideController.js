const mongoose = require("mongoose");
const RideRequest = require("../schema/RideRequest");
const Driver = require("../schema/Driver");
const Customer = require("../schema/user");
const CustomerNotification = require("../schema/CustomerNotification");
const SuggestedRoute = require("../schema/SuggestedRoute");
const Vehicle = require("../schema/Vehicle");
const DriverNotification = require("../schema/DriverNotification");

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
            label: `${savedRide.vehicleType || "Sedan"} â€¢ ${savedRide.acPreference || "AC"}`
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
        console.log("ðŸ“¡ Real-time event emitted: new-ride", savedRide.requestId);
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

    const rides = await RideRequest.find(query).sort({ createdAt: -1 }).lean();

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
        label: `${ride.vehicleType || "Sedan"} â€¢ ${ride.acPreference || "AC"}`
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
      assignedDriver: ride.assignedDriverName || ride.assignedDriver || null,
      assignedDriverName: ride.assignedDriverName || ride.assignedDriver || null,
      assignedDriverId: ride.assignedDriverId || ride.driverId || ride.driver || null,
      driverId: ride.driverId || ride.assignedDriverId || ride.driver || null,
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

    // Persist CustomerNotification for Driver Assigned
    try {
      await CustomerNotification.findOneAndUpdate(
        { notificationId: `${updatedRide.requestId}_ACCEPTED` },
        {
          customerId: updatedRide.customerId || updatedRide.passengerPhone,
          passengerPhone: updatedRide.passengerPhone,
          passengerEmail: updatedRide.passengerEmail || "",
          rideId: updatedRide.requestId,
          mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
          notificationId: `${updatedRide.requestId}_ACCEPTED`,
          title: "🚗 Driver Assigned!",
          subtitle: `Driver ${assignedName || "A driver"} has been assigned to your ride (${updatedRide.requestId}).`,
          status: "ACCEPTED",
          fareFormatted: updatedRide.fare ? `Rs. ${Number(updatedRide.fare).toLocaleString()}` : "",
          pickup: updatedRide.pickupLocation || "Pickup Point",
          destination: updatedRide.dropoffLocation || "Destination Point",
          driverName: assignedName || "Assigned Driver",
          driverPhone: "",
          driverCode: driverId || "",
          rating: "⭐ 4.9 (Verified Driver)",
          vehicle: "🚗 Assigned Vehicle",
          numberPlate: "REGISTERED",
          isRead: false,
          isDismissed: false
        },
        { upsert: true, new: true }
      );
    } catch (notifErr) {
      console.warn("Failed saving customer notification for dispatched ride:", notifErr.message);
    }

    // Emit real-time update for dispatch
    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("ride-dispatched", updatedRide);
        io.emit("ride-update", { type: "RIDE_DISPATCHED", ride: updatedRide });
        io.emit("ride_accepted", {
          requestId: updatedRide.requestId,
          customerId: updatedRide.customerId,
          passengerName: updatedRide.passengerName,
          passengerPhone: updatedRide.passengerPhone,
          status: "ACCEPTED",
          driverDetails: {
            name: assignedName || "Assigned Driver",
            driverCode: driverId || "DRV-ASSIGNED",
            vehicle: "Assigned Vehicle"
          }
        });
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

    const rides = await RideRequest.find(query).sort({ createdAt: -1 }).lean();

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
      customerId: updatedRide.customerId,
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

    // Persist CustomerNotification for Driver Accepted or Assigned (ONLY Driver Details)
    if (updatedRide.status === "ACCEPTED" || updatedRide.status === "Accepted" || updatedRide.status === "ASSIGNED") {
      try {
        await CustomerNotification.findOneAndUpdate(
          { notificationId: `${updatedRide.requestId}_ACCEPTED` },
          {
            customerId: updatedRide.customerId || updatedRide.passengerPhone,
            passengerPhone: updatedRide.passengerPhone,
            passengerEmail: updatedRide.passengerEmail || "",
            rideId: updatedRide.requestId,
            mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
            notificationId: `${updatedRide.requestId}_ACCEPTED`,
            title: "🚗 Driver Accepted Ride!",
            subtitle: `Driver ${driverDetails.name} has accepted your ride (${updatedRide.requestId}). Tap to view driver details.`,
            status: "ACCEPTED",
            fareFormatted: notifyPayload.fareFormatted,
            pickup: updatedRide.pickupLocation || "Pickup Point",
            destination: updatedRide.dropoffLocation || "Destination Point",
            driverName: driverDetails.name,
            driverPhone: driverDetails.phone,
            driverCode: driverDetails.driverCode,
            rating: driverDetails.rating,
            vehicle: driverDetails.vehicle,
            numberPlate: driverDetails.numberPlate,
            isRead: false,
            isDismissed: false
          },
          { upsert: true, new: true }
        );
      } catch (notifErr) {
        console.warn("Failed saving customer notification for accepted ride:", notifErr.message);
      }
    }

    // When Driver COMPLETES Ride: Send Payment Notification & Retire Accepted Notification
    if (updatedRide.status === "COMPLETED" || updatedRide.status === "Completed") {
      try {
        // Mark old accepted notification for this ride as dismissed so customer now sees payment notification
        await CustomerNotification.updateMany(
          { rideId: updatedRide.requestId, status: "ACCEPTED" },
          { isDismissed: true }
        ).catch(() => {});

        await CustomerNotification.findOneAndUpdate(
          { notificationId: `${updatedRide.requestId}_COMPLETED` },
          {
            customerId: updatedRide.customerId || updatedRide.passengerPhone,
            passengerPhone: updatedRide.passengerPhone,
            passengerEmail: updatedRide.passengerEmail || "",
            rideId: updatedRide.requestId,
            mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
            notificationId: `${updatedRide.requestId}_COMPLETED`,
            title: "💳 Ride Completed - Pay Fare",
            subtitle: `Your ride ${updatedRide.requestId} is complete. Please tap to submit payment of ${notifyPayload.fareFormatted}.`,
            status: "COMPLETED",
            fareFormatted: notifyPayload.fareFormatted,
            pickup: updatedRide.pickupLocation || "Pickup Point",
            destination: updatedRide.dropoffLocation || "Destination Point",
            driverName: driverDetails.name,
            driverPhone: driverDetails.phone,
            driverCode: driverDetails.driverCode,
            rating: driverDetails.rating,
            vehicle: driverDetails.vehicle,
            numberPlate: driverDetails.numberPlate,
            isRead: false,
            isDismissed: false
          },
          { upsert: true, new: true }
        );
      } catch (notifErr) {
        console.warn("Failed saving customer notification for completed ride:", notifErr.message);
      }
    }

    // Emit Real-time Socket.IO events
    try {
      const io = req.app.get("io");
      if (io) {
        if (updatedRide.status === "ACCEPTED" || updatedRide.status === "Accepted") {
          io.emit("ride_accepted", notifyPayload);
          io.emit("ride-accepted", notifyPayload);
          console.log(`📡 Real-time event [ride_accepted] emitted for ${updatedRide.requestId} by driver ${driverDetails.name}`);
        }
        if (updatedRide.status === "COMPLETED" || updatedRide.status === "Completed") {
          io.emit("ride_completed", notifyPayload);
          io.emit("ride-completed", notifyPayload);
          console.log(`📡 Real-time event [ride_completed] emitted for ${updatedRide.requestId}`);
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
        console.log(`ðŸ“¡ Emitted [driver-unavailable] for Ride ${ride.requestId}`);
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
        console.log(`ðŸ“¡ Emitted [replacement-requested] for Ride ${ride.requestId}`);
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

// 9. Get Customer Notifications (Include Driver Accepted, Driver Unavailable Issues & Persistent History)
exports.getCustomerNotifications = async (req, res) => {
  try {
    const { customerId, phone, email } = req.query;

    let queryConds = [];
    if (customerId) {
      queryConds.push({ customerId: customerId });
      if (mongoose.Types.ObjectId.isValid(customerId)) {
        queryConds.push({ customerId: new mongoose.Types.ObjectId(customerId) });
      }
    }
    if (phone) {
      const rawPhone = String(phone).trim();
      const digitsOnly = rawPhone.replace(/\D/g, "");
      const core = digitsOnly.replace(/^92/, "").replace(/^0/, "");

      const variations = [
        rawPhone,
        digitsOnly,
        core,
        `0${core}`,
        `+92${core}`,
        `92${core}`,
        `+92 ${core}`,
        `0${core.slice(0, 3)} ${core.slice(3)}`
      ];

      for (const v of variations) {
        if (v && v.length >= 7) {
          queryConds.push({ passengerPhone: v });
          queryConds.push({ "passenger.phone": v });
        }
      }
      if (core && core.length >= 9) {
        queryConds.push({ passengerPhone: new RegExp(`${core}$`) });
        queryConds.push({ "passenger.phone": new RegExp(`${core}$`) });
      }
    }
    if (email) {
      const cleanEmail = email.trim();
      queryConds.push({ passengerEmail: new RegExp(`^${cleanEmail}$`, "i") });
      queryConds.push({ "passenger.email": new RegExp(`^${cleanEmail}$`, "i") });
    }

    const query = queryConds.length > 0 ? { $or: queryConds } : {};

    // 1. Fetch persistent notifications from CustomerNotification collection (exclude dismissed)
    const storedNotifs = await CustomerNotification.find({
      ...(queryConds.length > 0 ? query : {}),
      isDismissed: { $ne: true }
    }).sort({ createdAt: -1 }).lean().catch(() => []);

    // Also get set of dismissed notification keys so dynamically generated items stay dismissed
    const dismissedNotifs = await CustomerNotification.find({
      ...(queryConds.length > 0 ? query : {}),
      isDismissed: true
    }).lean().catch(() => []);
    const dismissedKeys = new Set(dismissedNotifs.map(d => `${d.rideId}_${d.status}`));
    const dismissedRideIds = new Set(dismissedNotifs.map(d => d.rideId));

    // 2. Fetch active rides for customer from RideRequest and ScheduleRide collections
    const customerRides = await RideRequest.find(queryConds.length > 0 ? query : {}).sort({ updatedAt: -1 }).lean().catch(() => []);
    let scheduleRides = [];
    try {
      const ScheduleRide = require("../schema/ScheduleRide");
      scheduleRides = await ScheduleRide.find(queryConds.length > 0 ? query : {}).sort({ updatedAt: -1 }).lean().catch(() => []);
    } catch (_) {}
    const allCustomerRides = [...customerRides, ...scheduleRides];

    // 3. Generate notifications dynamically for actionable active events
    const generatedNotifs = [];
    for (const r of allCustomerRides) {
      const rId = r.requestId || r._id.toString();
      const fareText = r.fare ? `Rs. ${Number(r.fare).toLocaleString()}` : "Rs. 9,500";

      // A) Driver Accepted / Assigned (ONLY Driver Details notification)
      if (r.status === "ACCEPTED" || r.status === "Accepted" || r.status === "ASSIGNED" || r.status === "Driver Assigned") {
        const notifKey = `${rId}_ACCEPTED`;
        if (!dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId)) {
          const dDetails = r.assignedDriverDetails || {};
          const driverName = r.assignedDriverName || dDetails.name || "Driver";
          const driverPhone = dDetails.phone || "";
          const driverVehicle = dDetails.vehicle || (r.vehicleType ? `🚗 ${r.vehicleType}` : "🚗 Vehicle");
          const driverPlate = dDetails.registrationNumber || "REGISTERED";
          const driverRating = dDetails.rating ? `⭐ ${dDetails.rating} (Verified Driver)` : "⭐ 4.9 (Verified Driver)";

          generatedNotifs.push({
            id: `${rId}_accepted`,
            notificationId: `${rId}_accepted`,
            title: "🚗 Driver Accepted Ride!",
            subtitle: `Driver ${driverName} has accepted your ride (${rId}). Tap to view driver details.`,
            rideId: rId,
            requestId: rId,
            mongoId: r._id ? r._id.toString() : rId,
            customerId: r.customerId,
            passengerPhone: r.passengerPhone,
            passengerEmail: r.passengerEmail,
            fareFormatted: fareText,
            pickup: r.pickupLocation || "Pickup Point",
            destination: r.dropoffLocation || "Destination Point",
            status: "ACCEPTED",
            driverName: driverName,
            driverPhone: driverPhone,
            driverCode: dDetails.driverCode || r.assignedDriverId || "DRV-VERIFIED",
            rating: driverRating,
            vehicle: driverVehicle,
            numberPlate: driverPlate,
            createdAt: r.updatedAt || r.createdAt || new Date().toISOString()
          });
        }
      }

      // B) Driver Issue / Unavailable
      if (r.status === "Driver Unavailable" || r.status === "Replacement Requested" || r.driverIssue) {
        const notifKey = `${rId}_driver_unavailable`;
        if (!dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId)) {
          generatedNotifs.push({
            id: `${rId}_driver_unavailable`,
            notificationId: `${rId}_driver_unavailable`,
            title: "Driver Unavailable",
            subtitle: "Your assigned driver is unavailable for this ride.",
            rideId: rId,
            requestId: rId,
            mongoId: r._id ? r._id.toString() : rId,
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
      }

      // C) Fare / Price Update - ONLY if status is explicitly PRICE_UPDATED or Pending Dispatch with pending fare approval
      if (r.status === "PRICE_UPDATED" || (r.status === "Pending Dispatch" && r.fare && r.fareResponseStatus === "Pending")) {
        const notifKey = `${rId}_price_updated`;
        if (!dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId)) {
          generatedNotifs.push({
            id: `${rId}_price_updated`,
            notificationId: `${rId}_price_updated`,
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has set your ride price to ${fareText}.`,
            rideId: rId,
            requestId: rId,
            mongoId: r._id ? r._id.toString() : rId,
            customerId: r.customerId,
            passengerPhone: r.passengerPhone,
            fareFormatted: fareText,
            pickup: r.pickupLocation,
            destination: r.dropoffLocation,
            status: "PRICE_UPDATED",
            fareResponseStatus: "Pending",
            createdAt: r.updatedAt || r.createdAt
          });
        }
      }

      // D) Ride Completed (Payment Notification ONLY when driver marks completed)
      if (r.status === "COMPLETED" || r.status === "Completed") {
        const notifKey = `${rId}_COMPLETED`;
        if (!dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId)) {
          generatedNotifs.push({
            id: `${rId}_completed`,
            notificationId: `${rId}_completed`,
            title: "💳 Ride Completed - Pay Fare",
            subtitle: `Your ride ${rId} has been completed. Tap to submit payment of ${fareText}.`,
            rideId: rId,
            requestId: rId,
            mongoId: r._id ? r._id.toString() : rId,
            customerId: r.customerId,
            passengerPhone: r.passengerPhone,
            status: "COMPLETED",
            fareFormatted: fareText,
            pickup: r.pickupLocation,
            destination: r.dropoffLocation,
            createdAt: r.updatedAt || r.createdAt
          });
        }
      }
    }

    // Merge stored and generated notifications
    const allNotifs = [...storedNotifs, ...generatedNotifs];

    // Find all rides that are completed so their old "Driver Accepted" notifications are retired
    const completedRideIds = new Set();
    for (const n of allNotifs) {
      if (n.status === "COMPLETED" || n.status === "Completed") {
        const rId = n.rideId || n.requestId || "";
        if (rId) completedRideIds.add(rId);
      }
    }

    const seenKeys = new Set();
    const finalNotifications = [];

    for (const n of allNotifs) {
      const rId = n.rideId || n.requestId || n.id || "";
      const st = n.status || "";

      // When ride is COMPLETED, only show the Payment notification (hide old ACCEPTED notification)
      if ((st === "ACCEPTED" || st === "Accepted") && completedRideIds.has(rId)) {
        continue;
      }

      const key = `${rId}_${st}`;

      if (!seenKeys.has(key)) {
        seenKeys.add(key);
        const uniqueId = n.notificationId || (n._id ? n._id.toString() : `${rId}_${st}`);
        finalNotifications.push({
          id: uniqueId,
          notificationId: uniqueId,
          requestId: rId,
          rideId: rId,
          mongoId: n.mongoId || (n._id ? n._id.toString() : rId),
          title: st === "COMPLETED" || st === "Completed" ? "💳 Ride Completed - Pay Fare" : (n.title || "Ride Notification"),
          subtitle: st === "COMPLETED" || st === "Completed" ? `Your ride ${rId} is complete. Please tap to submit payment of ${n.fareFormatted || ""}.` : (n.subtitle || ""),
          status: st,
          fareFormatted: n.fareFormatted || "",
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

// 10. Respond to Fare Update
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
      title: isAccepted ? "âœ… Fare Approved by Customer" : "âŒ Fare Rejected by Customer",
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

      // If customer accepted, also notify assigned Driver
      if (isAccepted) {
        const dDetails = ride.assignedDriverDetails || {};
        const targetDriverId = ride.assignedDriverId || dDetails.driverId || null;
        const targetDriverName = ride.assignedDriverName || dDetails.name || "Driver";
        const targetDriverRef = dDetails.driverCode || ride.assignedDriverId || "";
        const rId = ride.requestId || ride._id.toString();

        const driverNotifData = {
          driverId: targetDriverId,
          driverReferenceId: targetDriverRef,
          driverName: targetDriverName,
          rideId: rId,
          notificationId: `${rId}_FARE_ACCEPTED`,
          title: "🎉 Customer Accepted Ride!",
          subtitle: `Customer ${name} has accepted the ride request (${rId}) with fare ${fareFormatted}. Tap to view ride details.`,
          customerName: name,
          customerPhone: ride.passengerPhone || "",
          pickup: ride.pickupLocation || "Pickup Point",
          destination: ride.dropoffLocation || "Destination Point",
          fareFormatted: fareFormatted,
          status: "CUSTOMER_ACCEPTED",
          type: "CUSTOMER_ACCEPTED",
          isRead: false,
          isDismissed: false,
          payload: {
            id: rId,
            rideId: rId,
            requestId: rId,
            mongoId: ride._id ? ride._id.toString() : rId,
            customerName: name,
            passengerName: name,
            passengerPhone: ride.passengerPhone,
            pickupLocation: ride.pickupLocation,
            dropoffLocation: ride.dropoffLocation,
            fare: ride.fare,
            fareFormatted: fareFormatted,
            status: "CUSTOMER_ACCEPTED"
          }
        };

        await DriverNotification.findOneAndUpdate(
          { notificationId: `${rId}_FARE_ACCEPTED` },
          driverNotifData,
          { upsert: true, new: true }
        ).catch(() => {});

        if (io) {
          if (targetDriverId) {
            io.to(`driver_${targetDriverId}`).emit("customer-accepted-ride", driverNotifData);
            io.to(String(targetDriverId)).emit("customer-accepted-ride", driverNotifData);
            io.to(`driver_${targetDriverId}`).emit("driver-notification", driverNotifData);
          }
          if (targetDriverName) {
            io.to(targetDriverName).emit("customer-accepted-ride", driverNotifData);
            io.to(`driver_${targetDriverName}`).emit("customer-accepted-ride", driverNotifData);
          }
          io.emit("customer-accepted-ride", driverNotifData);
          io.emit("driver-notification", driverNotifData);
          console.log(`📡 Real-time event [customer-accepted-ride] emitted for driver for ride ${rId}`);
        }
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

// 11. Helper to build default route seed data
function getDefaultRoutesSeed(realDbRides = []) {
  const defaultNamesA = [
    { name: "Sarah Khan", phone: "+92 300 1122331", pickup: "I-8/4, Street 12, Islamabad", dropoff: "Blue Area, Saudi Pak Tower", time: "7:15 AM" },
    { name: "Muhammad Ali", phone: "+92 321 2233442", pickup: "I-8/2, Main Road, Islamabad", dropoff: "F-6 Markaz, Super Market", time: "7:25 AM" },
    { name: "Ahmed Raza", phone: "+92 333 3344553", pickup: "H-8/1, Near HEC, Islamabad", dropoff: "G-7/2, Street 8, Islamabad", time: "7:40 AM" },
    { name: "Fatima Noor", phone: "+92 345 4455664", pickup: "I-9/1, Street 3, Islamabad", dropoff: "Blue Area, ISE Towers", time: "7:55 AM" },
    { name: "Zainab Bibi", phone: "+92 301 5566775", pickup: "I-8/3, Street 25, Islamabad", dropoff: "F-7 Markaz, Jinnah Super", time: "8:10 AM" },
    { name: "Hamza Tariq", phone: "+92 312 6677886", pickup: "G-8/4, Street 18, Islamabad", dropoff: "Zero Point Interchange", time: "8:25 AM" },
    { name: "Ayesha Malik", phone: "+92 305 7788997", pickup: "I-8/1, Service Road, Islamabad", dropoff: "Blue Area, Stock Exchange", time: "8:35 AM" },
    { name: "Bilal Ahmed", phone: "+92 322 8899008", pickup: "H-9/2, Near Metro, Islamabad", dropoff: "Pak Secretariat, Gate 3", time: "8:50 AM" },
  ];

  const defaultNamesB = [
    { name: "Omar Farooq", phone: "+92 300 2345671", pickup: "F-10 Markaz, Islamabad", dropoff: "Blue Area, Beverly Centre", time: "1:10 PM" },
    { name: "Sana Javed", phone: "+92 321 3456782", pickup: "F-11/2, Street 14, Islamabad", dropoff: "G-8 Markaz, Islamabad", time: "1:20 PM" },
    { name: "Hassan Shah", phone: "+92 333 4567893", pickup: "G-10/4, Street 22, Islamabad", dropoff: "Blue Area, Ufone Tower", time: "1:30 PM" },
    { name: "Maryam Nawaz", phone: "+92 345 5678904", pickup: "F-8/3, Park Road, Islamabad", dropoff: "F-6/1, School Road", time: "1:40 PM" },
    { name: "Usman Ghani", phone: "+92 302 6789015", pickup: "G-11/3, Main Double Road", dropoff: "Blue Area, Kulsum Plaza", time: "1:50 PM" },
    { name: "Khadija Bibi", phone: "+92 313 7890126", pickup: "E-11/2, MPCHS, Islamabad", dropoff: "F-7/2, Street 11, Islamabad", time: "2:00 PM" },
    { name: "Zubair Khan", phone: "+92 306 8901237", pickup: "F-10/1, Street 30, Islamabad", dropoff: "Zero Point, Islamabad", time: "2:10 PM" },
    { name: "Anum Tariq", phone: "+92 324 9012348", pickup: "G-9/1, Street 4, Islamabad", dropoff: "Blue Area, Green Trust Tower", time: "2:20 PM" },
    { name: "Kamran Akmal", phone: "+92 334 0123459", pickup: "G-10/2, Near Court, Islamabad", dropoff: "Pak Secretariat, Block A", time: "2:30 PM" },
    { name: "Hina Altaf", phone: "+92 303 1234560", pickup: "F-11/4, Street 9, Islamabad", dropoff: "Centaurus Mall, Jinnah Ave", time: "2:35 PM" },
    { name: "Waqas Younis", phone: "+92 323 2345671", pickup: "F-10/3, Street 15, Islamabad", dropoff: "Blue Area, Islamabad", time: "2:40 PM" },
    { name: "Mahnoor Baloch", phone: "+92 335 3456782", pickup: "G-11/1, Street 3, Islamabad", dropoff: "F-8 Markaz, Ayub Market", time: "2:45 PM" },
    { name: "Danish Taimoor", phone: "+92 346 4567893", pickup: "F-8/2, Street 7, Islamabad", dropoff: "Blue Area, Islamabad", time: "2:50 PM" },
    { name: "Sadia Imam", phone: "+92 307 5678904", pickup: "G-9/3, Street 19, Islamabad", dropoff: "F-6 Markaz, Islamabad", time: "2:55 PM" },
    { name: "Babar Azam", phone: "+92 314 6789015", pickup: "F-10/4, Street 40, Islamabad", dropoff: "Blue Area, Islamabad", time: "3:00 PM" },
  ];

  const defaultNamesC = [
    { name: "Noman Ali", phone: "+92 300 9988771", pickup: "Saddar, Cantt, Rawalpindi", dropoff: "Blue Area, Islamabad", time: "6:15 PM" },
    { name: "Farah Naz", phone: "+92 321 8877662", pickup: "Commercial Market, Rawalpindi", dropoff: "F-7 Markaz, Islamabad", time: "6:30 PM" },
    { name: "Tariq Jameel", phone: "+92 333 7766553", pickup: "Chandni Chowk, Murree Road", dropoff: "Zero Point, Islamabad", time: "6:50 PM" },
    { name: "Mehwish Hayat", phone: "+92 345 6655444", pickup: "Westridge 1, Rawalpindi", dropoff: "F-6/2, Islamabad", time: "7:15 PM" },
    { name: "Asim Azhar", phone: "+92 301 5544335", pickup: "Faizabad Interchange", dropoff: "Blue Area, Islamabad", time: "7:45 PM" },
  ];

  function mapCustomers(defaults, prefix) {
    return defaults.map((item, idx) => {
      // If a real DB ride is available, link its real id
      const dbRide = realDbRides[idx % (realDbRides.length || 1)];
      const reqId = dbRide ? (dbRide.requestId || dbRide._id?.toString()) : `${prefix}-${8030 + idx + 1}`;
      return {
        requestId: reqId,
        customerId: dbRide?.customerId || `CUST-${prefix}-${idx + 1}`,
        customerName: dbRide?.passengerName || item.name,
        phone: dbRide?.passengerPhone || item.phone,
        email: dbRide?.passengerEmail || `${item.name.toLowerCase().replace(/\s+/g, '')}@gmail.com`,
        pickupLocation: dbRide?.pickupLocation || item.pickup,
        dropoffLocation: dbRide?.dropoffLocation || item.dropoff,
        time: dbRide?.timeToReach || item.time,
        fare: dbRide?.fare || 9500,
        fareFormatted: dbRide?.fare ? `Rs. ${Number(dbRide.fare).toLocaleString()}` : "Rs. 9,500",
        vehicleType: dbRide?.vehicleType || "Sedan",
        status: "Pending Acceptance"
      };
    });
  }

  return [
    {
      routeId: "ROUTE-A",
      routeName: "Route A",
      pickupPoint: "Pickup Point",
      dropoffPoint: "Drop Point",
      timeRange: "7:00 AM - 9:00 AM",
      customerCount: 8,
      customers: mapCustomers(defaultNamesA, "A"),
      isPreferred: false,
      status: "Pending"
    },
    {
      routeId: "ROUTE-B",
      routeName: "Route B",
      pickupPoint: "Pickup Point",
      dropoffPoint: "Drop Point",
      timeRange: "1:00 PM - 3:00 PM",
      customerCount: 15,
      customers: mapCustomers(defaultNamesB, "B"),
      isPreferred: true, // Default preferred in design
      status: "Pending"
    },
    {
      routeId: "ROUTE-C",
      routeName: "Route C",
      pickupPoint: "Pickup Point",
      dropoffPoint: "Drop Point",
      timeRange: "6:00 PM - 8:00 PM",
      customerCount: 5,
      customers: mapCustomers(defaultNamesC, "C"),
      isPreferred: false,
      status: "Pending"
    }
  ];
}

// 12. GET SUGGESTED ROUTES (For Driver App & Admin)
exports.getSuggestedRoutes = async (req, res) => {
  try {
    let routes = await SuggestedRoute.find().lean();

    if (!routes || routes.length === 0) {
      // Fetch any pending rides from MongoDB to enrich the initial seed
      const pendingRides = await RideRequest.find({ status: { $ne: "CANCELLED" } }).limit(20).lean().catch(() => []);
      const seedData = getDefaultRoutesSeed(pendingRides);
      routes = await SuggestedRoute.insertMany(seedData);
    }

    return res.status(200).json({
      success: true,
      count: routes.length,
      routes
    });
  } catch (err) {
    console.error("Get Suggested Routes Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch suggested routes",
      error: err.message
    });
  }
};

// 13. CREATE / SEND NEW ROUTE (Admin Action)
exports.createSuggestedRoute = async (req, res) => {
  try {
    const { routeName, pickupPoint, dropoffPoint, timeRange, customers, driverId } = req.body;

    if (!routeName) {
      return res.status(400).json({ success: false, message: "Route name is required" });
    }

    const routeId = `ROUTE-${Date.now()}`;
    const newRoute = new SuggestedRoute({
      routeId,
      routeName: routeName.trim(),
      pickupPoint: pickupPoint || "Pickup Point",
      dropoffPoint: dropoffPoint || "Drop Point",
      timeRange: timeRange || "8:00 AM - 10:00 AM",
      customerCount: Array.isArray(customers) ? customers.length : 0,
      customers: Array.isArray(customers) ? customers : [],
      driverId: driverId || null,
      isPreferred: false,
      status: "Pending"
    });

    const savedRoute = await newRoute.save();

    // Create persistent DriverNotification
    try {
      const driverNotif = new DriverNotification({
        driverId: driverId || null,
        title: `📍 New Route Available: ${savedRoute.routeName}`,
        subtitle: `Admin has assigned ${savedRoute.routeName} with ${savedRoute.customerCount} passenger requests (${savedRoute.timeRange}).`,
        routeId: savedRoute.routeId,
        routeName: savedRoute.routeName,
        customerCount: savedRoute.customerCount,
        type: "NEW_ROUTE_ASSIGNED",
        pickup: savedRoute.pickupPoint,
        destination: savedRoute.dropoffPoint,
        timeRange: savedRoute.timeRange,
        isRead: false
      });
      await driverNotif.save();

      const io = req.app.get("io");
      if (io) {
        io.emit("driver-notification", driverNotif);
        if (driverId) {
          io.to(`driver_${driverId}`).emit("driver-notification", driverNotif);
        }
      }
    } catch (notifErr) {
      console.warn("Driver notification creation error:", notifErr.message);
    }

    // Emit real-time socket event so drivers receive this route immediately
    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("new-suggested-route", savedRoute);
        io.emit("suggested-routes-updated", savedRoute);
      }
    } catch (_) {}

    return res.status(201).json({
      success: true,
      message: "Route created and sent to driver successfully",
      route: savedRoute
    });
  } catch (err) {
    console.error("Create Suggested Route Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to create suggested route",
      error: err.message
    });
  }
};

// 14. ACCEPT ROUTE & SEND NOTIFICATIONS TO ALL REQUESTED CUSTOMERS (Driver Action)
exports.acceptSuggestedRoute = async (req, res) => {
  try {
    const { routeId, driverId, driverName } = req.body;

    if (!routeId) {
      return res.status(400).json({
        success: false,
        message: "Route ID or routeName is required to accept route"
      });
    }

    // 1. Locate Route
    let route = await SuggestedRoute.findOne({
      $or: [
        { routeId: routeId },
        { _id: mongoose.Types.ObjectId.isValid(routeId) ? routeId : null },
        { routeName: new RegExp(`^${routeId}$`, "i") }
      ]
    });

    // If route doesn't exist yet, seed and locate it
    if (!route) {
      const pendingRides = await RideRequest.find({ status: { $ne: "CANCELLED" } }).limit(20).lean().catch(() => []);
      const seedData = getDefaultRoutesSeed(pendingRides);
      await SuggestedRoute.insertMany(seedData);
      route = await SuggestedRoute.findOne({
        $or: [
          { routeId: routeId },
          { routeName: new RegExp(`^${routeId}$`, "i") }
        ]
      });
    }

    if (!route) {
      return res.status(404).json({
        success: false,
        message: `Suggested Route '${routeId}' not found`
      });
    }

    // 2. Resolve Driver Information
    let resolvedName = driverName || "Arbab";
    let resolvedPhone = "+92 300 9876543";
    let resolvedCode = "DRV-1001";
    let resolvedVehicle = "Honda Accord (White)";
    let resolvedPlate = "ISB-0009";
    let resolvedRating = "⭐ 4.9 (Verified Driver)";

    if (driverId) {
      try {
        let driverDoc = null;
        if (mongoose.Types.ObjectId.isValid(driverId)) {
          driverDoc = await Driver.findById(driverId).catch(() => null);
        }
        if (!driverDoc) {
          driverDoc = await Driver.findOne({ driverReferenceId: driverId }).catch(() => null);
        }

        if (driverDoc) {
          resolvedName = driverDoc.Name || resolvedName;
          resolvedPhone = driverDoc.PhoneNumber || resolvedPhone;
          resolvedCode = driverDoc.driverReferenceId || resolvedCode;

          const vehDoc = await Vehicle.findOne({ driver: driverDoc._id }).catch(() => null);
          if (vehDoc) {
            resolvedVehicle = `${vehDoc.vehicleMake || ''} ${vehDoc.vehicleModel || ''} (${vehDoc.vehicleColor || 'White'})`.trim();
            resolvedPlate = vehDoc.registrationNumber || resolvedPlate;
          }
        }
      } catch (_) {}
    }

    // 3. Mark Route as Accepted
    route.status = "ACCEPTED";
    route.acceptedByDriver = resolvedName;
    route.acceptedAt = new Date();
    if (driverId) route.driverId = driverId;

    // 4. Update Each Customer Request & Create Notification
    const io = req.app.get("io");
    const notifiedCustomers = [];

    for (let i = 0; i < route.customers.length; i++) {
      const cust = route.customers[i];
      cust.status = "ACCEPTED";

      const reqId = cust.requestId || `REQ-${Date.now()}-${i}`;
      const fareFormatted = cust.fareFormatted || (cust.fare ? `Rs. ${Number(cust.fare).toLocaleString()}` : "Rs. 9,500");

      // Update matching RideRequest if exists in MongoDB
      try {
        await RideRequest.findOneAndUpdate(
          {
            $or: [
              { requestId: reqId },
              { passengerPhone: cust.phone },
              { _id: mongoose.Types.ObjectId.isValid(reqId) ? reqId : null }
            ]
          },
          {
            status: "ACCEPTED",
            assignedDriverId: driverId || null,
            assignedDriverName: resolvedName,
            assignedDriverDetails: {
              driverId: driverId || "",
              driverCode: resolvedCode,
              name: resolvedName,
              phone: resolvedPhone,
              rating: resolvedRating,
              vehicle: resolvedVehicle,
              registrationNumber: resolvedPlate
            }
          }
        );
      } catch (_) {}

      // Create persistent Notification in CustomerNotification collection
      try {
        await CustomerNotification.create({
          customerId: cust.customerId || cust.phone,
          passengerPhone: cust.phone,
          passengerEmail: cust.email || "",
          rideId: reqId,
          title: "🔔 Ride Accepted by Driver!",
          subtitle: `Driver ${resolvedName} has accepted your ride request for ${route.routeName}!`,
          status: "ACCEPTED",
          fareFormatted: fareFormatted,
          pickup: cust.pickupLocation || route.pickupPoint,
          destination: cust.dropoffLocation || route.dropoffPoint,
          driverName: resolvedName,
          driverPhone: resolvedPhone,
          driverCode: resolvedCode,
          rating: resolvedRating,
          vehicle: resolvedVehicle,
          numberPlate: resolvedPlate,
          isRead: false
        });
      } catch (notifErr) {
        console.warn("Failed saving customer notification:", notifErr.message);
      }

      // Prepare Socket.IO payload
      const notifyPayload = {
        id: reqId,
        requestId: reqId,
        rideId: reqId,
        customerId: cust.customerId,
        customerName: cust.customerName,
        passengerName: cust.customerName,
        passengerPhone: cust.phone,
        passengerEmail: cust.email,
        title: "🔔 Ride Accepted by Driver!",
        subtitle: `Driver ${resolvedName} accepted your ride request for ${route.routeName}.`,
        fareFormatted: fareFormatted,
        fare: cust.fare,
        status: "ACCEPTED",
        pickup: cust.pickupLocation || route.pickupPoint,
        destination: cust.dropoffLocation || route.dropoffPoint,
        driverName: resolvedName,
        driverPhone: resolvedPhone,
        driverCode: resolvedCode,
        rating: resolvedRating,
        vehicle: resolvedVehicle,
        numberPlate: resolvedPlate,
        driverDetails: {
          name: resolvedName,
          phone: resolvedPhone,
          driverCode: resolvedCode,
          rating: resolvedRating,
          vehicle: resolvedVehicle,
          registrationNumber: resolvedPlate
        },
        time: cust.time || route.timeRange,
        createdAt: new Date().toISOString()
      };

      // Emit to this customer's rooms
      if (io) {
        try {
          if (cust.customerId) {
            io.to(`customer_${cust.customerId}`).emit("ride-accepted", notifyPayload);
            io.to(String(cust.customerId)).emit("ride-accepted", notifyPayload);
          }
          if (cust.phone) {
            io.to(`customer_${cust.phone}`).emit("ride-accepted", notifyPayload);
            io.to(String(cust.phone)).emit("ride-accepted", notifyPayload);
          }
          if (reqId) {
            io.to(`ride_${reqId}`).emit("ride-accepted", notifyPayload);
          }
          io.emit("ride-accepted", notifyPayload);
          io.emit("ride_accepted", notifyPayload);
        } catch (_) {}
      }

      notifiedCustomers.push({
        name: cust.customerName,
        phone: cust.phone,
        requestId: reqId
      });
    }

    await route.save();

    // Create persistent DriverNotification for this driver
    try {
      const driverNotif = new DriverNotification({
        driverId: driverId || resolvedCode || null,
        driverReferenceId: resolvedCode,
        title: `✅ Route Accepted: ${route.routeName}`,
        subtitle: `You accepted ${route.routeName}. Notifications dispatched to all ${route.customers.length} passengers.`,
        routeId: route.routeId,
        routeName: route.routeName,
        customerCount: route.customers.length,
        type: "ROUTE_ACCEPTED",
        pickup: route.pickupPoint,
        destination: route.dropoffPoint,
        timeRange: route.timeRange,
        isRead: false
      });
      await driverNotif.save();

      if (io) {
        io.emit("driver-notification", driverNotif);
        if (driverId) {
          io.to(`driver_${driverId}`).emit("driver-notification", driverNotif);
        }
      }
    } catch (driverNotifErr) {
      console.warn("Driver accept notification error:", driverNotifErr.message);
    }

    // Global Socket.IO event notifying Admin & all connected clients
    if (io) {
      io.emit("route-accepted", {
        routeId: route.routeId,
        routeName: route.routeName,
        driverName: resolvedName,
        customerCount: route.customers.length,
        acceptedAt: route.acceptedAt
      });
      io.emit("ride-update", {
        type: "ROUTE_ACCEPTED",
        routeId: route.routeId,
        driverName: resolvedName
      });
      console.log(`🚀 Route ${route.routeName} accepted by ${resolvedName}. Real-time notifications dispatched to all ${route.customers.length} customers.`);
    }

    return res.status(200).json({
      success: true,
      message: `Route '${route.routeName}' successfully accepted! Notifications have been sent to all ${route.customers.length} customers.`,
      route,
      notifiedCount: route.customers.length,
      notifiedCustomers
    });
  } catch (err) {
    console.error("Accept Suggested Route Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to accept route",
      error: err.message
    });
  }
};

// 15. SET PREFERRED ROUTE (Star Toggle)
exports.setPreferredRoute = async (req, res) => {
  try {
    const routeId = req.params.id;
    const { isPreferred } = req.body;

    const route = await SuggestedRoute.findOneAndUpdate(
      { $or: [{ routeId: routeId }, { _id: mongoose.Types.ObjectId.isValid(routeId) ? routeId : null }] },
      { isPreferred: isPreferred !== undefined ? isPreferred : true },
      { new: true }
    );

    if (!route) {
      return res.status(404).json({ success: false, message: "Route not found" });
    }

    return res.status(200).json({
      success: true,
      message: "Preferred route updated",
      route
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: "Failed to update preferred route",
      error: err.message
    });
  }
};

// 16. GET DRIVER NOTIFICATIONS
exports.getDriverNotifications = async (req, res) => {
  try {
    const { driverId, driverName } = req.query;

    let queryConds = [{ driverId: null }];
    let driverMatchRides = [];

    if (driverId) {
      queryConds.push({ driverId: driverId });
      queryConds.push({ driverReferenceId: driverId });
      driverMatchRides.push({ assignedDriverId: driverId });
      driverMatchRides.push({ assignedDriverId: new RegExp(`^${driverId}$`, "i") });
      driverMatchRides.push({ "assignedDriverDetails.driverId": driverId });
      if (mongoose.Types.ObjectId.isValid(driverId)) {
        queryConds.push({ driverId: new mongoose.Types.ObjectId(driverId) });
        driverMatchRides.push({ assignedDriverId: new mongoose.Types.ObjectId(driverId) });
      }
    }

    if (driverName) {
      queryConds.push({ driverName: new RegExp(`^${driverName.trim()}$`, "i") });
      driverMatchRides.push({ assignedDriverName: new RegExp(`^${driverName.trim()}$`, "i") });
      driverMatchRides.push({ "assignedDriverDetails.name": new RegExp(`^${driverName.trim()}$`, "i") });
    }

    // 1. Fetch persistent notifications from DriverNotification collection
    let storedNotifications = await DriverNotification.find({
      $or: queryConds,
      isDismissed: { $ne: true }
    })
      .sort({ createdAt: -1 })
      .lean()
      .catch(() => []);

    // Also get dismissed keys
    const dismissedNotifs = await DriverNotification.find({
      $or: queryConds,
      isDismissed: true
    }).lean().catch(() => []);
    const dismissedKeys = new Set(dismissedNotifs.map(d => d.notificationId || `${d.rideId}_${d.status}`));
    const dismissedRideIds = new Set(dismissedNotifs.map(d => d.rideId).filter(Boolean));

    // 2. Fetch active rides for driver from RideRequest and ScheduleRide where customer accepted or ride was assigned
    let dynamicNotifs = [];
    if (driverMatchRides.length > 0) {
      const assignedRides = await RideRequest.find({ $or: driverMatchRides })
        .sort({ updatedAt: -1 })
        .lean()
        .catch(() => []);

      let scheduleRides = [];
      try {
        const ScheduleRide = require("../schema/ScheduleRide");
        scheduleRides = await ScheduleRide.find({ $or: driverMatchRides })
          .sort({ updatedAt: -1 })
          .lean()
          .catch(() => []);
      } catch (_) {}

      const allDriverRides = [...assignedRides, ...scheduleRides];

      for (const r of allDriverRides) {
        const rId = r.requestId || r._id.toString();
        const fareText = r.fare ? `Rs. ${Number(r.fare).toLocaleString()}` : "Rs. 9,500";
        const custName = r.passengerName || "Customer";
        const st = (r.status || "").toLowerCase();

        // Customer Accepted Ride
        if (
          r.customerAccepted === true ||
          st.includes("customer accepted") ||
          st.includes("fare accepted") ||
          st === "accepted" ||
          st === "confirmed"
        ) {
          const notifKey = `${rId}_CUSTOMER_ACCEPTED`;
          if (!dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId)) {
            dynamicNotifs.push({
              id: `${rId}_customer_accepted`,
              notificationId: notifKey,
              title: "🎉 Customer Accepted Ride!",
              subtitle: `Customer ${custName} has accepted your ride request (${rId}). Tap to view ride details.`,
              rideId: rId,
              requestId: rId,
              mongoId: r._id ? r._id.toString() : rId,
              customerName: custName,
              customerPhone: r.passengerPhone || "",
              pickup: r.pickupLocation || "Pickup Point",
              destination: r.dropoffLocation || "Destination Point",
              fareFormatted: fareText,
              status: "CUSTOMER_ACCEPTED",
              type: "CUSTOMER_ACCEPTED",
              isRead: false,
              isDismissed: false,
              createdAt: r.customerAcceptedAt || r.updatedAt || r.createdAt || new Date().toISOString()
            });
          }
        }
      }
    }

    // Merge stored and dynamic notifications, deduplicating by notificationId/rideId+type
    const merged = [];
    const seenMap = new Set();

    for (const n of [...storedNotifications, ...dynamicNotifs]) {
      const key = n.notificationId || (n.rideId ? `${n.rideId}_${n.type || n.status}` : String(n._id || n.id));
      if (!seenMap.has(key) && !dismissedKeys.has(key)) {
        seenMap.add(key);
        merged.push({
          ...n,
          id: n.notificationId || n._id || n.id,
          notificationId: key
        });
      }
    }

    let notifications = merged;

    if (!notifications || notifications.length === 0) {
      const seedNotifs = [
        {
          driverId: driverId || null,
          title: "📍 New Route Match Ready!",
          subtitle: "Admin has published Route B with 15 customer ride requests (1:00 PM - 3:00 PM).",
          routeId: "ROUTE-B",
          routeName: "Route B",
          customerCount: 15,
          type: "NEW_ROUTE_ASSIGNED",
          pickup: "Pickup Point (F-10 / F-11 / G-10)",
          destination: "Drop Point (Blue Area / Islamabad)",
          timeRange: "1:00 PM - 3:00 PM",
          fareFormatted: "Rs. 9,500/seat",
          isRead: false,
          createdAt: new Date().toISOString()
        },
        {
          driverId: driverId || null,
          title: "⭐ Route Setup Recommendation",
          subtitle: "Morning routes (Route A) are experiencing high passenger traffic. Tap to view requests.",
          routeId: "ROUTE-A",
          routeName: "Route A",
          customerCount: 8,
          type: "NEW_ROUTE_ASSIGNED",
          pickup: "Pickup Point (I-8 / H-8)",
          destination: "Drop Point (Blue Area / F-6)",
          timeRange: "7:00 AM - 9:00 AM",
          fareFormatted: "Rs. 9,500/seat",
          isRead: false,
          createdAt: new Date(Date.now() - 3600000).toISOString()
        }
      ];

      try {
        notifications = await DriverNotification.insertMany(seedNotifs);
      } catch (_) {
        notifications = seedNotifs;
      }
    }

    return res.status(200).json({
      success: true,
      count: notifications.length,
      notifications
    });
  } catch (err) {
    console.error("Get Driver Notifications Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch driver notifications",
      error: err.message
    });
  }
};

// 17. MARK DRIVER NOTIFICATION AS READ
exports.markDriverNotificationRead = async (req, res) => {
  try {
    const { id } = req.params;
    await DriverNotification.findByIdAndUpdate(id, { isRead: true }).catch(() => {});
    return res.status(200).json({ success: true, message: "Notification marked as read" });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};



// 18. DISMISS CUSTOMER NOTIFICATION
exports.dismissCustomerNotification = async (req, res) => {
  try {
    const { id } = req.params;
    const { customerId, phone } = req.body || {};

    if (id) {
      if (id.match(/^[0-9a-fA-F]{24}$/)) {
        await CustomerNotification.findByIdAndUpdate(id, { isDismissed: true, isRead: true }).catch(() => {});
      }
      await CustomerNotification.updateMany(
        { $or: [{ notificationId: id }, { rideId: id }] },
        { isDismissed: true, isRead: true }
      ).catch(() => {});

      // Also record dismissed state for dynamically generated IDs (e.g. REQ-8033_accepted)
      const cleanRideId = id.replace(/_accepted|_price_updated|_driver_unavailable|_completed/i, "");
      await CustomerNotification.findOneAndUpdate(
        { notificationId: id },
        {
          notificationId: id,
          rideId: cleanRideId,
          status: "DISMISSED",
          title: "Dismissed Notification",
          subtitle: "",
          isDismissed: true,
          isRead: true,
          ...(customerId ? { customerId } : {}),
          ...(phone ? { passengerPhone: phone } : {})
        },
        { upsert: true }
      ).catch(() => {});
    }

    return res.status(200).json({ success: true, message: "Notification dismissed" });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

// 19. CLEAR ALL CUSTOMER NOTIFICATIONS
exports.clearAllCustomerNotifications = async (req, res) => {
  try {
    const { customerId, phone, email } = req.body || {};
    let queryConds = [];
    if (customerId) queryConds.push({ customerId });
    if (phone) queryConds.push({ passengerPhone: phone });
    if (email) queryConds.push({ passengerEmail: email });

    const query = queryConds.length > 0 ? { $or: queryConds } : {};
    await CustomerNotification.updateMany(query, { isDismissed: true, isRead: true }).catch(() => {});

    return res.status(200).json({ success: true, message: "All customer notifications cleared" });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

// 20. DISMISS DRIVER NOTIFICATION
exports.dismissDriverNotification = async (req, res) => {
  try {
    const { id } = req.params;
    const { driverId } = req.body || {};

    if (id) {
      if (id.match(/^[0-9a-fA-F]{24}$/)) {
        await DriverNotification.findByIdAndUpdate(id, { isDismissed: true, isRead: true }).catch(() => {});
      }
      await DriverNotification.updateMany(
        { $or: [{ notificationId: id }, { rideId: id }] },
        { isDismissed: true, isRead: true }
      ).catch(() => {});

      const cleanRideId = id.replace(/_customer_accepted|_accepted|_fare_accepted|_price_updated/i, "");
      await DriverNotification.findOneAndUpdate(
        { notificationId: id },
        {
          notificationId: id,
          rideId: cleanRideId,
          status: "DISMISSED",
          title: "Dismissed Notification",
          subtitle: "",
          isDismissed: true,
          isRead: true,
          ...(driverId ? { driverId } : {})
        },
        { upsert: true }
      ).catch(() => {});
    }

    return res.status(200).json({ success: true, message: "Driver notification dismissed" });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

// 21. CLEAR ALL DRIVER NOTIFICATIONS
exports.clearAllDriverNotifications = async (req, res) => {
  try {
    const { driverId } = req.body || {};
    let queryConds = [{ driverId: null }];
    if (driverId) {
      queryConds.push({ driverId });
      queryConds.push({ driverReferenceId: driverId });
    }
    const query = { $or: queryConds };
    await DriverNotification.updateMany(query, { isDismissed: true, isRead: true }).catch(() => {});

    return res.status(200).json({ success: true, message: "All driver notifications cleared" });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

// 22. ACCEPT RIDE BY CUSTOMER (Real-time Notification Dispatched to Driver)
exports.acceptRideByCustomer = async (req, res) => {
  try {
    const rideId = req.params.id || req.body.rideId;
    const { customerId, customerName, customerPhone } = req.body || {};

    if (!rideId) {
      return res.status(400).json({
        success: false,
        message: "Ride ID is required."
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
      try {
        const ScheduleRide = require("../schema/ScheduleRide");
        ride = await ScheduleRide.findOne({
          $or: [
            { requestId: rideId },
            ...(mongoose.Types.ObjectId.isValid(rideId) ? [{ _id: rideId }] : [])
          ]
        }).catch(() => null);
      } catch (_) {}
    }

    if (!ride) {
      return res.status(404).json({
        success: false,
        message: `Ride ${rideId} not found.`
      });
    }

    const resolvedCustName = customerName || ride.passengerName || "Customer";
    const resolvedCustPhone = customerPhone || ride.passengerPhone || "";
    const resolvedRideId = ride.requestId || ride._id.toString();
    const fareFormatted = ride.fare ? `Rs. ${Number(ride.fare).toLocaleString()}` : "Rs. 9,500";

    ride.customerAccepted = true;
    ride.customerAcceptedAt = new Date();
    ride.status = "Customer Accepted";
    await ride.save();

    // Prepare driver target
    const dDetails = ride.assignedDriverDetails || {};
    const targetDriverId = ride.assignedDriverId || dDetails.driverId || null;
    const targetDriverRef = dDetails.driverCode || ride.assignedDriverId || "";
    const targetDriverName = ride.assignedDriverName || dDetails.name || "Driver";

    // 1. Create persistent DriverNotification
    const notifId = `${resolvedRideId}_CUSTOMER_ACCEPTED`;
    const driverNotifData = {
      driverId: targetDriverId,
      driverReferenceId: targetDriverRef,
      driverName: targetDriverName,
      rideId: resolvedRideId,
      notificationId: notifId,
      title: "🎉 Customer Accepted Ride!",
      subtitle: `Customer ${resolvedCustName} has accepted your ride request (${resolvedRideId}). Tap to view ride details.`,
      customerName: resolvedCustName,
      customerPhone: resolvedCustPhone,
      pickup: ride.pickupLocation || "Pickup Point",
      destination: ride.dropoffLocation || "Destination Point",
      fareFormatted: fareFormatted,
      status: "CUSTOMER_ACCEPTED",
      type: "CUSTOMER_ACCEPTED",
      isRead: false,
      isDismissed: false,
      payload: {
        id: resolvedRideId,
        rideId: resolvedRideId,
        requestId: resolvedRideId,
        mongoId: ride._id ? ride._id.toString() : resolvedRideId,
        passengerName: resolvedCustName,
        customerName: resolvedCustName,
        passengerPhone: resolvedCustPhone,
        pickupLocation: ride.pickupLocation,
        dropoffLocation: ride.dropoffLocation,
        fare: ride.fare,
        fareFormatted: fareFormatted,
        status: "CUSTOMER_ACCEPTED",
        startingFrom: ride.startingFrom,
        timeToReach: ride.timeToReach
      }
    };

    let savedDriverNotif;
    try {
      savedDriverNotif = await DriverNotification.findOneAndUpdate(
        { notificationId: notifId },
        driverNotifData,
        { upsert: true, new: true }
      );
    } catch (dErr) {
      console.warn("DriverNotification save notice:", dErr.message);
      savedDriverNotif = driverNotifData;
    }

    // 2. Also update CustomerNotification so customer sees confirmed status
    try {
      await CustomerNotification.findOneAndUpdate(
        { notificationId: `${resolvedRideId}_ACCEPTED` },
        {
          subtitle: `You accepted this ride with Driver ${targetDriverName}.`,
          status: "CUSTOMER_ACCEPTED"
        }
      ).catch(() => {});
    } catch (_) {}

    // 3. Emit real-time Socket.IO events to Driver and System
    try {
      const io = req.app.get("io");
      if (io) {
        if (targetDriverId) {
          io.to(`driver_${targetDriverId}`).emit("customer-accepted-ride", driverNotifData);
          io.to(String(targetDriverId)).emit("customer-accepted-ride", driverNotifData);
          io.to(`driver_${targetDriverId}`).emit("driver-notification", driverNotifData);
        }
        if (targetDriverName) {
          io.to(targetDriverName).emit("customer-accepted-ride", driverNotifData);
          io.to(`driver_${targetDriverName}`).emit("customer-accepted-ride", driverNotifData);
        }
        io.emit("customer-accepted-ride", driverNotifData);
        io.emit("driver-notification", driverNotifData);
        io.emit("ride-updated", { type: "CUSTOMER_ACCEPTED", ride: driverNotifData.payload });
        io.emit("ride_accepted", driverNotifData);
        console.log(`📡 Real-time event [customer-accepted-ride] emitted for driver ${targetDriverName} (${resolvedRideId})`);
      }
    } catch (socketErr) {
      console.warn("Socket emit error:", socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: `Ride ${resolvedRideId} accepted successfully! Driver has been notified.`,
      ride,
      notification: savedDriverNotif
    });
  } catch (err) {
    console.error("Accept Ride By Customer Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to accept ride",
      error: err.message
    });
  }
};

