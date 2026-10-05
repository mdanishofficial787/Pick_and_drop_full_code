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
          customerPhone: savedHire.customerPhone,
          cnic: savedHire.cnic,
          bookingDate: savedHire.bookingDate,
          pickupLocation: savedHire.pickupLocation,
          dropoffLocation: savedHire.dropoffLocation,
          timeToReach: savedHire.timeToReach,
          offTime: savedHire.offTime,
          fare: savedHire.fare,
          fareFormatted: `Rs. ${(savedHire.fare || 3500).toLocaleString()}`,
          status: savedHire.status,
          createdAt: savedHire.createdAt
        };

        io.emit("new-driver-hire", hirePayload);
        io.emit("driver-hire-update", { type: "NEW_DRIVER_HIRE", request: hirePayload });
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

// 2. Get All Hire Driver Requests (Admin Console)
exports.getAllDriverHireRequests = async (req, res) => {
  try {
    const { status, search } = req.query;
    let query = {};

    if (status) {
      query.status = status.toLowerCase() === "pending" ? "Pending Dispatch" : status;
    }

    if (search) {
      query.$or = [
        { requestId: { $regex: search, $options: "i" } },
        { customerName: { $regex: search, $options: "i" } },
        { customerPhone: { $regex: search, $options: "i" } },
        { cnic: { $regex: search, $options: "i" } },
        { pickupLocation: { $regex: search, $options: "i" } },
        { dropoffLocation: { $regex: search, $options: "i" } }
      ];
    }

    const requests = await DriverHireRequest.find(query).sort({ createdAt: -1 });

    const formattedRequests = requests.map((item) => ({
      _id: item._id,
      id: item.requestId || item._id,
      mongoId: item._id,
      requestId: item.requestId,
      customerName: item.customerName,
      customerPhone: item.customerPhone,
      customerEmail: item.customerEmail,
      cnic: item.cnic,
      bookingDate: item.bookingDate,
      pickupLocation: item.pickupLocation,
      dropoffLocation: item.dropoffLocation,
      timeToReach: item.timeToReach,
      offTime: item.offTime,
      fare: item.fare || 3500,
      fareFormatted: `Rs. ${(item.fare || 3500).toLocaleString()}`,
      status: item.status,
      assignedDriverName: item.assignedDriverName || null,
      createdAt: item.createdAt
    }));

    return res.status(200).json({
      success: true,
      count: requests.length,
      data: formattedRequests,
      requests: formattedRequests
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

    let assignedName = driverName;
    if (driverId && !assignedName) {
      const driver = await Driver.findById(driverId);
      if (driver) {
        assignedName = `${driver.firstName} ${driver.lastName}`.trim();
      }
    }

    const updated = await DriverHireRequest.findByIdAndUpdate(
      reqId,
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
        io.emit("driver-hire-dispatched", updated);
        io.emit("driver-hire-update", { type: "DRIVER_HIRE_DISPATCHED", request: updated });
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

// 4. Update Driver Hire Details / Fare (Admin Action)
exports.updateDriverHire = async (req, res) => {
  try {
    const reqId = req.params.id;
    const { fare, status, notes } = req.body;

    let updateFields = {};
    if (fare !== undefined) updateFields.fare = Number(fare);
    if (status) updateFields.status = status;
    if (notes !== undefined) updateFields.notes = notes;

    const updated = await DriverHireRequest.findByIdAndUpdate(
      reqId,
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
      }
    } catch (socketErr) {}

    return res.status(200).json({
      success: true,
      message: `Driver hire request ${updated.requestId} updated successfully`,
      request: updated
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: "Failed to update driver hire request",
      error: err.message
    });
  }
};
