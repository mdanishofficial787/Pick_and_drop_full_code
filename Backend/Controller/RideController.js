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

    const resolvedName = (passengerName || req.body.name || req.body.customerName || "Customer User").toString().trim();
    const resolvedPhone = (passengerPhone || req.body.phone || req.body.customerPhone || "+923001234567").toString().trim();
    const resolvedEmail = (passengerEmail || req.body.email || req.body.customerEmail || "").toString().trim().toLowerCase();
    const resolvedPickup = (pickupLocation || req.body.pickup || req.body.from || "").toString().trim();
    const resolvedDropoff = (dropoffLocation || req.body.dropoff || req.body.to || "").toString().trim();
    const resolvedStartingFrom = (startingFrom || req.body.startDate || req.body.date || req.body.travelDate || new Date().toISOString().split("T")[0]).toString().trim();

    if (!resolvedName || !resolvedPhone || !resolvedPickup || !resolvedDropoff || !resolvedStartingFrom) {
      return res.status(400).json({
        success: false,
        message: "Please provide all required ride details (Name, Phone, Pickup, Drop-off, Starting Date)"
      });
    }

    const newRide = new RideRequest({
      customerId: customerId || req.body.userId || null,
      passengerName: resolvedName,
      passengerPhone: resolvedPhone,
      passengerEmail: resolvedEmail || null,
      pickupLocation: resolvedPickup,
      dropoffLocation: resolvedDropoff,
      startingFrom: resolvedStartingFrom,
      timeToReach: timeToReach || "08:30 AM",
      timeToLeave: timeToLeave || "05:00 PM",
      scheduleType: scheduleType || req.body.schedulePreset || "Mon - Fri",
      scheduleTime: scheduleTime || timeToReach || "08:30 AM",
      customSchedule: customSchedule || {},
      vehicleTypeSelection: vehicleTypeSelection || req.body.serviceType || "Separate",
      seatingArrangement: seatingArrangement || "Sedan Executive",
      vehicleType: vehicleType || "Sedan",
      acPreference: acPreference || "AC",
      passengersCount: Number(passengersCount) || 1,
      fare: (fare !== undefined && !isNaN(Number(fare)) && Number(fare) > 0)
        ? Number(fare)
        : (customSchedule && !isNaN(Number(customSchedule.fare)) && Number(customSchedule.fare) > 0
            ? Number(customSchedule.fare)
            : ((tripType === "Two Way" || (customSchedule && customSchedule.tripType === "Two Way")) ? 12000 : 9500)),
      notes: notes || req.body.instructions || "",
      tripType: tripType || customSchedule?.tripType || "One Way",
      genderPreference: genderPreference || customSchedule?.genderPreference || "Both",
      status: "Pending Dispatch",
      requestType: "Monthly Pick & Drop",
      category: "Monthly Pick & Drop"
    });

    const savedRide = await newRide.save();

    // Also sync to riderequests collection so both collections stay updated
    try {
      const db = mongoose.connection.db;
      if (db) {
        await db.collection("riderequests").updateOne(
          { requestId: savedRide.requestId },
          { $set: savedRide.toObject() },
          { upsert: true }
        );
      }
    } catch (syncErr) {
      console.warn("Sync to riderequests notice:", syncErr.message);
    }

    // Emit real-time event to Admin Portal via Socket.IO
    try {
      const io = req.app.get("io");
      if (io) {
        const ridePayload = {
          _id: savedRide._id,
          id: savedRide.requestId || savedRide._id,
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
          requestType: "Monthly Pick & Drop",
          category: "Monthly Pick & Drop",
          type: "Monthly Pick & Drop",
          createdAt: savedRide.createdAt
        };

        // Emit all event variations for admin dispatch listeners
        io.emit("new-ride", ridePayload);
        io.emit("ride-update", { type: "NEW_RIDE", ride: ridePayload });
        io.emit("new-monthly-ride", ridePayload);
        io.emit("monthly-ride-update", { type: "NEW_MONTHLY_RIDE", ride: ridePayload });
        io.emit("new-monthly-pickup", ridePayload);
        io.emit("monthly-pickup-update", { type: "NEW_MONTHLY_PICKUP", ride: ridePayload });
        io.emit("new-monthly-request", ridePayload);
        io.emit("monthly-request-update", { type: "NEW_MONTHLY_REQUEST", ride: ridePayload });
        io.emit("new_ride", ridePayload);
        io.emit("new_ride_request", ridePayload);
        io.emit("new-request", ridePayload);
        io.emit("request-update", { type: "NEW_REQUEST", request: ridePayload, ride: ridePayload });
        console.log("📡 Real-time event emitted: new-ride, new-monthly-ride", savedRide.requestId);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(201).json({
      success: true,
      message: "Monthly ride booking submitted successfully. Awaiting dispatch.",
      ride: savedRide,
      requestId: savedRide.requestId,
      data: savedRide
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
    const { status, search, driverName } = req.query;
    const driverId = req.params.driverId || req.query.driverId;
    let query = {};

    if (status) {
      if (status.toLowerCase() === "pending" || status.toLowerCase() === "pending dispatch") {
        query.status = { $in: ["Pending Dispatch", "Pending", "PENDING", "pending dispatch", "Replacement Requested"] };
      } else if (status.toLowerCase() === "assigned") {
        query.status = { $in: ["ASSIGNED", "Assigned", "assigned", "Awaiting Driver Acceptance", "Dispatched"] };
      } else {
        query.status = status;
      }
    }

    if (driverId || driverName) {
      const orConditions = [];
      if (driverId) {
        orConditions.push({ assignedDriverId: driverId });
        orConditions.push({ driverId: driverId });
        orConditions.push({ driver: driverId });
        orConditions.push({ assignedDriverCode: driverId });
        orConditions.push({ "assignedDriverDetails.driverId": driverId });
        orConditions.push({ "assignedDriverDetails.driverCode": driverId });
        orConditions.push({ assignedDriverId: new RegExp('^' + driverId + '$', 'i') });
        try {
          if (mongoose.Types.ObjectId.isValid(driverId)) {
            const objId = new mongoose.Types.ObjectId(driverId);
            orConditions.push({ assignedDriverId: objId });
            orConditions.push({ driverId: objId });
            orConditions.push({ driver: objId });
          }
        } catch (_) {}
      }
      if (driverName) {
        orConditions.push({ assignedDriverName: new RegExp('^' + driverName.trim() + '$', 'i') });
        orConditions.push({ "assignedDriverDetails.name": new RegExp('^' + driverName.trim() + '$', 'i') });
      }
      query.$or = orConditions;
    }

    if (search) {
      const searchConds = [
        { requestId: { $regex: search, $options: "i" } },
        { passengerName: { $regex: search, $options: "i" } },
        { passengerPhone: { $regex: search, $options: "i" } },
        { pickupLocation: { $regex: search, $options: "i" } },
        { dropoffLocation: { $regex: search, $options: "i" } }
      ];
      if (query.$or) {
        query.$and = [{ $or: query.$or }, { $or: searchConds }];
        delete query.$or;
      } else {
        query.$or = searchConds;
      }
    }

    const rides = await RideRequest.find(query).sort({ createdAt: -1 }).lean();

    const pendingCount = await RideRequest.countDocuments({
      status: { $in: ["Pending Dispatch", "Pending", "PENDING", "pending dispatch", "Replacement Requested"] }
    });
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
      isPending: /pending/i.test(ride.status) || ride.status === 'Replacement Requested',
      isAssigned: ride.status === 'ASSIGNED',
      requestType: ride.requestType || "Monthly Pick & Drop",
      category: ride.category || "Monthly Pick & Drop",
      type: "Monthly Pick & Drop",
      assignedDriver: ride.assignedDriverName || ride.assignedDriver || null,
      assignedDriverName: ride.assignedDriverName || ride.assignedDriver || null,
      assignedDriverId: ride.assignedDriverId || ride.driverId || ride.driver || null,
      driverId: ride.driverId || ride.assignedDriverId || ride.driver || null,
      createdAt: ride.createdAt
    }));

    // Fetch replacement requests if available and merge into formattedRides
    try {
      const rplCol = mongoose.connection.db.collection("replacementrequests");
      let rplQuery = {};
      if (query.status) {
        rplQuery.status = query.status;
      }
      if (driverId) {
        const rplOr = [
          { "assignedDriver.driverId": driverId },
          { "assignedDriver.driverCode": driverId },
          { assignedDriverId: driverId },
          { driverId: driverId }
        ];
        if (mongoose.Types.ObjectId.isValid(driverId)) {
          rplOr.push({ "assignedDriver.driverId": new mongoose.Types.ObjectId(driverId) });
        }
        rplQuery.$or = rplOr;
      }
      if (driverName) {
        const nameReg = new RegExp('^' + driverName.trim() + '$', "i");
        if (rplQuery.$or) {
          rplQuery.$or.push({ "assignedDriver.name": nameReg });
        } else {
          rplQuery.$or = [{ "assignedDriver.name": nameReg }];
        }
      }
      const replacementDocs = await rplCol.find(rplQuery).sort({ createdAt: -1 }).toArray();

      for (const rpl of replacementDocs) {
        const rplReqId = rpl.requestId || "";
        const rplRideId = rpl.rideId || rplReqId;
        const alreadyIncluded = formattedRides.some(r => r.requestId === rplRideId || r.requestId === rplReqId || r._id === rplReqId);
        if (!alreadyIncluded) {
          // If pickup/dropoff are missing on replacement doc, look up original RideRequest
          let orig = null;
          if ((!rpl.pickupLocation || !rpl.dropoffLocation) && rplRideId) {
            orig = await RideRequest.findOne({
              $or: [
                { requestId: rplRideId },
                ...(mongoose.Types.ObjectId.isValid(rplRideId) ? [{ _id: new mongoose.Types.ObjectId(rplRideId) }] : [])
              ]
            }).lean().catch(() => null);
          }

          const resolvedPickup = rpl.pickupLocation || rpl.pickup || (orig ? orig.pickupLocation : null) || "Pickup Location";
          const resolvedDropoff = rpl.dropoffLocation || rpl.dropoff || (orig ? orig.dropoffLocation : null) || "Drop-off Location";
          const resolvedTimeToReach = rpl.timeToReach || (orig ? orig.timeToReach : null) || rpl.timeSlot || rpl.scheduledTime || "08:00 AM";
          const resolvedTimeToLeave = rpl.timeToLeave || (orig ? orig.timeToLeave : null) || "05:00 PM";
          const resolvedClientName = rpl.clientName || rpl.passengerName || (orig ? orig.passengerName : null) || "Customer";
          const resolvedClientPhone = rpl.clientPhone || rpl.passengerPhone || (orig ? orig.passengerPhone : null) || "";

          const dObj = rpl.assignedDriver || {};
          formattedRides.push({
            _id: rplReqId || (rpl._id ? rpl._id.toString() : ""),
            id: rplReqId || (rpl._id ? rpl._id.toString() : ""),
            mongoId: rpl._id ? rpl._id.toString() : rplReqId,
            requestId: rplReqId,
            rideId: rplRideId,
            passengerName: resolvedClientName,
            passengerPhone: resolvedClientPhone,
            passengerEmail: rpl.passengerEmail || "",
            passenger: {
              name: resolvedClientName,
              phone: resolvedClientPhone,
              email: rpl.passengerEmail || ""
            },
            pickupLocation: resolvedPickup,
            dropoffLocation: resolvedDropoff,
            pickup: resolvedPickup,
            drop: resolvedDropoff,
            route: {
              pickup: resolvedPickup,
              dropoff: resolvedDropoff,
              summary: `${resolvedPickup} -> ${resolvedDropoff}`,
              passengers: 1
            },
            scheduledTime: resolvedTimeToReach,
            timeToReach: resolvedTimeToReach,
            pickupTime: resolvedTimeToReach,
            timeToLeave: resolvedTimeToLeave,
            dropoffTime: resolvedTimeToLeave,
            startingFrom: rpl.scheduledDate || rpl.startingFrom || (orig ? orig.startingFrom : null) || new Date().toISOString().split("T")[0],
            scheduleType: "Monthly Replacement",
            scheduleTime: resolvedTimeToReach,
            customSchedule: {},
            selectedDays: "Mon - Sat",
            vehicle: {
              type: dObj.vehicle || "Sedan",
              seating: "Standard",
              selection: "Separate",
              ac: dObj.ac ? "AC" : "Non-AC",
              label: `${dObj.vehicle || "Sedan"} • ${dObj.ac ? "AC" : "Non-AC"}`
            },
            vehicleType: dObj.vehicle || "Sedan",
            acPreference: dObj.ac ? "AC" : "Non-AC",
            tripType: "One Way",
            genderPreference: "Both",
            vehicleTypeSelection: "Separate",
            seatingArrangement: "Standard",
            passengersCount: 1,
            fare: rpl.fare || 0,
            fareFormatted: rpl.fareFormatted || `Rs. ${(rpl.fare || 0).toLocaleString()}`,
            notes: rpl.reason || "",
            cnic: "",
            status: rpl.status || "ASSIGNED",
            statusLabel: rpl.status || "ASSIGNED",
            isPending: /pending/i.test(rpl.status || '') || rpl.status === 'Replacement Requested',
            isAssigned: rpl.status === 'ASSIGNED' || rpl.status === 'Dispatched',
            assignedDriver: dObj.name || "",
            assignedDriverName: dObj.name || "",
            assignedDriverId: dObj.driverId || "",
            driverId: dObj.driverId || "",
            createdAt: rpl.createdAt || new Date()
          });
        }
      }
    } catch (_) {}

    // Ensure all rides (regular + replacements) are strictly sorted by creation date descending
    formattedRides.sort((a, b) => {
      const timeA = new Date(a.createdAt || 0).getTime();
      const timeB = new Date(b.createdAt || 0).getTime();
      return timeB - timeA;
    });

    return res.status(200).json({
      success: true,
      count: formattedRides.length,
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
    let ride = null;
    if (mongoose.Types.ObjectId.isValid(req.params.id)) {
      ride = await RideRequest.findById(req.params.id).catch(() => null);
    }
    if (!ride) {
      ride = await RideRequest.findOne({ requestId: req.params.id }).catch(() => null);
    }
    if (!ride) {
      try {
        const rplCol = mongoose.connection.db.collection("replacementrequests");
        const rplDoc = await rplCol.findOne({
          $or: [
            { requestId: req.params.id },
            ...(mongoose.Types.ObjectId.isValid(req.params.id) ? [{ _id: new mongoose.Types.ObjectId(req.params.id) }] : [])
          ]
        });
        if (rplDoc) ride = rplDoc;
      } catch (_) {}
    }
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
    // Also clear driverIssue so the newly assigned driver starts fresh
    const updatedRide = await RideRequest.findByIdAndUpdate(
      existingRide._id,
      {
        status: "ASSIGNED",
        assignedDriverId: driverId || null,
        driverId: driverId || null,
        driver: driverId || null,
        assignedDriverName: assignedName || "Assigned Driver",
        assignedDriver: assignedName || "Assigned Driver",
        driverIssue: null
      },
      { returnDocument: 'after', new: true }
    );

    // Also sync replacement request if one exists for this ride
    try {
      await mongoose.connection.db.collection("replacementrequests").updateMany(
        { $or: [{ rideId: existingRide.requestId }, { requestId: existingRide.requestId }] },
        {
          $set: {
            status: "ASSIGNED",
            "assignedDriver.driverId": driverId || "",
            "assignedDriver.name": assignedName || "Assigned Driver",
            "assignedDriver.assignedAt": new Date().toISOString()
          }
        }
      );
    } catch (_) {}

    if (!updatedRide) {
      return res.status(404).json({
        success: false,
        message: "Ride request not found after update"
      });
    }

    // Persist DriverNotification for Dispatched Ride
    try {
      const driverNotif = {
        driverId: driverId || "",
        driverName: assignedName || "Assigned Driver",
        driverReferenceId: driverId || "",
        rideId: updatedRide.requestId,
        requestId: updatedRide.requestId,
        mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
        notificationId: `${updatedRide.requestId}_ASSIGNED`,
        title: "🚗 New Ride Dispatched!",
        subtitle: `Admin assigned ride ${updatedRide.requestId} (${updatedRide.passengerName || "Customer"}) to you. Tap to view ride details.`,
        status: "ASSIGNED",
        type: "NEW_ASSIGNMENT",
        customerName: updatedRide.passengerName || "Customer",
        customerPhone: updatedRide.passengerPhone || "",
        pickup: updatedRide.pickupLocation || "Pickup Point",
        destination: updatedRide.dropoffLocation || "Destination Point",
        fareFormatted: updatedRide.fare ? `Rs. ${Number(updatedRide.fare).toLocaleString()}` : "Rs. 9,500",
        payload: updatedRide,
        isRead: false,
        isDismissed: false
      };
      await DriverNotification.findOneAndUpdate(
        { notificationId: `${updatedRide.requestId}_ASSIGNED` },
        driverNotif,
        { upsert: true, new: true }
      );
      const io = req.app.get("io");
      if (io) {
        const fullPayload = {
          ...driverNotif,
          ride: updatedRide,
          data: updatedRide,
          payload: updatedRide
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

        // Global broadcast for any active sockets
        io.emit("new-assignment", fullPayload);
        io.emit("ride-assigned", fullPayload);
        io.emit("ride-dispatched", fullPayload);
        io.emit("new-notification", fullPayload);
        io.emit("driver-notification", fullPayload);
        io.emit("ride-updated", { type: "RIDE_DISPATCHED", ride: updatedRide, notification: driverNotif });
      }
    } catch (driverNotifErr) {
      console.warn("Failed saving driver notification for dispatched ride:", driverNotifErr.message);
    }

    // Persist CustomerNotification for Driver Assigned (admin assigned — driver has NOT accepted yet)
    try {
      await CustomerNotification.findOneAndUpdate(
        { notificationId: `${updatedRide.requestId}_ASSIGNED` },
        {
          customerId: updatedRide.customerId || updatedRide.passengerPhone,
          passengerPhone: updatedRide.passengerPhone,
          passengerEmail: updatedRide.passengerEmail || "",
          rideId: updatedRide.requestId,
          mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
          notificationId: `${updatedRide.requestId}_ASSIGNED`,
          title: "📋 Driver Assigned!",
          subtitle: `Driver ${assignedName || "A driver"} has been assigned to your ride (${updatedRide.requestId}). Waiting for driver confirmation.`,
          status: "ASSIGNED",
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
        // Emit ASSIGNED (not ACCEPTED) — driver has not accepted yet, admin just assigned
        io.emit("ride_assigned", {
          requestId: updatedRide.requestId,
          customerId: updatedRide.customerId,
          passengerName: updatedRide.passengerName,
          passengerPhone: updatedRide.passengerPhone,
          status: "ASSIGNED",
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
      try {
        const rplCol = mongoose.connection.db.collection("replacementrequests");
        const rplDoc = await rplCol.findOne({
          $or: [
            { requestId: rideId },
            ...(mongoose.Types.ObjectId.isValid(rideId) ? [{ _id: new mongoose.Types.ObjectId(rideId) }] : [])
          ]
        });
        if (rplDoc) {
          const updateFields = {};
          if (status) updateFields.status = status;
          if (notes !== undefined) updateFields.notes = notes;
          if (fare !== undefined && fare !== null && !isNaN(Number(fare))) updateFields.fare = Number(fare);
          if (driverId) updateFields["assignedDriver.driverId"] = driverId;
          if (driverName) updateFields["assignedDriver.name"] = driverName;
          await rplCol.updateOne({ _id: rplDoc._id }, { $set: updateFields });
          const freshRpl = await rplCol.findOne({ _id: rplDoc._id });
          return res.status(200).json({
            success: true,
            message: "Replacement ride updated successfully",
            ride: freshRpl
          });
        }
      } catch (_) {}
    }
    if (!updatedRide) {
      return res.status(404).json({
        success: false,
        message: `Ride request ${rideId} not found`
      });
    }

    const isFareUpdated = (fare !== undefined && fare !== null && !isNaN(Number(fare)) && Number(fare) >= 0 && (Number(fare) !== Number(updatedRide.fare) || status === "PRICE_UPDATED" || req.body.fareStatus === "PRICE_UPDATED"));
    if (isFareUpdated) {
      updatedRide.fare = Number(fare);
      if (!status || status === "PRICE_UPDATED") {
        if (updatedRide.status !== "COMPLETED" && updatedRide.status !== "Completed" && updatedRide.status !== "PAID") {
          updatedRide.status = "PRICE_UPDATED";
        }
      }
      updatedRide.fareResponseStatus = "Pending";
      updatedRide.fareStatus = "PRICE_UPDATED";
    }
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

    // Prepare complete payload and driver details for real-time customer and driver notifications
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

    // Persist CustomerNotification for Fare Update
    if (isFareUpdated && updatedRide.status !== "COMPLETED" && updatedRide.status !== "Completed") {
      try {
        const fareFormatted = `Rs. ${Number(updatedRide.fare || 0).toLocaleString()}`;
        const notifId = `${updatedRide.requestId}_price_updated`;

        await CustomerNotification.findOneAndUpdate(
          { notificationId: notifId },
          {
            customerId: updatedRide.customerId || updatedRide.passengerPhone,
            passengerPhone: updatedRide.passengerPhone,
            passengerEmail: updatedRide.passengerEmail || "",
            rideId: updatedRide.requestId,
            mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
            notificationId: notifId,
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has updated your ride fare to ${fareFormatted}. Tap to review and confirm.`,
            status: "PRICE_UPDATED",
            fareResponseStatus: "Pending",
            fareFormatted: fareFormatted,
            pickup: updatedRide.pickupLocation || "Pickup Point",
            destination: updatedRide.dropoffLocation || "Destination Point",
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
        console.log(`✅ CustomerNotification [PRICE_UPDATED] saved for ride ${updatedRide.requestId}: ${fareFormatted}`);
      } catch (fareNotifErr) {
        console.warn("Failed saving customer notification for updated fare:", fareNotifErr.message);
      }
    }

    // Persist CustomerNotification for Driver Accepted or Assigned (ONLY Driver Details)
    if (updatedRide.status === "ACCEPTED" || updatedRide.status === "Accepted") {
      // Only send "Driver Accepted" notification when driver ACTUALLY accepts — not when admin assigns
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
    } else if (updatedRide.status === "ASSIGNED") {
      // Admin assigned ride — notify customer that a driver is ASSIGNED (not accepted yet)
      try {
        await CustomerNotification.findOneAndUpdate(
          { notificationId: `${updatedRide.requestId}_ASSIGNED` },
          {
            customerId: updatedRide.customerId || updatedRide.passengerPhone,
            passengerPhone: updatedRide.passengerPhone,
            passengerEmail: updatedRide.passengerEmail || "",
            rideId: updatedRide.requestId,
            mongoId: updatedRide._id ? updatedRide._id.toString() : updatedRide.requestId,
            notificationId: `${updatedRide.requestId}_ASSIGNED`,
            title: "🚗 Driver Assigned!",
            subtitle: `Driver ${driverDetails.name} has been assigned to your ride (${updatedRide.requestId}). Waiting for driver confirmation.`,
            status: "ASSIGNED",
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
        console.warn("Failed saving customer notification for assigned ride:", notifErr.message);
      }
    }

    // When Driver COMPLETES Ride: Send Payment Notification & Retire Accepted Notification
    if (updatedRide.status === "COMPLETED" || updatedRide.status === "Completed") {
      try {
        // Mark all older notifications for this ride (ACCEPTED, CUSTOMER_ACCEPTED, PRICE_UPDATED, etc.) as dismissed
        await CustomerNotification.updateMany(
          {
            $or: [
              { rideId: updatedRide.requestId },
              { rideId: updatedRide._id ? updatedRide._id.toString() : "" }
            ],
            status: { $ne: "COMPLETED" }
          },
          { isDismissed: true, isRead: true }
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

        // Store / ensure payment record in Payment History (collection: payments)
        try {
          const Payment = require("../schema/Payment");
          const fareStr = notifyPayload.fareFormatted || (updatedRide.fare ? `Rs. ${Number(updatedRide.fare).toLocaleString()}` : "Rs. 0");
          await Payment.findOneAndUpdate(
            { rideId: updatedRide.requestId },
            {
              customerId: updatedRide.customerId || null,
              customerName: updatedRide.passengerName || "Customer",
              customerPhone: updatedRide.passengerPhone || "",
              rideId: updatedRide.requestId,
              fare: fareStr,
              pickup: updatedRide.pickupLocation || "",
              destination: updatedRide.dropoffLocation || "",
              driverName: driverDetails.name || "",
              status: updatedRide.isPaid ? "PAID" : "PENDING PAYMENT"
            },
            { upsert: true, new: true }
          );
          console.log(`✅ Payment record stored in Payment History for ride ${updatedRide.requestId}: ${fareStr}`);
        } catch (paySaveErr) {
          console.warn("Notice saving payment record for completed ride:", paySaveErr.message);
        }
      } catch (notifErr) {
        console.warn("Failed saving customer notification for completed ride:", notifErr.message);
      }
      if (driverDetails.driverId) {
        try {
          await DriverNotification.findOneAndUpdate(
            { notificationId: `${updatedRide.requestId}_COMPLETED` },
            {
              driverId: driverDetails.driverId,
              driverReferenceId: driverDetails.driverCode,
              driverName: driverDetails.name,
              rideId: updatedRide.requestId,
              notificationId: `${updatedRide.requestId}_COMPLETED`,
              title: "🏁 Trip Completed!",
              subtitle: `Trip for ${updatedRide.passengerName || "Customer"} (${updatedRide.requestId}) has been completed successfully.`,
              customerName: updatedRide.passengerName || "Customer",
              customerPhone: updatedRide.passengerPhone || "",
              pickup: updatedRide.pickupLocation || "Pickup Point",
              destination: updatedRide.dropoffLocation || "Destination Point",
              fareFormatted: notifyPayload.fareFormatted,
              status: "COMPLETED",
              type: "TRIP_COMPLETED",
              isRead: false,
              isDismissed: false
            },
            { upsert: true, new: true }
          ).catch(() => {});
        } catch (_) {}
      }
    }

    // Emit Real-time Socket.IO events
    try {
      const io = req.app.get("io");
      if (io) {
        const custId = updatedRide.customerId ? String(updatedRide.customerId) : "";
        const custPhone = updatedRide.passengerPhone ? String(updatedRide.passengerPhone) : "";
        const drvId = driverDetails.driverId ? String(driverDetails.driverId) : "";
        const rId = String(updatedRide.requestId);

        if (updatedRide.status === "ACCEPTED" || updatedRide.status === "Accepted") {
          if (custId) io.to(`customer_${custId}`).emit("ride-accepted", notifyPayload);
          if (custPhone) io.to(`customer_${custPhone}`).emit("ride-accepted", notifyPayload);
          io.to(`ride_${rId}`).emit("ride-accepted", notifyPayload);
        }
        if (updatedRide.status === "COMPLETED" || updatedRide.status === "Completed") {
          const completedPayload = {
            ...notifyPayload,
            id: `${rId}_COMPLETED`,
            notificationId: `${rId}_COMPLETED`,
            rideId: rId,
            requestId: rId,
            type: "RIDE_COMPLETED",
            status: "COMPLETED",
            title: "💳 Ride Completed - Pay Fare",
            subtitle: `Your ride ${rId} is complete. Please tap to submit payment of ${notifyPayload.fareFormatted}.`,
            fareFormatted: notifyPayload.fareFormatted,
            fare: updatedRide.fare,
            pickup: updatedRide.pickupLocation,
            destination: updatedRide.dropoffLocation,
            driverDetails: driverDetails,
            driverName: driverDetails.name,
            createdAt: new Date().toISOString()
          };

          if (custId) {
            io.to(`customer_${custId}`).emit("ride-completed", completedPayload);
            io.to(`customer_${custId}`).emit("customer-notification", completedPayload);
            io.to(`customer_${custId}`).emit("ride-updated", completedPayload);
          }
          if (custPhone) {
            io.to(`customer_${custPhone}`).emit("ride-completed", completedPayload);
            io.to(`customer_${custPhone}`).emit("customer-notification", completedPayload);
            io.to(`customer_${custPhone}`).emit("ride-updated", completedPayload);
          }
          if (drvId) {
            io.to(`driver_${drvId}`).emit("trip-completed", notifyPayload);
            io.to(`driver_${drvId}`).emit("driver-notification", {
              title: "🏁 Trip Completed!",
              subtitle: `Trip for ${updatedRide.passengerName || "Customer"} (${rId}) completed.`,
              rideId: rId,
              status: "COMPLETED"
            });
          }
          io.to(`ride_${rId}`).emit("ride-completed", completedPayload);
          io.emit("ride-completed", completedPayload);
          io.emit("customer-notification", completedPayload);
          io.emit("ride-updated", completedPayload);
          console.log(`📡 Real-time event [ride-completed] emitted to customer for ride ${rId}`);
        }
        if (isFareUpdated && updatedRide.status !== "COMPLETED") {
          const farePayload = {
            ...notifyPayload,
            type: "PRICE_UPDATED",
            status: "PRICE_UPDATED",
            fareUpdated: true,
            fareResponseStatus: "Pending",
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has updated your ride fare to ${notifyPayload.fareFormatted}.`
          };
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
          console.log(`📡 Real-time fare update emitted to customer for ride ${rId}: ${notifyPayload.fareFormatted}`);
        }
        if (custId) io.to(`customer_${custId}`).emit("ride-updated", notifyPayload);
        if (custPhone) io.to(`customer_${custPhone}`).emit("ride-updated", notifyPayload);
        if (drvId) io.to(`driver_${drvId}`).emit("ride-updated", notifyPayload);
        io.to(`ride_${rId}`).emit("ride-updated", notifyPayload);
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

    // Sync to riderequests collection
    try {
      const db = mongoose.connection.db;
      if (db) {
        await db.collection("riderequests").updateOne(
          { requestId: ride.requestId },
          { $set: ride.toObject() },
          { upsert: true }
        );
      }
    } catch (_) {}

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

    // Sync to riderequests and replacementrequests collections
    try {
      const db = mongoose.connection.db;
      if (db) {
        await db.collection("riderequests").updateOne(
          { requestId: ride.requestId },
          { $set: ride.toObject() },
          { upsert: true }
        );
        await db.collection("replacementrequests").updateOne(
          { $or: [{ rideId: ride.requestId }, { rideId: ride._id.toString() }, { requestId: ride.requestId }] },
          {
            $set: {
              requestId: ride.requestId,
              rideId: ride.requestId || ride._id.toString(),
              clientName: ride.passengerName,
              passengerName: ride.passengerName,
              passengerPhone: ride.passengerPhone,
              passengerEmail: ride.passengerEmail || "",
              pickupLocation: ride.pickupLocation,
              dropoffLocation: ride.dropoffLocation,
              scheduledDate: ride.startingFrom,
              startingFrom: ride.startingFrom,
              timeToReach: ride.timeToReach,
              timeToLeave: ride.timeToLeave,
              fare: ride.fare || 0,
              preferences: ride.replacementPreferences,
              status: "Replacement Requested",
              createdAt: new Date(),
              updatedAt: new Date()
            }
          },
          { upsert: true }
        );
      }
    } catch (syncErr) {
      console.warn("Replacement sync notice:", syncErr.message);
    }

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
    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    // 1. Fetch persistent notifications from CustomerNotification collection (exclude dismissed and ride assigned notifications older than 1 day)
    const storedNotifsRaw = await CustomerNotification.find({
      ...(queryConds.length > 0 ? query : {}),
      isDismissed: { $ne: true }
    }).sort({ createdAt: -1 }).lean().catch(() => []);

    const storedNotifs = storedNotifsRaw.filter(n => {
      const isAssigned = (n.status === "ACCEPTED" || n.status === "Accepted" || n.status === "ASSIGNED" || n.status === "Driver Assigned" ||
        String(n.notificationId || "").toUpperCase().endsWith("_ACCEPTED") ||
        String(n.notificationId || "").toUpperCase().endsWith("_ASSIGNED") ||
        /driver assigned|ride assigned/i.test(n.title || ""));
      if (isAssigned && n.createdAt && new Date(n.createdAt) < oneDayAgo) {
        return false;
      }
      return true;
    });

    // Also get set of dismissed notification keys so dynamically generated items stay dismissed
    const dismissedNotifs = await CustomerNotification.find({
      ...(queryConds.length > 0 ? query : {}),
      isDismissed: true
    }).lean().catch(() => []);

    const dismissedKeys = new Set();
    const dismissedRideIds = new Set();
    for (const d of dismissedNotifs) {
      if (d.notificationId) {
        dismissedKeys.add(String(d.notificationId).toLowerCase().trim());
      }
      if (d.rideId) {
        const rIdStr = String(d.rideId).trim();
        dismissedRideIds.add(rIdStr);
        dismissedKeys.add(`${rIdStr}_${d.status}`.toLowerCase());
        dismissedKeys.add(`${rIdStr}_accepted`.toLowerCase());
        dismissedKeys.add(`${rIdStr}_completed`.toLowerCase());
        dismissedKeys.add(`${rIdStr}_price_updated`.toLowerCase());
        dismissedKeys.add(`${rIdStr}_driver_unavailable`.toLowerCase());
      }
    }

    const isNotificationDismissed = (notifId, rId, status) => {
      if (notifId && dismissedKeys.has(String(notifId).toLowerCase().trim())) return true;
      if (rId && dismissedRideIds.has(String(rId).trim())) return true;
      if (rId && status && dismissedKeys.has(`${String(rId).trim()}_${status}`.toLowerCase())) return true;
      return false;
    };

    // 2. Fetch active rides for customer from RideRequest, ScheduleRide, and TravelTourismRequest collections
    const customerRides = await RideRequest.find(queryConds.length > 0 ? query : {}).sort({ updatedAt: -1 }).lean().catch(() => []);
    let scheduleRides = [];
    try {
      const ScheduleRide = require("../schema/ScheduleRide");
      scheduleRides = await ScheduleRide.find(queryConds.length > 0 ? query : {}).sort({ updatedAt: -1 }).lean().catch(() => []);
    } catch (_) {}
    let travelRequests = [];
    try {
      const TravelTourismRequest = require("../schema/TravelTourismRequest");
      travelRequests = await TravelTourismRequest.find(queryConds.length > 0 ? query : {}).sort({ updatedAt: -1 }).lean().catch(() => []);
    } catch (_) {}
    const allCustomerRides = [...customerRides, ...scheduleRides, ...travelRequests];

    // 3. Find all paid rides (from Payment collection and ride status)
    const paidRideIds = new Set();
    try {
      const Payment = require("../schema/Payment");
      const rideIdsList = allCustomerRides.map(r => r.requestId || (r._id ? r._id.toString() : "")).filter(Boolean);
      
      let paymentConds = [];
      if (customerId && mongoose.Types.ObjectId.isValid(customerId)) {
        paymentConds.push({ customerId: new mongoose.Types.ObjectId(customerId) });
      }
      if (phone) {
        paymentConds.push({ customerPhone: phone });
      }
      if (rideIdsList.length > 0) {
        paymentConds.push({ rideId: { $in: rideIdsList } });
      }

      const existingPayments = await Payment.find({
        ...(paymentConds.length > 0 ? { $or: paymentConds } : {}),
        status: { $ne: "REJECTED" }
      }).lean().catch(() => []);

      for (const p of existingPayments) {
        if (p.rideId) paidRideIds.add(String(p.rideId).trim());
      }
    } catch (_) {}

    // Check ride objects directly for payment status
    for (const r of allCustomerRides) {
      const rId = String(r.requestId || (r._id ? r._id.toString() : "")).trim();
      if (r.paymentStatus === "Paid" || r.isPaid === true || r.status === "PAID" || r.status === "Paid") {
        paidRideIds.add(rId);
      }
    }

    // 4. Identify all rides that are completed
    const completedRideIds = new Set();
    for (const r of allCustomerRides) {
      const rId = String(r.requestId || (r._id ? r._id.toString() : "")).trim();
      if (r.status === "COMPLETED" || r.status === "Completed") {
        completedRideIds.add(rId);
      }
    }
    for (const n of storedNotifs) {
      if (n.status === "COMPLETED" || n.status === "Completed") {
        const rId = String(n.rideId || n.requestId || "").trim();
        if (rId) completedRideIds.add(rId);
      }
    }

    // 5. Generate notifications dynamically for actionable active events
    const generatedNotifs = [];
    for (const r of allCustomerRides) {
      const rId = String(r.requestId || (r._id ? r._id.toString() : "")).trim();
      const fareText = r.fare ? `Rs. ${Number(r.fare).toLocaleString()}` : "Rs. 9,500";

      const isRideCompleted = completedRideIds.has(rId) || r.status === "COMPLETED" || r.status === "Completed";
      const isPaid = paidRideIds.has(rId) || r.paymentStatus === "Paid" || r.isPaid === true || r.status === "PAID";
      const hasCustomerAccepted = r.customerAccepted === true || r.status === "Customer Accepted" || r.status === "CUSTOMER_ACCEPTED";

      // A) Driver Accepted / Assigned
      // ONLY show if customer has NOT accepted yet, ride is NOT completed, and not dismissed, and assignment was within last 24 hours (1 day)
      const isAcceptedStatus = (r.status === "ACCEPTED" || r.status === "Accepted" || r.status === "ASSIGNED" || r.status === "Driver Assigned");
      const assignedTime = r.assignedAt || r.driverAcceptedAt || r.updatedAt || r.createdAt;
      const isAssignedOlderThanOneDay = assignedTime && new Date(assignedTime) < oneDayAgo;

      if (isAcceptedStatus && !hasCustomerAccepted && !isRideCompleted && !isAssignedOlderThanOneDay) {
        const notifKey = `${rId}_accepted`;
        if (!isNotificationDismissed(notifKey, rId, "ACCEPTED")) {
          const dDetails = r.assignedDriverDetails || {};
          const driverName = r.assignedDriverName || dDetails.name || "Driver";
          const driverPhone = dDetails.phone || "";
          const driverVehicle = dDetails.vehicle || (r.vehicleType ? `🚗 ${r.vehicleType}` : "🚗 Vehicle");
          const driverPlate = dDetails.registrationNumber || "REGISTERED";
          const driverRating = dDetails.rating ? `⭐ ${dDetails.rating} (Verified Driver)` : "⭐ 4.9 (Verified Driver)";

          generatedNotifs.push({
            id: notifKey,
            notificationId: notifKey,
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

      // B) Driver Issue / Unavailable (ONLY if not completed)
      if ((r.status === "Driver Unavailable" || r.status === "Replacement Requested" || r.driverIssue) && !isRideCompleted) {
        const notifKey = `${rId}_driver_unavailable`;
        if (!isNotificationDismissed(notifKey, rId, "Driver Unavailable")) {
          generatedNotifs.push({
            id: notifKey,
            notificationId: notifKey,
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

      // C) Fare / Price Update - ONLY if status is explicitly PRICE_UPDATED or Pending Dispatch with pending fare approval, not yet responded, and not completed
      const isPriceUpdated = (r.status === "PRICE_UPDATED" || r.fareStatus === "PRICE_UPDATED");
      const isFareDecided = (r.fareResponseStatus === "Fare Accepted" || r.fareResponseStatus === "Fare Rejected" || r.fareStatus === "Fare Accepted" || r.fareStatus === "Fare Rejected");

      if (isPriceUpdated && !isFareDecided && !isRideCompleted) {
        const notifKey = `${rId}_price_updated`;
        if (!isNotificationDismissed(notifKey, rId, "PRICE_UPDATED")) {
          generatedNotifs.push({
            id: notifKey,
            notificationId: notifKey,
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

      // D) Ride Completed (Payment Notification ONLY when ride is completed AND customer has NOT paid yet)
      if (isRideCompleted && !isPaid) {
        const notifKey = `${rId}_completed`;
        if (!isNotificationDismissed(notifKey, rId, "COMPLETED")) {
          generatedNotifs.push({
            id: notifKey,
            notificationId: notifKey,
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

    const seenKeys = new Set();
    const finalNotifications = [];

    for (const n of allNotifs) {
      const rId = String(n.rideId || n.requestId || n.id || "").trim();
      const st = n.status || "";

      // 0. Only show PRICE_UPDATED if ride is actually in PRICE_UPDATED status and not decided
      if (st === "PRICE_UPDATED" || (n.notificationId && String(n.notificationId).toLowerCase().includes("_price_updated"))) {
        const matchingRide = allCustomerRides.find(r => {
          const mId = String(r.requestId || (r._id ? r._id.toString() : "")).trim();
          return mId === rId;
        });
        if (matchingRide) {
          const isReallyPriceUpdated = (matchingRide.status === "PRICE_UPDATED" || matchingRide.fareStatus === "PRICE_UPDATED");
          const isDecided = (matchingRide.fareResponseStatus === "Fare Accepted" || matchingRide.fareResponseStatus === "Fare Rejected" || matchingRide.fareStatus === "Fare Accepted" || matchingRide.fareStatus === "Fare Rejected");
          if (!isReallyPriceUpdated || isDecided) {
            continue;
          }
        }
      }

      // 1. If customer accepted the ride, do not show accept ride notification
      if (n.customerAccepted === true || st === "CUSTOMER_ACCEPTED" || st === "Customer Accepted") {
        continue;
      }

      // 2. If ride is completed, retire ALL older notifications (ACCEPTED, CUSTOMER_ACCEPTED, PRICE_UPDATED, Driver Unavailable)
      if (st !== "COMPLETED" && st !== "Completed" && completedRideIds.has(rId)) {
        continue;
      }

      // 3. If ride is already paid, do NOT show "Ride Completed - Pay Fare" notification
      if ((st === "COMPLETED" || st === "Completed") && (paidRideIds.has(rId) || paidRideIds.has(String(n.rideId || "").trim()) || paidRideIds.has(String(n.requestId || "").trim()))) {
        continue;
      }

      // 4. Check if dismissed
      if (isNotificationDismissed(n.notificationId, rId, st)) {
        continue;
      }

      // 5. Automatically remove ride assigned notification when 1 day has passed (24 hours)
      const isAssignedNotif = st === "ACCEPTED" || st === "Accepted" || st === "ASSIGNED" || st === "Driver Assigned" ||
        String(n.notificationId || "").toUpperCase().endsWith("_ACCEPTED") ||
        String(n.notificationId || "").toUpperCase().endsWith("_ASSIGNED") ||
        /driver assigned|ride assigned/i.test(n.title || "");
      const notifCreatedDate = n.createdAt ? new Date(n.createdAt) : null;
      if (isAssignedNotif && notifCreatedDate && notifCreatedDate < oneDayAgo) {
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
    let rideType = "RideRequest";

    // 1. Check in RideRequest
    if (mongoose.Types.ObjectId.isValid(rideId)) {
      ride = await RideRequest.findById(rideId).catch(() => null);
    }
    if (!ride) {
      ride = await RideRequest.findOne({ requestId: rideId }).catch(() => null);
    }

    // 2. Check in ScheduleRide
    if (!ride) {
      try {
        const ScheduleRide = require("../schema/ScheduleRide");
        if (mongoose.Types.ObjectId.isValid(rideId)) {
          ride = await ScheduleRide.findById(rideId).catch(() => null);
        }
        if (!ride) {
          ride = await ScheduleRide.findOne({ requestId: rideId }).catch(() => null);
        }
        if (ride) rideType = "ScheduleRide";
      } catch (_) {}
    }

    // 3. Check in DriverHireRequest
    if (!ride) {
      try {
        const DriverHireRequest = require("../schema/DriverHireRequest");
        if (mongoose.Types.ObjectId.isValid(rideId)) {
          ride = await DriverHireRequest.findById(rideId).catch(() => null);
        }
        if (!ride) {
          ride = await DriverHireRequest.findOne({ requestId: rideId }).catch(() => null);
        }
        if (ride) rideType = "DriverHireRequest";
      } catch (_) {}
    }

    // 4. Check in TravelTourismRequest
    if (!ride) {
      try {
        const TravelTourismRequest = require("../schema/TravelTourismRequest");
        if (mongoose.Types.ObjectId.isValid(rideId)) {
          ride = await TravelTourismRequest.findById(rideId).catch(() => null);
        }
        if (!ride) {
          ride = await TravelTourismRequest.findOne({ requestId: rideId }).catch(() => null);
        }
        if (ride) rideType = "TravelTourismRequest";
      } catch (_) {}
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
    const fareFormatted = ride.fare ? `Rs. ${Number(ride.fare).toLocaleString()}` : "Rs. 9,500";

    ride.status = newStatus;
    ride.fareStatus = newStatus;
    ride.fareResponseStatus = newStatus;
    if (isAccepted) {
      ride.customerAccepted = true;
      ride.customerAcceptedAt = new Date();
    }
    await ride.save();

    // Sync to riderequests
    try {
      const db = mongoose.connection.db;
      if (db) {
        await db.collection("riderequests").updateOne(
          { requestId: ride.requestId },
          { $set: ride.toObject() },
          { upsert: true }
        );
      }
    } catch (_) {}

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

      // If customer accepted, notify assigned Driver immediately
      if (isAccepted) {
        const dDetails = ride.assignedDriverDetails || {};
        let targetDriverId = ride.assignedDriverId || dDetails.driverId || null;
        let targetDriverName = ride.assignedDriverName || dDetails.name || "";
        let targetDriverRef = dDetails.driverCode || dDetails.driverReferenceId || (ride.assignedDriverId ? String(ride.assignedDriverId) : "");
        const rId = ride.requestId || ride._id.toString();

        // If targetDriverId exists, lookup full Driver record to ensure all ID fields match
        if (targetDriverId) {
          try {
            const Driver = require("../schema/Driver");
            let drvDoc = null;
            if (mongoose.Types.ObjectId.isValid(targetDriverId)) {
              drvDoc = await Driver.findById(targetDriverId).catch(() => null);
            }
            if (!drvDoc) {
              drvDoc = await Driver.findOne({
                $or: [
                  { driverReferenceId: targetDriverId },
                  { driverCode: targetDriverId },
                  { phone: targetDriverId }
                ]
              }).catch(() => null);
            }
            if (drvDoc) {
              if (!targetDriverName) {
                targetDriverName = drvDoc.Name || `${drvDoc.firstName || ""} ${drvDoc.lastName || ""}`.trim();
              }
              if (!targetDriverRef) {
                targetDriverRef = drvDoc.driverReferenceId || drvDoc.driverCode || "";
              }
            }
          } catch (_) {}
        }

        const driverNotifData = {
          driverId: targetDriverId,
          driverReferenceId: targetDriverRef,
          driverCode: targetDriverRef,
          driverName: targetDriverName || "Driver",
          assignedDriverId: targetDriverId,
          assignedDriverName: targetDriverName || "Driver",
          rideId: rId,
          notificationId: `${rId}_FARE_ACCEPTED`,
          title: "🎉 Customer Accepted Ride!",
          subtitle: `Customer ${name} has confirmed the updated fare of ${fareFormatted} (${rId}). Tap to view ride details.`,
          customerName: name,
          customerPhone: ride.passengerPhone || "",
          pickup: ride.pickupLocation || "Pickup Point",
          destination: ride.dropoffLocation || "Destination Point",
          fareFormatted: fareFormatted,
          fare: ride.fare,
          status: "CUSTOMER_ACCEPTED",
          type: "CUSTOMER_ACCEPTED",
          isRead: false,
          isDismissed: false,
          createdAt: new Date().toISOString(),
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

        // Persist notification under both _FARE_ACCEPTED and _CUSTOMER_ACCEPTED keys
        await DriverNotification.findOneAndUpdate(
          { notificationId: `${rId}_FARE_ACCEPTED` },
          driverNotifData,
          { upsert: true, new: true }
        ).catch(() => {});

        await DriverNotification.findOneAndUpdate(
          { notificationId: `${rId}_CUSTOMER_ACCEPTED` },
          { ...driverNotifData, notificationId: `${rId}_CUSTOMER_ACCEPTED` },
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
            io.to(`driver_${targetDriverName.trim().toLowerCase()}`).emit("customer-accepted-ride", driverNotifData);
          }
          if (targetDriverRef) {
            io.to(targetDriverRef).emit("customer-accepted-ride", driverNotifData);
            io.to(`driver_${targetDriverRef}`).emit("customer-accepted-ride", driverNotifData);
          }
          // Global broadcast so connected driver device receives real-time alert without delay
          io.emit("customer-accepted-ride", driverNotifData);
          io.emit("driver-notification", driverNotifData);
          io.emit("ride-updated", { type: "CUSTOMER_ACCEPTED", ride: driverNotifData.payload, ...driverNotifData });
          io.emit("ride_accepted", driverNotifData);
          console.log(`📡 Real-time event [customer-accepted-ride] emitted for driver ${targetDriverName || "assigned"} for ride ${rId}`);
        }
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    // Dismiss price updated notification for this ride in CustomerNotification
    try {
      await CustomerNotification.updateMany(
        {
          $or: [
            { rideId: ride.requestId },
            { rideId: ride._id ? ride._id.toString() : "" },
            { notificationId: `${ride.requestId}_price_updated` },
            { notificationId: `${ride.requestId}_PRICE_UPDATED` }
          ]
        },
        { isDismissed: true, isRead: true }
      ).catch(() => {});
    } catch (_) {}

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
    const { routeId, driverId, driverName, customers, routeName, pickupPoint, dropoffPoint, timeRange } = req.body;

    if (!routeId && !routeName) {
      return res.status(400).json({
        success: false,
        message: "Route ID or routeName is required to accept route"
      });
    }

    const effectiveRouteId = (routeId || "").toString().trim();
    const effectiveRouteName = (routeName || effectiveRouteId || "Route").toString().trim();

    // 1. Locate Route by ID, Mongo ID, or Name
    let route = null;
    const searchConditions = [];
    if (effectiveRouteId) {
      searchConditions.push({ routeId: effectiveRouteId });
      if (mongoose.Types.ObjectId.isValid(effectiveRouteId)) {
        searchConditions.push({ _id: new mongoose.Types.ObjectId(effectiveRouteId) });
      }
      try {
        searchConditions.push({ routeName: new RegExp(`^${effectiveRouteId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, "i") });
      } catch (_) {}
    }
    if (effectiveRouteName) {
      try {
        searchConditions.push({ routeName: new RegExp(`^${effectiveRouteName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, "i") });
      } catch (_) {}
      searchConditions.push({ routeName: effectiveRouteName });
    }

    if (searchConditions.length > 0) {
      route = await SuggestedRoute.findOne({ $or: searchConditions });
    }

    // If route doesn't exist yet, seed or synthesize it
    if (!route) {
      const pendingRides = await RideRequest.find({ status: { $ne: "CANCELLED" } }).limit(20).lean().catch(() => []);
      const seedData = getDefaultRoutesSeed(pendingRides);
      await SuggestedRoute.insertMany(seedData).catch(() => []);
      if (searchConditions.length > 0) {
        route = await SuggestedRoute.findOne({ $or: searchConditions });
      }
    }

    // If still not found, create it dynamically so request never fails
    if (!route) {
      const generatedId = effectiveRouteId && effectiveRouteId.startsWith("ROUTE-") ? effectiveRouteId : `ROUTE-${Date.now()}`;
      route = new SuggestedRoute({
        routeId: generatedId,
        routeName: effectiveRouteName,
        pickupPoint: pickupPoint || "Pickup Point",
        dropoffPoint: dropoffPoint || "Drop Point",
        timeRange: timeRange || "8:00 AM - 10:00 AM",
        customers: Array.isArray(customers) ? customers : [],
        customerCount: Array.isArray(customers) ? customers.length : 0,
        status: "Pending"
      });
    }

    // 2. Resolve Driver Information
    let resolvedName = req.body.driverName || driverName || "Arbab";
    let resolvedPhone = req.body.driverPhone || "+92 300 9876543";
    let resolvedCode = req.body.driverCode || (driverId && driverId.toString().startsWith("DRV-") ? driverId : "DRV-1001");
    let resolvedVehicle = req.body.vehicle || req.body.driverVehicle || "Honda Accord (Super White)";
    let resolvedPlate = req.body.numberPlate || req.body.registrationNumber || "ISB-0009";
    let resolvedRating = req.body.rating || "⭐ 4.9 (Verified Driver)";

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

    // Use passed customer list if provided, otherwise route.customers
    const passedCustomers = Array.isArray(customers) && customers.length > 0 ? customers : [];
    const sourceCustomers = passedCustomers.length > 0 ? passedCustomers : (route.customers || []);

    // Update route.customers in DB
    if (passedCustomers.length > 0) {
      route.customers = passedCustomers.map((c, idx) => ({
        ...c,
        status: "ACCEPTED",
        requestId: c.requestId || `REQ-${8030 + idx + 1}`
      }));
      route.customerCount = passedCustomers.length;
    } else {
      route.customers.forEach(c => (c.status = "ACCEPTED"));
    }

    // 4. Update Each Customer Request & Create Notification
    const io = req.app.get("io");
    const notifiedCustomers = [];

    for (let i = 0; i < sourceCustomers.length; i++) {
      const cust = sourceCustomers[i];
      const reqId = cust.requestId || `REQ-${Date.now()}-${i}`;
      const custPhone = (cust.phone || "").toString().trim();
      const custPhoneDigits = custPhone.replace(/[^0-9]/g, "");
      const custCorePhone = custPhoneDigits.length >= 9 ? custPhoneDigits.slice(-9) : custPhoneDigits;
      const custName = cust.customerName || cust.name || "Customer";
      const fareFormatted = cust.fareFormatted || (cust.fare ? `Rs. ${Number(cust.fare).toLocaleString()}` : "Rs. 9,500");

      // Update matching RideRequest if exists in MongoDB
      try {
        const rideFilter = [{ requestId: reqId }];
        if (mongoose.Types.ObjectId.isValid(reqId)) {
          rideFilter.push({ _id: new mongoose.Types.ObjectId(reqId) });
        }
        if (custPhone) {
          rideFilter.push({ passengerPhone: custPhone });
          rideFilter.push({ "passenger.phone": custPhone });
        }
        if (custCorePhone && custCorePhone.length >= 9) {
          rideFilter.push({ passengerPhone: new RegExp(`${custCorePhone}$`) });
          rideFilter.push({ "passenger.phone": new RegExp(`${custCorePhone}$`) });
        }
        if (custName && custName !== "Customer") {
          rideFilter.push({ passengerName: new RegExp(`^${custName.trim()}$`, "i") });
        }

        const updateRideData = {
          status: "ACCEPTED",
          assignedDriverId: driverId || resolvedCode,
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
        };

        await RideRequest.updateMany({ $or: rideFilter }, { $set: updateRideData }).catch(() => {});

        try {
          const ScheduleRide = require("../schema/ScheduleRide");
          await ScheduleRide.updateMany({ $or: rideFilter }, { $set: updateRideData }).catch(() => {});
        } catch (_) {}

        try {
          const TravelTourismRequest = require("../schema/TravelTourismRequest");
          await TravelTourismRequest.updateMany({ $or: rideFilter }, { $set: updateRideData }).catch(() => {});
        } catch (_) {}
      } catch (errReq) {
        console.warn("RideRequest update warning:", errReq.message);
      }

      // Create persistent Notification in CustomerNotification collection
      try {
        const notifUniqueId = `${reqId}_ACCEPTED`;
        const notifConditions = [
          { notificationId: notifUniqueId },
          { notificationId: `${reqId}_DRIVER_ACCEPTED` },
          { rideId: reqId, status: "ACCEPTED" }
        ];
        if (custPhone) {
          notifConditions.push({ passengerPhone: custPhone, status: "ACCEPTED" });
        }

        await CustomerNotification.findOneAndUpdate(
          { $or: notifConditions },
          {
            $set: {
              customerId: cust.customerId || custPhone || reqId,
              passengerPhone: custPhone,
              passengerEmail: cust.email || cust.passengerEmail || "",
              rideId: reqId,
              mongoId: reqId,
              notificationId: notifUniqueId,
              title: "🚗 Driver Accepted Ride!",
              subtitle: `Driver ${resolvedName} has accepted your ride request (${reqId}) for ${route.routeName || effectiveRouteName}! Tap to view driver details.`,
              status: "ACCEPTED",
              fareFormatted: fareFormatted,
              pickup: cust.pickupLocation || cust.pickup || route.pickupPoint,
              destination: cust.dropoffLocation || cust.destination || route.dropoffPoint,
              pickupLocation: cust.pickupLocation || cust.pickup || route.pickupPoint,
              dropoffLocation: cust.dropoffLocation || cust.destination || route.dropoffPoint,
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
              isRead: false,
              isDismissed: false,
              createdAt: new Date()
            }
          },
          { upsert: true, new: true }
        );
      } catch (notifErr) {
        console.warn("Failed saving customer notification:", notifErr.message);
      }

      // Prepare Socket.IO payload
      const notifyPayload = {
        id: reqId,
        requestId: reqId,
        rideId: reqId,
        customerId: cust.customerId || custPhone || reqId,
        customerName: custName,
        passengerName: custName,
        passengerPhone: custPhone,
        passengerEmail: cust.email || "",
        title: "🚗 Driver Accepted Ride!",
        subtitle: `Driver ${resolvedName} accepted your ride request for ${route.routeName || effectiveRouteName}. Tap to view driver details.`,
        fareFormatted: fareFormatted,
        fare: cust.fare,
        status: "ACCEPTED",
        pickup: cust.pickupLocation || cust.pickup || route.pickupPoint,
        destination: cust.dropoffLocation || cust.destination || route.dropoffPoint,
        pickupLocation: cust.pickupLocation || cust.pickup || route.pickupPoint,
        dropoffLocation: cust.dropoffLocation || cust.destination || route.dropoffPoint,
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
            io.to(`customer_${cust.customerId}`).emit("ride_accepted", notifyPayload);
            io.to(String(cust.customerId)).emit("ride-accepted", notifyPayload);
            io.to(String(cust.customerId)).emit("ride_accepted", notifyPayload);
          }
          if (custPhone) {
            const phoneRooms = [
              custPhone,
              custPhoneDigits,
              custCorePhone,
              `0${custCorePhone}`,
              `+92${custCorePhone}`,
              `92${custCorePhone}`,
              `+92 ${custCorePhone}`
            ];
            for (const pr of phoneRooms) {
              if (pr) {
                io.to(`customer_${pr}`).emit("ride-accepted", notifyPayload);
                io.to(`customer_${pr}`).emit("ride_accepted", notifyPayload);
                io.to(String(pr)).emit("ride-accepted", notifyPayload);
                io.to(String(pr)).emit("ride_accepted", notifyPayload);
              }
            }
          }
          if (reqId) {
            io.to(`ride_${reqId}`).emit("ride-accepted", notifyPayload);
            io.to(`ride_${reqId}`).emit("ride_accepted", notifyPayload);
          }

          // Broadcast to all connected customer dashboards
          io.emit("ride-accepted", notifyPayload);
          io.emit("ride_accepted", notifyPayload);
          io.emit("customer-notification", notifyPayload);
          io.emit("customer_notification", notifyPayload);
          io.emit("driver-assigned", notifyPayload);
          io.emit("ride-updated", { type: "ACCEPTED", ride: notifyPayload, notification: notifyPayload });
          io.emit("ride_updated", { type: "ACCEPTED", ride: notifyPayload, notification: notifyPayload });
        } catch (_) {}
      }

      notifiedCustomers.push({
        name: custName,
        phone: custPhone,
        requestId: reqId
      });
    }

    await route.save().catch(() => {});

    // Create persistent DriverNotification for this driver
    try {
      const driverNotif = new DriverNotification({
        driverId: driverId || resolvedCode || null,
        driverReferenceId: resolvedCode,
        title: `✅ Route Accepted: ${route.routeName}`,
        subtitle: `You accepted ${route.routeName}. Notifications dispatched to all ${sourceCustomers.length} passengers.`,
        routeId: route.routeId,
        routeName: route.routeName,
        customerCount: sourceCustomers.length,
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
        customerCount: sourceCustomers.length,
        acceptedAt: route.acceptedAt
      });
      io.emit("ride-update", {
        type: "ROUTE_ACCEPTED",
        routeId: route.routeId,
        driverName: resolvedName
      });
      console.log(`🚀 Route ${route.routeName} accepted by ${resolvedName}. Real-time notifications dispatched to all ${sourceCustomers.length} customers.`);
    }

    return res.status(200).json({
      success: true,
      message: `Route '${route.routeName}' successfully accepted! Notifications have been sent to all ${sourceCustomers.length} customers.`,
      route,
      notifiedCount: sourceCustomers.length,
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

    let queryConds = [];
    let driverMatchRides = [];

    if (driverId) {
      queryConds.push({ driverId: driverId });
      queryConds.push({ driverReferenceId: driverId });
      driverMatchRides.push({ assignedDriverId: driverId });
      driverMatchRides.push({ driverId: driverId });
      driverMatchRides.push({ driver: driverId });
      driverMatchRides.push({ assignedDriverId: new RegExp('^' + driverId + '$', "i") });
      driverMatchRides.push({ "assignedDriverDetails.driverId": driverId });
      driverMatchRides.push({ "assignedDriver.driverId": driverId });
      if (mongoose.Types.ObjectId.isValid(driverId)) {
        queryConds.push({ driverId: new mongoose.Types.ObjectId(driverId) });
        driverMatchRides.push({ assignedDriverId: new mongoose.Types.ObjectId(driverId) });
        driverMatchRides.push({ driverId: new mongoose.Types.ObjectId(driverId) });
        driverMatchRides.push({ driver: new mongoose.Types.ObjectId(driverId) });
      }
    }

    if (driverName) {
      queryConds.push({ driverName: new RegExp(`^${driverName.trim()}$`, "i") });
      driverMatchRides.push({ assignedDriverName: new RegExp(`^${driverName.trim()}$`, "i") });
      driverMatchRides.push({ "assignedDriverDetails.name": new RegExp(`^${driverName.trim()}$`, "i") });
    }

    // 1. Fetch persistent notifications from DriverNotification collection
    if (queryConds.length === 0 && driverMatchRides.length === 0) {
      return res.status(200).json({ success: true, count: 0, notifications: [] });
    }

    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    let storedNotifications = [];
    if (queryConds.length > 0) {
      const rawStoredNotifications = await DriverNotification.find({
        $or: queryConds,
        isDismissed: { $ne: true }
      })
        .sort({ createdAt: -1 })
        .lean()
        .catch(() => []);

      storedNotifications = rawStoredNotifications.filter(n => {
        const isRideAssigned = (n.type === "RIDE_ASSIGNED" || n.status === "ASSIGNED" ||
          String(n.notificationId || "").toUpperCase().endsWith("_ASSIGNED") ||
          /ride assigned|ride dispatched|new ride assigned/i.test(n.title || ""));
        if (isRideAssigned && n.createdAt && new Date(n.createdAt) < oneDayAgo) {
          return false;
        }
        return true;
      });
    }

    let dismissedNotifs = [];
    if (queryConds.length > 0) {
      dismissedNotifs = await DriverNotification.find({
      $or: queryConds,
      isDismissed: true
    }).lean().catch(() => []);
    }
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

        // Skip completed, paid, cancelled, or rejected rides
        if (st === "completed" || st === "paid" || st === "cancelled" || st === "rejected") {
          continue;
        }

        // Customer Accepted Ride or Confirmed Fare
        if (
          r.customerAccepted === true ||
          st.includes("customer accepted") ||
          st.includes("fare accepted") ||
          st === "confirmed"
        ) {
          const notifKey = `${rId}_CUSTOMER_ACCEPTED`;
          if (!dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId)) {
            const isFareConf = st.includes("fare accepted") || r.fareResponseStatus === "Fare Accepted" || r.fareStatus === "Fare Accepted";
            dynamicNotifs.push({
              id: `${rId}_customer_accepted`,
              notificationId: notifKey,
              title: isFareConf ? "🎉 Customer Confirmed Fare!" : "🎉 Customer Accepted Ride!",
              subtitle: isFareConf
                ? `Customer ${custName} has confirmed the updated fare of ${fareText} (${rId}). Tap to view ride details.`
                : `Customer ${custName} has accepted your ride request (${rId}). Tap to view ride details.`,
              rideId: rId,
              requestId: rId,
              mongoId: r._id ? r._id.toString() : rId,
              customerName: custName,
              customerPhone: r.passengerPhone || "",
              pickup: r.pickupLocation || "Pickup Point",
              destination: r.dropoffLocation || "Destination Point",
              fareFormatted: fareText,
              fare: r.fare,
              status: "CUSTOMER_ACCEPTED",
              type: "CUSTOMER_ACCEPTED",
              isRead: false,
              isDismissed: false,
              createdAt: r.customerAcceptedAt || r.updatedAt || r.createdAt || new Date().toISOString()
            });
          }
        }

        // New Ride Assigned by Admin
        else if (st === "assigned" || st === "accepted") {
          const notifKey = `${rId}_ASSIGNED`;
          const assignedTimestamp = r.assignedAt || r.updatedAt || r.createdAt;
          const isOlderThanOneDay = assignedTimestamp && new Date(assignedTimestamp) < oneDayAgo;

          if (!isOlderThanOneDay && !dismissedKeys.has(notifKey) && !dismissedRideIds.has(rId) && !dismissedKeys.has(`${rId}_CUSTOMER_ACCEPTED`)) {
            dynamicNotifs.push({
              id: `${rId}_assigned`,
              notificationId: notifKey,
              title: "🚗 New Ride Assigned!",
              subtitle: `Admin assigned ride ${rId} (${custName}) to you. Tap to view ride details.`,
              rideId: rId,
              requestId: rId,
              mongoId: r._id ? r._id.toString() : rId,
              customerName: custName,
              customerPhone: r.passengerPhone || "",
              pickup: r.pickupLocation || "Pickup Point",
              destination: r.dropoffLocation || "Destination Point",
              fareFormatted: fareText,
              status: "ASSIGNED",
              type: "RIDE_ASSIGNED",
              isRead: false,
              isDismissed: false,
              createdAt: r.updatedAt || r.createdAt || new Date().toISOString()
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
      const notifCreatedDate = n.createdAt ? new Date(n.createdAt) : null;
      const isRideAssigned = (n.type === "RIDE_ASSIGNED" || n.status === "ASSIGNED" ||
        String(key).toUpperCase().endsWith("_ASSIGNED") ||
        /ride assigned|ride dispatched|new ride assigned/i.test(n.title || ""));

      if (isRideAssigned && notifCreatedDate && notifCreatedDate < oneDayAgo) {
        continue; // Automatically remove ride assigned notification when one day has passed
      }

      if (!seenMap.has(key) && !dismissedKeys.has(key)) {
        seenMap.add(key);
        merged.push({
          ...n,
          id: n.notificationId || n._id || n.id,
          notificationId: key
        });
      }
    }

    const notifications = merged;

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
    const { customerId, phone, rideId: reqRideId } = req.body || {};

    if (id) {
      const cleanRideId = reqRideId || id.replace(/_accepted|_price_updated|_driver_unavailable|_completed/i, "");

      if (id.match(/^[0-9a-fA-F]{24}$/)) {
        await CustomerNotification.findByIdAndUpdate(id, { isDismissed: true, isRead: true }).catch(() => {});
      }
      await CustomerNotification.updateMany(
        {
          $or: [
            { notificationId: id },
            { notificationId: `${cleanRideId}_accepted` },
            { notificationId: `${cleanRideId}_completed` },
            { notificationId: `${cleanRideId}_price_updated` },
            { notificationId: `${cleanRideId}_driver_unavailable` },
            { rideId: id },
            { rideId: cleanRideId }
          ]
        },
        { isDismissed: true, isRead: true }
      ).catch(() => {});

      // Also record dismissed state for dynamically generated IDs (e.g. REQ-8033_accepted)
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

    // Also mark all current rides for this customer as having their active notifications dismissed
    const allRides = await RideRequest.find(query).lean().catch(() => []);
    for (const r of allRides) {
      const rId = r.requestId || (r._id ? r._id.toString() : "");
      if (rId) {
        await CustomerNotification.findOneAndUpdate(
          { notificationId: `${rId}_clear_all` },
          {
            notificationId: `${rId}_clear_all`,
            rideId: rId,
            status: "DISMISSED",
            title: "Dismissed All",
            subtitle: "",
            isDismissed: true,
            isRead: true,
            ...(customerId ? { customerId } : {}),
            ...(phone ? { passengerPhone: phone } : {})
          },
          { upsert: true }
        ).catch(() => {});
      }
    }

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
    let queryConds = [];
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

    // Sync to riderequests
    try {
      const db = mongoose.connection.db;
      if (db) {
        await db.collection("riderequests").updateOne(
          { requestId: ride.requestId },
          { $set: ride.toObject() },
          { upsert: true }
        );
      }
    } catch (_) {}

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

    // 2. Dismiss CustomerNotification for driver accepted / assigned since customer has now accepted
    try {
      await CustomerNotification.updateMany(
        {
          $or: [
            { rideId: resolvedRideId },
            { notificationId: `${resolvedRideId}_ACCEPTED` },
            { notificationId: `${resolvedRideId}_accepted` }
          ]
        },
        {
          subtitle: `You accepted this ride with Driver ${targetDriverName}.`,
          status: "CUSTOMER_ACCEPTED",
          isDismissed: true,
          isRead: true
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

// 22. Get Driver Ride History (with Earnings & Metrics Summary)
exports.getDriverRideHistory = async (req, res) => {
  try {
    const driverId = req.params.driverId || req.query.driverId;
    const { status, timeframe, search, driverName } = req.query;

    if (!driverId && !driverName) {
      return res.status(400).json({
        success: false,
        message: "Driver ID or Driver Name is required."
      });
    }

    let ScheduleRideModel;
    try { ScheduleRideModel = require("../schema/ScheduleRide"); } catch (_) {}
    let TravelTourismModel;
    try { TravelTourismModel = require("../schema/TravelTourismRequest"); } catch (_) {}
    let DriverHireModel;
    try { DriverHireModel = require("../schema/DriverHireRequest"); } catch (_) {}

    // Build conditions for matching the driver
    const driverConditions = [];
    if (driverId) {
      driverConditions.push({ assignedDriverId: driverId });
      driverConditions.push({ driverId: driverId });
      driverConditions.push({ driver: driverId });
      driverConditions.push({ assignedDriverCode: driverId });
      driverConditions.push({ "assignedDriverDetails.driverId": driverId });
      driverConditions.push({ "assignedDriverDetails.driverCode": driverId });
      driverConditions.push({ assignedDriverId: new RegExp('^' + driverId + '$', 'i') });
      if (mongoose.Types.ObjectId.isValid(driverId)) {
        try {
          const objId = new mongoose.Types.ObjectId(driverId);
          driverConditions.push({ assignedDriverId: objId });
          driverConditions.push({ driverId: objId });
          driverConditions.push({ driver: objId });
        } catch (_) {}
      }
    }
    if (driverName) {
      const nameReg = new RegExp('^' + driverName.trim() + '$', 'i');
      driverConditions.push({ assignedDriverName: nameReg });
      driverConditions.push({ "assignedDriverDetails.name": nameReg });
    }

    // Date filtering (timeframe)
    let dateFilter = null;
    const now = new Date();
    if (timeframe === "today") {
      const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      dateFilter = { $gte: startOfDay };
    } else if (timeframe === "week") {
      const startOfWeek = new Date(now);
      startOfWeek.setDate(now.getDate() - 7);
      dateFilter = { $gte: startOfWeek };
    } else if (timeframe === "month") {
      const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
      dateFilter = { $gte: startOfMonth };
    }

    let baseQuery = { $or: driverConditions };
    if (dateFilter) {
      baseQuery.createdAt = dateFilter;
    }

    // Fetch rides from RideRequest
    let allRides = await RideRequest.find(baseQuery).sort({ createdAt: -1 }).lean().catch(() => []);

    // Also fetch from ScheduleRide if available
    if (ScheduleRideModel) {
      try {
        const schedRides = await ScheduleRideModel.find(baseQuery).sort({ createdAt: -1 }).lean();
        if (schedRides && schedRides.length > 0) {
          allRides = allRides.concat(schedRides);
        }
      } catch (_) {}
    }

    // Also fetch from TravelTourismRequest if available
    if (TravelTourismModel) {
      try {
        const ttRides = await TravelTourismModel.find(baseQuery).sort({ createdAt: -1 }).lean();
        if (ttRides && ttRides.length > 0) {
          allRides = allRides.concat(ttRides);
        }
      } catch (_) {}
    }

    // Also fetch from DriverHireRequest if available
    if (DriverHireModel) {
      try {
        const hirRides = await DriverHireModel.find(baseQuery).sort({ createdAt: -1 }).lean();
        if (hirRides && hirRides.length > 0) {
          allRides = allRides.concat(hirRides);
        }
      } catch (_) {}
    }

    // Also fetch replacement requests
    try {
      const rplCol = mongoose.connection.db.collection("replacementrequests");
      const rplDocs = await rplCol.find({ $or: driverConditions }).sort({ createdAt: -1 }).toArray();
      for (const rpl of rplDocs) {
        if (!allRides.some(r => r.requestId === rpl.requestId || r.requestId === rpl.rideId)) {
          allRides.push(rpl);
        }
      }
    } catch (_) {}

    // Deduplicate by requestId or _id
    const seenMap = new Map();
    const uniqueRides = [];
    for (const r of allRides) {
      const key = r.requestId || (r._id ? r._id.toString() : "");
      if (key && !seenMap.has(key)) {
        seenMap.set(key, true);
        uniqueRides.push(r);
      }
    }

    // Sort by createdAt / updatedAt descending
    uniqueRides.sort((a, b) => new Date(b.updatedAt || b.createdAt || 0) - new Date(a.updatedAt || a.createdAt || 0));

    // Summary calculations
    let totalEarnings = 0;
    let completedCount = 0;
    let cancelledCount = 0;

    const formattedList = uniqueRides.map(ride => {
      const st = (ride.status || "ASSIGNED").toUpperCase();
      const isCompleted = st === "COMPLETED" || st === "PAID" || st === "FINISHED";
      const isCancelled = st.includes("CANCEL") || st === "REJECTED";
      const rawFare = Number(ride.fare) || 0;

      if (isCompleted) {
        totalEarnings += rawFare;
        completedCount++;
      } else if (isCancelled) {
        cancelledCount++;
      }

      return {
        _id: ride.requestId || ride._id,
        id: ride.requestId || ride._id,
        mongoId: ride._id,
        requestId: ride.requestId || `REQ-${ride._id ? ride._id.toString().slice(-4) : 'RIDE'}`,
        passengerName: ride.passengerName || "Customer",
        passengerPhone: ride.passengerPhone || "",
        passengerEmail: ride.passengerEmail || "",
        pickupLocation: ride.pickupLocation || ride.pickup || "Pickup Location",
        dropoffLocation: ride.dropoffLocation || ride.drop || "Drop-off Location",
        startingFrom: ride.startingFrom || ride.date || "Today",
        timeToReach: ride.timeToReach || ride.scheduledTime || "08:30 AM",
        timeToLeave: ride.timeToLeave || "05:00 PM",
        scheduleType: ride.scheduleType || ride.rideType || "Monthly Pick & Drop",
        fare: rawFare,
        fareFormatted: `Rs. ${rawFare.toLocaleString()}`,
        status: isCompleted ? "COMPLETED" : (isCancelled ? "CANCELLED" : st),
        statusLabel: isCompleted ? "Completed" : (isCancelled ? "Cancelled" : (ride.status || "Assigned")),
        vehicleType: ride.vehicleType || "Sedan",
        acPreference: ride.acPreference || "AC",
        tripType: ride.tripType || "One Way",
        passengersCount: ride.passengersCount || 1,
        notes: ride.notes || "",
        paymentMethod: ride.paymentMethod || "Cash on Completion",
        createdAt: ride.createdAt || new Date(),
        updatedAt: ride.updatedAt || new Date()
      };
    });

    // Optional status filter
    let filteredList = formattedList;
    if (status && status.toLowerCase() !== "all") {
      if (status.toLowerCase() === "completed") {
        filteredList = formattedList.filter(r => r.status === "COMPLETED");
      } else if (status.toLowerCase() === "cancelled") {
        filteredList = formattedList.filter(r => r.status === "CANCELLED");
      } else {
        filteredList = formattedList.filter(r => r.status.toLowerCase() === status.toLowerCase());
      }
    }

    // Optional search query
    if (search && search.trim().length > 0) {
      const q = search.trim().toLowerCase();
      filteredList = filteredList.filter(r =>
        r.requestId.toLowerCase().includes(q) ||
        r.passengerName.toLowerCase().includes(q) ||
        r.pickupLocation.toLowerCase().includes(q) ||
        r.dropoffLocation.toLowerCase().includes(q)
      );
    }

    return res.status(200).json({
      success: true,
      summary: {
        totalEarnings,
        earningsFormatted: `Rs. ${totalEarnings.toLocaleString()}`,
        completedCount,
        cancelledCount,
        totalRides: formattedList.length
      },
      count: filteredList.length,
      rides: filteredList
    });
  } catch (err) {
    console.error("Driver Ride History Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch driver ride history",
      error: err.message
    });
  }
};

