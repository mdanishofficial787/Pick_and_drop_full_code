const mongoose = require("mongoose");
const ScheduleRide = require("../schema/ScheduleRide");
const Driver = require("../schema/Driver");
const CustomerNotification = require("../schema/CustomerNotification");

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
        console.log("ðŸ“¡ Real-time event emitted: new-schedule-ride", saved.requestId);
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
    const { status, search, driverId, driverName } = req.query;
    let query = {};

    if (status) {
      const s = status.toLowerCase();
      query.status = s === "pending" ? "Pending Dispatch" : (s === "assigned" ? "ASSIGNED" : status);
    }

    if (driverId) {
      const driverConditions = [
        { assignedDriverId: driverId },
        { driverId: driverId }
      ];
      if (driverName && driverName.trim().length > 0) {
        driverConditions.push({ assignedDriverName: { $regex: driverName.trim(), $options: "i" } });
      }
      if (query.$or) {
        query.$and = [{ $or: query.$or }, { $or: driverConditions }];
        delete query.$or;
      } else {
        query.$or = driverConditions;
      }
    }

    if (search) {
      const searchConditions = [
        { requestId: { $regex: search, $options: "i" } },
        { passengerName: { $regex: search, $options: "i" } },
        { passengerPhone: { $regex: search, $options: "i" } },
        { pickupLocation: { $regex: search, $options: "i" } },
        { dropoffLocation: { $regex: search, $options: "i" } }
      ];
      if (query.$or) {
        query.$and = [{ $or: query.$or }, { $or: searchConditions }];
        delete query.$or;
      } else {
        query.$or = searchConditions;
      }
    }

    const rides = await ScheduleRide.find(query).sort({ createdAt: -1 }).lean();
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
      assignedDriver: r.assignedDriverName || r.assignedDriver || null,
      assignedDriverName: r.assignedDriverName || r.assignedDriver || null,
      assignedDriverId: r.assignedDriverId || r.driverId || r.driver || null,
      driverId: r.driverId || r.assignedDriverId || r.driver || null,
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

    const rides = await ScheduleRide.find(query).sort({ createdAt: -1 }).lean();
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

    // Persist CustomerNotification for assigned schedule ride
    try {
      await CustomerNotification.findOneAndUpdate(
        { notificationId: `${updated.requestId}_ACCEPTED` },
        {
          customerId: updated.customerId || updated.passengerPhone,
          passengerPhone: updated.passengerPhone,
          passengerEmail: updated.passengerEmail || "",
          rideId: updated.requestId,
          mongoId: updated._id ? updated._id.toString() : updated.requestId,
          notificationId: `${updated.requestId}_ACCEPTED`,
          title: "🚗 Driver Assigned!",
          subtitle: `Driver ${assignedName || "A driver"} has been assigned to your scheduled ride (${updated.requestId}).`,
          status: "ACCEPTED",
          fareFormatted: updated.fare ? `Rs. ${Number(updated.fare).toLocaleString()}` : "",
          pickup: updated.pickupLocation || "Pickup Point",
          destination: updated.dropoffLocation || "Destination Point",
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
      console.warn("Failed saving customer notification for dispatched schedule ride:", notifErr.message);
    }

    // Persist DriverNotification for Dispatched Schedule Ride
    try {
      const DriverNotification = require("../schema/DriverNotification");
      const driverNotif = {
        driverId: driverId || "",
        driverName: assignedName || "Assigned Driver",
        driverReferenceId: driverId || "",
        rideId: updated.requestId,
        requestId: updated.requestId,
        mongoId: updated._id ? updated._id.toString() : updated.requestId,
        notificationId: `${updated.requestId}_ASSIGNED`,
        title: "🚗 New Schedule Ride Dispatched!",
        subtitle: `Admin assigned schedule ride ${updated.requestId} (${updated.passengerName || "Customer"}) to you. Tap to view ride details.`,
        status: "ASSIGNED",
        type: "NEW_ASSIGNMENT",
        customerName: updated.passengerName || "Customer",
        customerPhone: updated.passengerPhone || "",
        pickup: updated.pickupLocation || "Pickup Point",
        destination: updated.dropoffLocation || "Destination Point",
        fareFormatted: updated.fare ? `Rs. ${Number(updated.fare).toLocaleString()}` : "Rs. 7,500",
        payload: updated,
        isRead: false,
        isDismissed: false
      };
      await DriverNotification.findOneAndUpdate(
        { notificationId: `${updated.requestId}_ASSIGNED` },
        driverNotif,
        { upsert: true, new: true }
      );

      const io = req.app.get("io");
      if (io) {
        const fullPayload = {
          ...driverNotif,
          ride: updated,
          data: updated,
          payload: updated
        };

        const targetRooms = [
          `driver-${driverId}`,
          `driver_${driverId}`,
          String(driverId)
        ];
        if (assignedName) {
          targetRooms.push(`driver-${assignedName}`);
          targetRooms.push(`driver_${assignedName}`);
          targetRooms.push(assignedName);
        }

        targetRooms.forEach(room => {
          io.to(room).emit("new-assignment", fullPayload);
          io.to(room).emit("ride-assigned", fullPayload);
          io.to(room).emit("ride-dispatched", fullPayload);
          io.to(room).emit("new-notification", fullPayload);
          io.to(room).emit("driver-notification", fullPayload);
        });

        io.emit("new-assignment", fullPayload);
        io.emit("ride-assigned", fullPayload);
        io.emit("ride-dispatched", fullPayload);
        io.emit("new-notification", fullPayload);
        io.emit("driver-notification", fullPayload);
        io.emit("schedule-ride-dispatched", updated);
        io.emit("schedule-ride-update", { type: "SCHEDULE_RIDE_DISPATCHED", ride: updated });
        io.emit("ride-updated", { type: "RIDE_DISPATCHED", ride: updated, notification: driverNotif });
        io.emit("ride_accepted", {
          requestId: updated.requestId,
          customerId: updated.customerId,
          passengerName: updated.passengerName,
          passengerPhone: updated.passengerPhone,
          status: "ACCEPTED",
          driverDetails: {
            name: assignedName || "Assigned Driver",
            driverCode: driverId || "DRV-ASSIGNED",
            vehicle: "Assigned Vehicle"
          }
        });
        console.log("📡 Real-time events emitted for schedule ride dispatch:", updated.requestId);
      }
    } catch (driverNotifErr) {
      console.warn("Failed saving driver notification for dispatched schedule ride:", driverNotifErr.message);
    }

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

    const isFareUpdated = (fare !== undefined && fare !== null && !isNaN(Number(fare)) && Number(fare) >= 0 && (Number(fare) !== Number(ride.fare) || status === "PRICE_UPDATED" || req.body.fareStatus === "PRICE_UPDATED"));
    if (isFareUpdated) {
      ride.fare = Number(fare);
      if (!status || status === "PRICE_UPDATED") {
        if (ride.status !== "COMPLETED" && ride.status !== "Completed" && ride.status !== "PAID") {
          ride.status = "PRICE_UPDATED";
        }
      }
      ride.fareResponseStatus = "Pending";
      ride.fareStatus = "PRICE_UPDATED";
    }
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
      rating: dDetails.rating ? `â­ ${dDetails.rating} (Verified Driver)` : "â­ 4.9 (Verified Driver)",
      vehicle: dDetails.vehicle ? `ðŸš— ${dDetails.vehicle}` : "ðŸš— Vehicle",
      numberPlate: dDetails.registrationNumber ? `ðŸ”¢ ${dDetails.registrationNumber}` : "ðŸ”¢ Registered"
    };

    const notifyPayload = {
      requestId: ride.requestId,
      customerId: ride.customerId,
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


    // Persist CustomerNotification for Schedule Ride Fare Update
    if (isFareUpdated && ride.status !== "COMPLETED" && ride.status !== "Completed") {
      try {
        const fareFormatted = `Rs. ${Number(ride.fare || 0).toLocaleString()}`;
        const notifId = `${ride.requestId}_price_updated`;

        await CustomerNotification.findOneAndUpdate(
          { notificationId: notifId },
          {
            customerId: ride.customerId || ride.passengerPhone,
            passengerPhone: ride.passengerPhone,
            passengerEmail: ride.passengerEmail || "",
            rideId: ride.requestId,
            mongoId: ride._id ? ride._id.toString() : ride.requestId,
            notificationId: notifId,
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has updated your scheduled ride fare to ${fareFormatted}. Tap to review and accept.`,
            status: "PRICE_UPDATED",
            fareResponseStatus: "Pending",
            fareFormatted: fareFormatted,
            pickup: ride.pickupLocation || "Pickup Point",
            destination: ride.dropoffLocation || "Destination Point",
            driverName: driverDetails ? driverDetails.name : "",
            driverPhone: driverDetails ? driverDetails.phone : "",
            driverCode: driverDetails ? driverDetails.driverCode : "",
            rating: driverDetails ? driverDetails.rating : "",
            vehicle: driverDetails ? driverDetails.vehicle : "",
            numberPlate: driverDetails ? driverDetails.numberPlate : "",
            isRead: false,
            isDismissed: false
          },
          { upsert: true, new: true }
        );
        console.log(`✅ CustomerNotification [PRICE_UPDATED] saved for schedule ride ${ride.requestId}: ${fareFormatted}`);
      } catch (fareNotifErr) {
        console.warn("Failed saving customer notification for updated schedule fare:", fareNotifErr.message);
      }
    }

    // Persist CustomerNotification for Driver Accepted or Assigned (ONLY Driver Details)
    if (ride.status === "ACCEPTED" || ride.status === "Accepted" || ride.status === "ASSIGNED") {
      try {
        await CustomerNotification.findOneAndUpdate(
          { notificationId: `${ride.requestId}_ACCEPTED` },
          {
            customerId: ride.customerId || ride.passengerPhone,
            passengerPhone: ride.passengerPhone,
            passengerEmail: ride.passengerEmail || "",
            rideId: ride.requestId,
            mongoId: ride._id ? ride._id.toString() : ride.requestId,
            notificationId: `${ride.requestId}_ACCEPTED`,
            title: "🚗 Driver Accepted Ride!",
            subtitle: `Driver ${driverDetails.name} has accepted your scheduled ride (${ride.requestId}). Tap to view driver details.`,
            status: "ACCEPTED",
            fareFormatted: notifyPayload.fareFormatted,
            pickup: ride.pickupLocation || "Pickup Point",
            destination: ride.dropoffLocation || "Destination Point",
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
        console.warn("Failed saving customer notification for accepted schedule ride:", notifErr.message);
      }
    }

    // When Driver COMPLETES Scheduled Ride: Send Payment Notification & Retire Accepted Notification
    if (ride.status === "COMPLETED" || ride.status === "Completed") {
      try {
        await CustomerNotification.updateMany(
          {
            $or: [
              { rideId: ride.requestId },
              { rideId: ride._id ? ride._id.toString() : "" }
            ],
            status: { $ne: "COMPLETED" }
          },
          { isDismissed: true, isRead: true }
        ).catch(() => {});

        await CustomerNotification.findOneAndUpdate(
          { notificationId: `${ride.requestId}_COMPLETED` },
          {
            customerId: ride.customerId || ride.passengerPhone,
            passengerPhone: ride.passengerPhone,
            passengerEmail: ride.passengerEmail || "",
            rideId: ride.requestId,
            mongoId: ride._id ? ride._id.toString() : ride.requestId,
            notificationId: `${ride.requestId}_COMPLETED`,
            title: "💳 Ride Completed - Pay Fare",
            subtitle: `Your ride ${ride.requestId} is complete. Please tap to submit payment of ${notifyPayload.fareFormatted}.`,
            status: "COMPLETED",
            fareFormatted: notifyPayload.fareFormatted,
            pickup: ride.pickupLocation || "Pickup Point",
            destination: ride.dropoffLocation || "Destination Point",
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
        console.warn("Failed saving customer notification for completed schedule ride:", notifErr.message);
      }
        // Store / ensure payment record in Payment History (collection: payments)
        try {
          const Payment = require("../schema/Payment");
          const fareStr = notifyPayload.fareFormatted || (ride.fare ? `Rs. ${Number(ride.fare).toLocaleString()}` : "Rs. 0");
          await Payment.findOneAndUpdate(
            { rideId: ride.requestId },
            {
              customerId: ride.customerId || null,
              customerName: ride.passengerName || "Customer",
              customerPhone: ride.passengerPhone || "",
              rideId: ride.requestId,
              fare: fareStr,
              pickup: ride.pickupLocation || "",
              destination: ride.dropoffLocation || "",
              driverName: driverDetails.name || "",
              status: ride.isPaid ? "PAID" : "PENDING PAYMENT"
            },
            { upsert: true, new: true }
          );
          console.log(`✅ Payment record stored in Payment History for schedule ride ${ride.requestId}: ${fareStr}`);
        } catch (paySaveErr) {
          console.warn("Notice saving payment record for completed schedule ride:", paySaveErr.message);
        }
    }

    try {
      const io = req.app.get("io");
      if (io) {
        if (ride.status === "ACCEPTED" || ride.status === "Accepted") {
          io.emit("ride_accepted", notifyPayload);
          io.emit("ride-accepted", notifyPayload);
          console.log(`📡 Real-time event [ride_accepted] emitted for ${ride.requestId} by driver ${driverDetails.name}`);
        }
        if (ride.status === "COMPLETED" || ride.status === "Completed") {
          io.emit("ride_completed", notifyPayload);
          io.emit("ride-completed", notifyPayload);
          console.log(`📡 Real-time event [ride_completed] emitted for ${ride.requestId}`);
        }
        if (isFareUpdated && ride.status !== "COMPLETED") {
          const farePayload = {
            ...notifyPayload,
            type: "PRICE_UPDATED",
            status: "PRICE_UPDATED",
            fareUpdated: true,
            fareResponseStatus: "Pending",
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has set your ride price to ${notifyPayload.fareFormatted}.`
          };
          const custId = ride.customerId ? String(ride.customerId) : "";
          const custPhone = ride.passengerPhone ? String(ride.passengerPhone) : "";
          const rId = String(ride.requestId);

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
          console.log(`📡 Real-time fare update emitted to customer for schedule ride ${rId}: ${notifyPayload.fareFormatted}`);
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
