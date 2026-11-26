const mongoose = require("mongoose");
const DriverHireRequest = require("../schema/DriverHireRequest");
const Driver = require("../schema/Driver");

// 1. Create a new Hire Driver Request (Customer Mobile App)
exports.createDriverHireRequest = async (req, res) => {
  try {
    const {
      customerName,
      customerPhone,
      customerEmail,
      cnic,
      bookingDate,
      pickupLocation,
      dropoffLocation,
      timeToReach,
      offTime,
      fare,
      notes,
      customerId
    } = req.body;

    if (!customerName || !customerPhone || !cnic || !bookingDate || !pickupLocation || !dropoffLocation || !timeToReach || !offTime) {
      return res.status(400).json({
        success: false,
        message: "Please provide all required fields (Name, Phone, CNIC, Date, Pickup, Dropoff, Reach Time, Off Time)"
      });
    }

    const newHireRequest = new DriverHireRequest({
      customerId: customerId || null,
      customerName: customerName.trim(),
      customerPhone: customerPhone.trim(),
      customerEmail: customerEmail ? customerEmail.trim().toLowerCase() : null,
      cnic: cnic.trim(),
      bookingDate: bookingDate.trim(),
      pickupLocation: pickupLocation.trim(),
      dropoffLocation: dropoffLocation.trim(),
      timeToReach: timeToReach.trim(),
      offTime: offTime.trim(),
      fare: Number(fare) || 3500,
      notes: notes || "",
      status: "Pending Dispatch"
    });

    const savedHire = await newHireRequest.save();

    // Emit real-time WebSocket event to Admin Portal
    try {
      const io = req.app.get("io");
      if (io) {
        const hirePayload = {
          _id: savedHire._id,
          id: savedHire._id,
          requestId: savedHire.requestId,
          customerName: savedHire.customerName,
          passengerName: savedHire.customerName,
          customerPhone: savedHire.customerPhone,
          passengerPhone: savedHire.customerPhone,
          cnic: savedHire.cnic,
          bookingDate: savedHire.bookingDate,
          date: savedHire.bookingDate,
          startingFrom: savedHire.bookingDate,
          pickupLocation: savedHire.pickupLocation,
          dropoffLocation: savedHire.dropoffLocation,
          pickup: savedHire.pickupLocation,
          drop: savedHire.dropoffLocation,
          timeToReach: savedHire.timeToReach,
          scheduledTime: savedHire.timeToReach,
          offTime: savedHire.offTime,
          fare: savedHire.fare,
          fareFormatted: `Rs. ${(savedHire.fare || 3500).toLocaleString()}`,
          status: savedHire.status,
          requestType: "Hire Driver",
          category: "Hire Driver",
          type: "Hire Driver",
          createdAt: savedHire.createdAt
        };

        io.emit("new-driver-hire", hirePayload);
        io.emit("driver-hire-update", { type: "NEW_DRIVER_HIRE", request: hirePayload, ride: hirePayload, data: hirePayload });
        io.emit("new-ride", { ...hirePayload, category: "Hire Driver" });
        io.emit("ride-update", { type: "NEW_DRIVER_HIRE", ride: hirePayload });
        console.log("📡 Real-time event emitted: new-driver-hire", savedHire.requestId);
      }
    } catch (socketErr) {
      console.warn("Socket emit notice:", socketErr.message);
    }

    return res.status(201).json({
      success: true,
      message: "Driver hiring request submitted successfully. Awaiting dispatch.",
      request: savedHire,
      requestId: savedHire.requestId
    });
  } catch (err) {
    console.error("Create Driver Hire Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to submit driver hiring request",
      error: err.message
    });
  }
};

// 2. Get All Hire Driver Requests (Admin Console & Driver App)
exports.getAllDriverHireRequests = async (req, res) => {
  try {
    const { status, search, driverId, driverName } = req.query;
    let query = {};

    if (status) {
      const s = status.toLowerCase();
      query.status = s === "pending"
        ? "Pending Dispatch"
        : (s === "assigned"
            ? { $in: ["ASSIGNED", "Assigned", "assigned"] }
            : status);
    }

    if (driverId || driverName) {
      const driverConditions = [];
      if (driverId) {
        driverConditions.push({ assignedDriverId: driverId });
        driverConditions.push({ driverId: driverId });
        try {
          if (mongoose.Types.ObjectId.isValid(driverId)) {
            const objId = new mongoose.Types.ObjectId(driverId);
            driverConditions.push({ assignedDriverId: objId });
            driverConditions.push({ driverId: objId });
          }
        } catch (_) {}
      }
      if (driverName && driverName.trim().length > 0) {
        driverConditions.push({ assignedDriverName: new RegExp('^' + driverName.trim() + '$', 'i') });
        driverConditions.push({ assignedDriverName: new RegExp(driverName.trim(), 'i') });
      }
      if (driverConditions.length > 0) {
        if (query.$or) {
          query.$and = [{ $or: query.$or }, { $or: driverConditions }];
          delete query.$or;
        } else {
          query.$or = driverConditions;
        }
      }
    }

    if (search) {
      const searchConds = [
        { requestId: { $regex: search, $options: "i" } },
        { customerName: { $regex: search, $options: "i" } },
        { customerPhone: { $regex: search, $options: "i" } },
        { cnic: { $regex: search, $options: "i" } },
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

    const requests = await DriverHireRequest.find(query).sort({ createdAt: -1 }).lean();

    const formattedRequests = requests.map((item) => ({
      _id: item._id,
      id: item.requestId || item._id,
      mongoId: item._id,
      requestId: item.requestId,
      customerName: item.customerName,
      passengerName: item.customerName,
      customerPhone: item.customerPhone,
      passengerPhone: item.customerPhone,
      customerEmail: item.customerEmail,
      cnic: item.cnic,
      bookingDate: item.bookingDate,
      date: item.bookingDate,
      startingFrom: item.bookingDate,
      pickupLocation: item.pickupLocation,
      dropoffLocation: item.dropoffLocation,
      pickup: item.pickupLocation,
      drop: item.dropoffLocation,
      timeToReach: item.timeToReach,
      scheduledTime: item.timeToReach,
      offTime: item.offTime,
      fare: item.fare || 3500,
      fareFormatted: `Rs. ${(item.fare || 3500).toLocaleString()}`,
      status: item.status,
      assignedDriver: item.assignedDriverName || item.assignedDriver || null,
      assignedDriverName: item.assignedDriverName || item.assignedDriver || null,
      assignedDriverId: item.assignedDriverId ? String(item.assignedDriverId) : (item.driverId || item.driver || null),
      driverId: item.driverId || (item.assignedDriverId ? String(item.assignedDriverId) : item.driver || null),
      requestType: "Hire Driver",
      category: "Hire Driver",
      type: "Hire Driver",
      createdAt: item.createdAt
    }));

    return res.status(200).json({
      success: true,
      count: requests.length,
      data: formattedRequests,
      requests: formattedRequests,
      rides: formattedRequests
    });
  } catch (err) {
    console.error("Get Driver Hire Requests Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch driver hire requests",
      error: err.message
    });
  }
};

// 3. Dispatch / Assign Driver to Hire Request (Admin Action)
exports.dispatchDriverHire = async (req, res) => {
  try {
    const { driverId, driverName } = req.body;
    const reqId = req.params.id;

    let existing = null;
    if (mongoose.Types.ObjectId.isValid(reqId)) {
      existing = await DriverHireRequest.findById(reqId).catch(() => null);
    }
    if (!existing) {
      existing = await DriverHireRequest.findOne({ requestId: reqId }).catch(() => null);
    }
    if (!existing) {
      return res.status(404).json({
        success: false,
        message: "Driver hire request not found"
      });
    }

    let assignedName = driverName;
    if (driverId && !assignedName) {
      const driver = mongoose.Types.ObjectId.isValid(driverId)
        ? await Driver.findById(driverId).catch(() => null)
        : await Driver.findOne({ driverReferenceId: driverId }).catch(() => null);
      if (driver) {
        assignedName = driver.Name || `${driver.firstName || ""} ${driver.lastName || ""}`.trim();
      }
    }

    const updated = await DriverHireRequest.findByIdAndUpdate(
      existing._id,
      {
        status: "ASSIGNED",
        assignedDriverId: driverId || null,
        assignedDriverName: assignedName || "Assigned Driver"
      },
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({
        success: false,
        message: "Driver hire request not found"
      });
    }

    try {
      const io = req.app.get("io");
      if (io) {
        const hirePayload = {
          _id: updated._id,
          id: updated.requestId || updated._id,
          mongoId: updated._id,
          requestId: updated.requestId,
          customerName: updated.customerName,
          passengerName: updated.customerName,
          customerPhone: updated.customerPhone,
          passengerPhone: updated.customerPhone,
          cnic: updated.cnic,
          bookingDate: updated.bookingDate,
          date: updated.bookingDate,
          startingFrom: updated.bookingDate,
          pickupLocation: updated.pickupLocation,
          dropoffLocation: updated.dropoffLocation,
          pickup: updated.pickupLocation,
          drop: updated.dropoffLocation,
          timeToReach: updated.timeToReach,
          scheduledTime: updated.timeToReach,
          offTime: updated.offTime,
          fare: updated.fare || 3500,
          fareFormatted: `Rs. ${(updated.fare || 3500).toLocaleString()}`,
          status: updated.status,
          assignedDriverId: updated.assignedDriverId ? String(updated.assignedDriverId) : null,
          assignedDriverName: updated.assignedDriverName,
          driverId: updated.assignedDriverId ? String(updated.assignedDriverId) : null,
          driverName: updated.assignedDriverName,
          requestType: "Hire Driver",
          category: "Hire Driver",
          type: "Hire Driver",
          createdAt: updated.createdAt
        };

        io.emit("driver-hire-dispatched", hirePayload);
        io.emit("driver-hire-update", { type: "DRIVER_HIRE_DISPATCHED", request: hirePayload, ride: hirePayload, data: hirePayload });
        io.emit("new-ride", hirePayload);
        io.emit("ride-update", { type: "DRIVER_HIRE_DISPATCHED", ride: hirePayload });
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Hire Driver request ${updated.requestId} successfully dispatched`,
      request: updated
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: "Failed to dispatch driver hire request",
      error: err.message
    });
  }
};

// 4. Update Driver Hire Details / Fare (Admin & Driver Action)
exports.updateDriverHire = async (req, res) => {
  try {
    const reqId = req.params.id;
    const { fare, status, rawStatus, action, notes, driverId } = req.body;

    let existing = null;
    if (mongoose.Types.ObjectId.isValid(reqId)) {
      existing = await DriverHireRequest.findById(reqId).catch(() => null);
    }
    if (!existing) {
      existing = await DriverHireRequest.findOne({ requestId: reqId }).catch(() => null);
    }
    if (!existing) {
      return res.status(404).json({
        success: false,
        message: "Driver hire request not found"
      });
    }

    let updateFields = {};
    const effectiveStatus = action || status || rawStatus;
    if (effectiveStatus) updateFields.status = effectiveStatus;
    if (driverId) updateFields.driverId = driverId;

    const isFareUpdated = (fare !== undefined && fare !== null && !isNaN(Number(fare)) && Number(fare) >= 0 && (Number(fare) !== Number(existing.fare || 0) || effectiveStatus === "PRICE_UPDATED" || req.body.fareStatus === "PRICE_UPDATED"));
    if (isFareUpdated) {
      updateFields.fare = Number(fare);
      if (!effectiveStatus || effectiveStatus === "PRICE_UPDATED") {
        updateFields.status = "PRICE_UPDATED";
      }
      updateFields.fareResponseStatus = "Pending";
      updateFields.fareStatus = "PRICE_UPDATED";
    }
    if (notes !== undefined) updateFields.notes = notes;

    const updated = await DriverHireRequest.findByIdAndUpdate(
      existing._id,
      updateFields,
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({
        success: false,
        message: "Driver hire request not found"
      });
    }

    try {
      const io = req.app.get("io");
      if (io) {
        io.emit("driver-hire-updated", updated);
        io.emit("driver-hire-update", { type: "DRIVER_HIRE_UPDATED", request: updated, ride: updated, data: updated });
        io.emit("ride-update", { type: "DRIVER_HIRE_UPDATED", ride: updated });

        if (isFareUpdated && updated.status !== "COMPLETED") {
          const farePayload = {
            id: updated.requestId,
            requestId: updated.requestId,
            customerId: updated.customerId,
            passengerPhone: updated.passengerPhone || updated.customerPhone,
            type: "PRICE_UPDATED",
            status: "PRICE_UPDATED",
            fareUpdated: true,
            fareResponseStatus: "Pending",
            fareFormatted: `Rs. ${Number(updated.fare || 0).toLocaleString()}`,
            fare: updated.fare,
            title: "💰 Ride Price Updated!",
            subtitle: `Admin has set your driver hire fare to Rs. ${Number(updated.fare || 0).toLocaleString()}.`
          };
          const custId = updated.customerId ? String(updated.customerId) : "";
          const custPhone = (updated.passengerPhone || updated.customerPhone) ? String(updated.passengerPhone || updated.customerPhone) : "";
          const rId = String(updated.requestId);

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
          console.log(`📡 Real-time fare update emitted to customer for driver hire ${rId}`);
        }
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Driver hire request ${updated.requestId} updated successfully`,
      request: updated,
      ride: updated
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: "Failed to update driver hire request",
      error: err.message
    });
  }
};
