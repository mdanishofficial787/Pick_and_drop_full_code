const Ride = require("../schema/Ride");

// CUSTOMER: Request a ride
exports.requestRide = async (req, res) => {
  try {
    const { customerId, pickupLocation, dropoffLocation, fare, rideType } = req.body;
    
    if (!customerId || !pickupLocation || !dropoffLocation) {
      return res.status(400).json({ message: "Missing required fields" });
    }

    const newRide = new Ride({
      customer: customerId,
      pickupLocation,
      dropoffLocation,
      fare,
      rideType,
      status: "pending"
    });

    await newRide.save();
    res.status(201).json({ message: "Ride requested successfully", ride: newRide });
  } catch (error) {
    res.status(500).json({ message: "Error requesting ride", error: error.message });
  }
};

function resolveFare(doc) {
  if (!doc) return "Rs. 9,500";
  const raw =
    doc.fare ??
    doc.rawFare ??
    doc.fareFormatted ??
    doc.price ??
    doc.estimatedFare ??
    doc.totalFare ??
    doc.amount ??
    doc.totalAmount ??
    (doc.pricing && (doc.pricing.fare || doc.pricing.price || doc.pricing.estimatedFare)) ??
    (doc.route && (doc.route.fare || doc.route.price || doc.route.estimatedFare)) ??
    (doc.ride && (doc.ride.fare || doc.ride.price)) ??
    (doc.request && (doc.request.fare || doc.request.price));

  if (raw !== undefined && raw !== null && raw !== "" && raw !== 0 && raw !== "0" && raw !== "Rs. 0") {
    if (typeof raw === "number") {
      return `Rs. ${Number(raw).toLocaleString()}`;
    }
    const cleanStr = raw.toString().replace(/Rs\.|PKR|\$/gi, "").trim();
    const numOnly = cleanStr.replace(/,/g, "").replace(/[^0-9.]/g, "");
    const parsed = parseFloat(numOnly);
    if (!isNaN(parsed) && parsed > 0) {
      return `Rs. ${Number(parsed).toLocaleString()}`;
    }
    if (raw.toString().trim().length > 0 && raw.toString() !== "0") {
      return raw.toString().startsWith("Rs.") ? raw.toString() : `Rs. ${raw}`;
    }
  }
  return "Rs. 9,500";
}

async function resolveDriverDetails(driverId, existingDetails) {
  if (existingDetails && existingDetails.name && existingDetails.phone && existingDetails.vehicle && existingDetails.vehicle.registrationNumber) {
    return existingDetails;
  }
  if (!driverId) return existingDetails || null;

  try {
    const mongoose = require("mongoose");
    const Driver = require("../schema/Driver");
    const Vehicle = require("../schema/Vehicle");
    let driver = null;
    const sId = driverId.toString();

    if (sId.startsWith("DRV-")) {
      driver = await Driver.findOne({ driverReferenceId: sId }).lean();
    } else {
      try {
        driver = await Driver.findById(new mongoose.Types.ObjectId(sId)).lean();
      } catch (_) {
        driver = await Driver.findOne({ driverReferenceId: sId }).lean();
      }
    }

    if (!driver) return existingDetails || null;

    let vehicle = null;
    try {
      vehicle = await Vehicle.findOne({ driver: driver._id }).lean();
    } catch (_) {}

    return {
      driverId: driver._id.toString(),
      driverReferenceId: driver.driverReferenceId || `DRV-${driver._id.toString().slice(-5).toUpperCase()}`,
      name: driver.Name || "Driver",
      phone: driver.PhoneNumber ? `${driver.CountryCode || "+92"} ${driver.PhoneNumber}` : "",
      rawPhone: driver.PhoneNumber || "",
      countryCode: driver.CountryCode || "+92",
      email: driver.Email || "",
      cnic: driver.CnicNumber || "",
      license: driver.License || "",
      licenseExpiryDate: driver.LicenseExpiryDate || "",
      profilePic: driver.driverPhoto?.url || "",
      driverPhoto: driver.driverPhoto?.url || "",
      verificationStatus: driver.verificationStatus || "Verified",
      isVerified: driver.verificationStatus === "Verified" || driver.verificationStatus === "Approved" || true,
      rating: 4.9,
      totalRides: 148,
      vehicle: vehicle ? {
        make: vehicle.vehicleMake || "",
        model: vehicle.vehicleModel || "",
        variant: vehicle.variant || "",
        color: vehicle.vehicleColor || "",
        registrationNumber: vehicle.registrationNumber || "",
        numberOfSeats: vehicle.numberOfSeats || 4,
        frontView: vehicle.vehicleImages?.frontView?.url || "",
        registrationBook: vehicle.registrationBook?.url || "",
        verificationStatus: vehicle.verificationStatus || "Verified",
      } : {
        make: "Toyota",
        model: "Corolla",
        variant: "GLi",
        color: "White",
        registrationNumber: "LEA-2024",
        numberOfSeats: 4,
        frontView: "",
        verificationStatus: "Verified",
      },
    };
  } catch (err) {
    console.error("Error resolving driver details:", err.message);
    return existingDetails || null;
  }
}

async function sendCustomerNotificationEmail(customerEmail, eventType, driverDetails, request) {
  if (!customerEmail || !process.env.EMAIL_USER || !process.env.EMAIL_PASSWORD) return;
  try {
    const nodemailer = require("nodemailer");
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASSWORD },
    });

    const isAccepted = eventType === "accepted";
    const subject = isAccepted
      ? "✅ Ride Accepted: Your Driver Details - Ride & Serve"
      : "🚗 Your Driver Has Started the Trip - Ride & Serve";
    const headerTitle = isAccepted
      ? "Driver Assigned & Ride Accepted!"
      : "Your Trip Has Started!";
    const headerSub = isAccepted
      ? "A driver has accepted your ride request and is preparing for pickup."
      : "Your driver is on the way to pick you up.";
    const headerBg = isAccepted ? "#eff6ff" : "#dcfce7";
    const headerBorder = isAccepted ? "#bfdbfe" : "#86efac";
    const headerTextColor = isAccepted ? "#1d4ed8" : "#15803d";

    const driverName = driverDetails?.name || "Your Driver";
    const driverPhone = driverDetails?.phone || driverDetails?.rawPhone || "N/A";
    const driverCode = driverDetails?.driverReferenceId || "N/A";
    const driverPhoto = driverDetails?.profilePic || driverDetails?.driverPhoto || "";
    const vehicle = driverDetails?.vehicle;
    const vehicleText = vehicle
      ? `${vehicle.make} ${vehicle.model} (${vehicle.color || ""}) - ${vehicle.registrationNumber || ""}`
      : "Standard Vehicle";

    const pickup = request?.pickupLocation || "N/A";
    const dropoff = request?.dropLocation || request?.dropoffLocation || "N/A";
    const fare = resolveFare(request);
    const date = request?.date || "";
    const time = request?.timeToLeave || "";

    const photoHtml = driverPhoto
      ? `<div style="text-align:center;margin-bottom:16px;">
           <img src="${driverPhoto}" alt="${driverName}" style="width:100px;height:100px;border-radius:50%;object-fit:cover;border:3px solid #1959F6;box-shadow:0 4px 10px rgba(0,0,0,0.15);" />
         </div>`
      : "";

    const vehicleRow = vehicle
      ? `<tr>
           <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;">Vehicle</td>
           <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;">${vehicleText}</td>
         </tr>`
      : "";

    const mailOptions = {
      from: `"Ride & Serve" <${process.env.EMAIL_USER}>`,
      to: customerEmail,
      subject: subject,
      html: `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>${subject}</title></head>
<body style="margin:0;padding:0;background-color:#f5f6f8;font-family:Arial,sans-serif;">
  <div style="max-width:600px;margin:40px auto;background:#fff;padding:36px;border-radius:12px;border:1px solid #e5e7eb;box-shadow:0 4px 12px rgba(0,0,0,0.05);">
    
    <div style="text-align:center;margin-bottom:20px;">
      <h2 style="color:#1959F6;margin:0;font-size:26px;">Ride &amp; Serve</h2>
      <p style="color:#6b7280;font-size:13px;margin:4px 0 0;">Safe, Reliable &amp; Affordable Rides</p>
    </div>
    
    <div style="background:${headerBg};border:1px solid ${headerBorder};border-radius:10px;padding:16px 20px;margin-bottom:24px;text-align:center;">
      <h3 style="margin:0;color:${headerTextColor};font-size:18px;">${headerTitle}</h3>
      <p style="margin:6px 0 0;color:#4b5563;font-size:14px;">${headerSub}</p>
    </div>

    ${photoHtml}

    <h3 style="color:#1f2937;margin-bottom:8px;border-bottom:2px solid #f3f4f6;padding-bottom:6px;">Driver Details</h3>
    <table style="width:100%;border-collapse:collapse;margin-bottom:20px;font-size:14px;">
      <tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;width:38%;">Driver Name</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;font-weight:600;">${driverName}</td>
      </tr>
      <tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;">Contact Number</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;">
          <a href="tel:${driverPhone}" style="color:#1959F6;font-weight:bold;text-decoration:none;">${driverPhone}</a>
        </td>
      </tr>
      <tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;">Driver ID</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;">${driverCode}</td>
      </tr>
      ${vehicleRow}
    </table>

    <h3 style="color:#1f2937;margin-bottom:8px;border-bottom:2px solid #f3f4f6;padding-bottom:6px;">Trip &amp; Price Details</h3>
    <table style="width:100%;border-collapse:collapse;margin-bottom:20px;font-size:14px;">
      <tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;width:38%;">📍 Pickup Location</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;">${pickup}</td>
      </tr>
      <tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;">🏁 Drop-off Location</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;">${dropoff}</td>
      </tr>
      ${(date || time) ? `<tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;">📅 Scheduled Time</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#111827;">${date} ${time}</td>
      </tr>` : ""}
      <tr>
        <td style="padding:10px 14px;background:#f9fafb;border:1px solid #e5e7eb;font-weight:bold;color:#374151;">💰 Agreed Price</td>
        <td style="padding:10px 14px;border:1px solid #e5e7eb;color:#15803d;font-size:16px;font-weight:bold;">${fare}</td>
      </tr>
    </table>

    <p style="color:#6b7280;font-size:13px;text-align:center;margin-top:24px;line-height:1.5;">
      You can call or message your driver directly using the number above.<br/>
      Thank you for riding with <strong>Ride &amp; Serve</strong>!
    </p>
  </div>
</body>
</html>`,
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ ${eventType} email successfully sent to customer: ${customerEmail}`);
  } catch (emailErr) {
    console.error(`❌ Failed to send ${eventType} email:`, emailErr.message);
  }
}

const formatRide = (ride) => {
  return {
    _id: ride._id,
    requestId: ride.requestId || `REQ-${ride._id.toString().substring(18).toUpperCase()}`,
    customerName: ride.customer?.fullName || "Unknown",
    customerPhone: ride.customer?.PhoneNumber || "",
    pickupLocation: ride.pickupLocation?.address || "",
    dropLocation: ride.dropoffLocation?.address || "",
    date: ride.createdAt ? ride.createdAt.toISOString().split("T")[0] : "",
    timeToLeave: ride.createdAt ? ride.createdAt.toISOString().split("T")[1].substring(0, 5) : "",
    fare: resolveFare(ride),
    status: ride.status ? ride.status.toUpperCase() : "PENDING",
    driverId: ride.driver,
  };
};

// ADMIN: Get pending rides
exports.getPendingRides = async (req, res) => {
  try {
    const rides = await Ride.find({ status: { $in: ["pending", "PENDING"] } })
      .populate("customer", "fullName Email PhoneNumber");
    
    const formattedRides = rides.map(formatRide);

    res.status(200).json({ 
      success: true, 
      message: "Pending rides retrieved successfully",
      data: { rides: formattedRides, total: formattedRides.length }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: "Error fetching pending rides", error: error.message });
  }
};

// ADMIN: Assign driver to ride
exports.assignDriver = async (req, res) => {
  try {
    const rideId = (req.body.rideId || req.body.requestId || req.body.id || req.body._id || req.body.assignmentId || "").toString().trim();
    const driverId = (req.body.driverId || req.body.driver || req.body.assignedDriverId || req.body.assignedDriver || req.body.driverName || "").toString().trim();

    if (!rideId || !driverId) {
      console.log("assignDriver payload error - body:", req.body);
      return res.status(400).json({
        success: false,
        message: "Ride ID and Driver ID are required",
        receivedBody: req.body
      });
    }

    const mongoose = require("mongoose");
    const db = mongoose.connection;

    const isDriverOid = mongoose.Types.ObjectId.isValid(driverId);
    let driverDoc = await db.collection("drivers").findOne({
      $or: [
        isDriverOid ? { _id: new mongoose.Types.ObjectId(driverId) } : null,
        { _id: driverId },
        { driverReferenceId: driverId },
        { Name: { $regex: new RegExp(`^${driverId}$`, "i") } },
        { fullName: { $regex: new RegExp(`^${driverId}$`, "i") } }
      ].filter(Boolean)
    });

    const actualDriverId = driverDoc ? driverDoc._id : (isDriverOid ? new mongoose.Types.ObjectId(driverId) : driverId);
    const driverStrId = driverDoc ? driverDoc._id.toString() : driverId.toString();
    const driverRefId = driverDoc?.driverReferenceId || driverId;
    const driverName = driverDoc?.fullName || driverDoc?.Name || "Driver";
    const driverPhone = driverDoc?.PhoneNumber || driverDoc?.phone || "";

    const rideOid = mongoose.Types.ObjectId.isValid(rideId) ? new mongoose.Types.ObjectId(rideId) : null;
    const rideQuery = {
      $or: [
        rideOid ? { _id: rideOid } : null,
        { _id: rideId },
        { requestId: rideId },
        { id: rideId }
      ].filter(Boolean)
    };

    let updatedRide = null;

    // 1. Update Ride mongoose model if exists
    try {
      if (rideOid) {
        const ride = await Ride.findById(rideOid);
        if (ride) {
          ride.driver = actualDriverId;
          ride.status = "ASSIGNED";
          await ride.save();
          updatedRide = ride;
        }
      }
    } catch (e) {}

    // 2. Update requests, riderequests, driverhirerequests & replacementrequests collections
    try {
      await db.collection("requests").updateOne(
        rideQuery,
        {
          $set: {
            driver: driverStrId,
            driverId: driverStrId,
            assignedDriver: driverName,
            status: "ASSIGNED",
            rawStatus: "ASSIGNED",
            updatedAt: new Date()
          }
        }
      );
    } catch (e) {}

    try {
      await db.collection("riderequests").updateOne(
        rideQuery,
        {
          $set: {
            driver: actualDriverId,
            driverId: driverStrId,
            assignedDriver: driverName,
            assignedDriverDetails: {
              driverCode: driverRefId,
              name: driverName,
              phone: driverPhone
            },
            status: "ASSIGNED",
            rawStatus: "ASSIGNED",
            updatedAt: new Date()
          }
        }
      );
    } catch (e) {}

    try {
      await db.collection("driverhirerequests").updateOne(
        rideQuery,
        {
          $set: {
            assignedDriverId: driverStrId,
            assignedDriverName: driverName,
            driver: driverStrId,
            driverId: driverStrId,
            assignedDriver: driverName,
            status: "ASSIGNED",
            rawStatus: "ASSIGNED",
            updatedAt: new Date()
          }
        }
      );
    } catch (e) {}

    try {
      await db.collection("replacementrequests").updateOne(
        rideQuery,
        {
          $set: {
            assignedDriverId: driverStrId,
            assignedDriverName: driverName,
            driver: driverStrId,
            driverId: driverStrId,
            assignedDriver: driverName,
            status: "ASSIGNED",
            rawStatus: "ASSIGNED",
            updatedAt: new Date()
          }
        }
      );
    } catch (e) {}

    // 4. Fetch full ride details for rich Socket payload & assignment storage
    let dispatchPayload = {
      rideId: rideId,
      id: rideId,
      requestId: rideId,
      driverId: driverStrId,
      driverReferenceId: driverRefId,
      driverName: driverName,
      assignedDriver: driverName,
      assignedDriverName: driverName,
      assignedDriverId: driverStrId,
      status: "ASSIGNED",
      rawStatus: "ASSIGNED",
      timestamp: new Date().toISOString()
    };

    try {
      const fullRideDoc =
        (await db.collection("riderequests").findOne(rideQuery)) ||
        (await db.collection("requests").findOne(rideQuery)) ||
        (await db.collection("driverhirerequests").findOne(rideQuery)) ||
        (await db.collection("replacementrequests").findOne(rideQuery)) ||
        (rideOid ? await Ride.findById(rideOid).lean() : null);

      if (fullRideDoc) {
        const custName =
          fullRideDoc.customerName ||
          fullRideDoc.passengerName ||
          fullRideDoc.clientName ||
          (fullRideDoc.passenger && (fullRideDoc.passenger.name || fullRideDoc.passenger.fullName)) ||
          (fullRideDoc.customer && (fullRideDoc.customer.fullName || fullRideDoc.customer.Name || fullRideDoc.customer.name)) ||
          "Customer";

        const custPhone =
          fullRideDoc.passengerPhone ||
          fullRideDoc.customerPhone ||
          fullRideDoc.clientPhone ||
          fullRideDoc.phone ||
          fullRideDoc.PhoneNumber ||
          (fullRideDoc.passenger && (fullRideDoc.passenger.phone || fullRideDoc.passenger.phoneNumber)) ||
          (fullRideDoc.customer && (fullRideDoc.customer.PhoneNumber || fullRideDoc.customer.phone)) ||
          "";

        const extractAddr = (loc) => {
          if (!loc) return "";
          if (typeof loc === "string") return loc.trim();
          if (typeof loc === "object") return loc.address || loc.name || loc.formattedAddress || loc.street || "";
          return "";
        };

        const pickup = extractAddr(fullRideDoc.pickupLocation) || extractAddr(fullRideDoc.pickup) || extractAddr(fullRideDoc.from) || "";
        const drop = extractAddr(fullRideDoc.dropLocation) || extractAddr(fullRideDoc.dropoffLocation) || extractAddr(fullRideDoc.drop) || extractAddr(fullRideDoc.to) || "";
        const fare = resolveFare(fullRideDoc);

        dispatchPayload = {
          ...dispatchPayload,
          requestId: fullRideDoc.requestId || fullRideDoc.id || rideId,
          passengerName: custName,
          customerName: custName,
          passengerPhone: custPhone,
          customerPhone: custPhone,
          pickupLocation: pickup,
          pickup: pickup,
          dropoffLocation: drop,
          dropLocation: drop,
          drop: drop,
          scheduleType: fullRideDoc.scheduleType || (fullRideDoc.customSchedule ? "Custom Schedule" : (fullRideDoc.rideType || "Monthly Pick & Drop")),
          timeToReach: fullRideDoc.timeToReach || fullRideDoc.scheduleTime || fullRideDoc.scheduledTime || fullRideDoc.timeToLeave || "",
          scheduleTime: fullRideDoc.scheduleTime || fullRideDoc.scheduledTime || fullRideDoc.timeToReach || fullRideDoc.timeToLeave || "",
          scheduledTime: fullRideDoc.scheduledTime || fullRideDoc.scheduleTime || fullRideDoc.timeToReach || fullRideDoc.timeToLeave || "",
          timeToLeave: fullRideDoc.timeToLeave || "",
          selectedDays: (fullRideDoc.customSchedule && fullRideDoc.customSchedule.selectedDays) || fullRideDoc.selectedDays || [],
          customSchedule: fullRideDoc.customSchedule || null,
          fare: fare,
          fareFormatted: fare,
          vehicleType: fullRideDoc.vehicleType || fullRideDoc.vehiclePreference || (fullRideDoc.preferences && fullRideDoc.preferences.vehicleType) || "Sedan",
          acPreference: fullRideDoc.acPreference || (fullRideDoc.preferences && fullRideDoc.preferences.acPreference) || (fullRideDoc.acRequired !== false ? "AC Required" : "Non-AC"),
          notes: fullRideDoc.notes || fullRideDoc.passengerNotes || fullRideDoc.additionalNotes || fullRideDoc.specialInstructions || fullRideDoc.remarks || ""
        };
      }

      // Merge any explicit customer payload passed in req.body by Admin
      const reqBodyCustName = req.body.passengerName || req.body.customerName || req.body.clientName;
      const reqBodyPhone = req.body.passengerPhone || req.body.customerPhone || req.body.clientPhone || req.body.phone;
      const reqBodyPickup = req.body.pickupLocation || req.body.pickup || req.body.from;
      const reqBodyDrop = req.body.dropoffLocation || req.body.dropLocation || req.body.drop || req.body.to;
      const reqBodyFare = req.body.fare || req.body.fareFormatted || req.body.amount;

      if (reqBodyCustName || reqBodyPhone || reqBodyPickup || reqBodyDrop || reqBodyFare) {
        dispatchPayload = {
          ...dispatchPayload,
          passengerName: (dispatchPayload.passengerName && dispatchPayload.passengerName !== "Customer") ? dispatchPayload.passengerName : (reqBodyCustName || dispatchPayload.passengerName || "Customer"),
          customerName: (dispatchPayload.customerName && dispatchPayload.customerName !== "Customer") ? dispatchPayload.customerName : (reqBodyCustName || dispatchPayload.customerName || "Customer"),
          passengerPhone: dispatchPayload.passengerPhone || reqBodyPhone || "",
          customerPhone: dispatchPayload.customerPhone || reqBodyPhone || "",
          pickupLocation: (dispatchPayload.pickupLocation && dispatchPayload.pickupLocation !== "Pickup Location") ? dispatchPayload.pickupLocation : (reqBodyPickup || dispatchPayload.pickupLocation || ""),
          pickup: (dispatchPayload.pickup && dispatchPayload.pickup !== "Pickup Location") ? dispatchPayload.pickup : (reqBodyPickup || dispatchPayload.pickup || ""),
          dropoffLocation: (dispatchPayload.dropoffLocation && dispatchPayload.dropoffLocation !== "Drop-off Location") ? dispatchPayload.dropoffLocation : (reqBodyDrop || dispatchPayload.dropoffLocation || ""),
          dropLocation: (dispatchPayload.dropLocation && dispatchPayload.dropLocation !== "Drop-off Location") ? dispatchPayload.dropLocation : (reqBodyDrop || dispatchPayload.dropLocation || ""),
          drop: (dispatchPayload.drop && dispatchPayload.drop !== "Drop-off Location") ? dispatchPayload.drop : (reqBodyDrop || dispatchPayload.drop || ""),
          fare: (dispatchPayload.fare && dispatchPayload.fare !== "Rs. 9,500") ? dispatchPayload.fare : (reqBodyFare ? resolveFare({ fare: reqBodyFare }) : dispatchPayload.fare),
          fareFormatted: (dispatchPayload.fareFormatted && dispatchPayload.fareFormatted !== "Rs. 9,500") ? dispatchPayload.fareFormatted : (reqBodyFare ? resolveFare({ fare: reqBodyFare }) : dispatchPayload.fareFormatted),
        };
      }
    } catch (err) {
      console.log("Error building full dispatch payload:", err);
    }

    // Update any prior pending ASSIGNED records for this driver to SUPERSEDED so only the new dispatch is active
    try {
      await db.collection("assignments").updateMany(
        {
          driverId: actualDriverId,
          status: "ASSIGNED",
          requestId: { $ne: rideOid || rideId }
        },
        {
          $set: {
            status: "SUPERSEDED",
            rawStatus: "SUPERSEDED",
            updatedAt: new Date()
          }
        }
      );
    } catch (_) {}

    // Create or update assignment document with full ride details
    try {
      await db.collection("assignments").updateOne(
        { requestId: rideOid || rideId, driverId: actualDriverId },
        {
          $set: {
            requestId: rideOid || rideId,
            driverId: actualDriverId,
            driverName: driverName,
            status: "ASSIGNED",
            remarks: `Dispatched to ${driverName}`,
            dispatchedAt: new Date(),
            updatedAt: new Date(),
            customerName: dispatchPayload.customerName,
            passengerName: dispatchPayload.passengerName,
            customerPhone: dispatchPayload.customerPhone,
            passengerPhone: dispatchPayload.passengerPhone,
            pickupLocation: dispatchPayload.pickupLocation,
            pickup: dispatchPayload.pickup,
            dropLocation: dispatchPayload.dropLocation,
            dropoffLocation: dispatchPayload.dropoffLocation,
            drop: dispatchPayload.drop,
            fare: dispatchPayload.fare,
            fareFormatted: dispatchPayload.fareFormatted,
            scheduleType: dispatchPayload.scheduleType,
            scheduledTime: dispatchPayload.scheduledTime,
            acPreference: dispatchPayload.acPreference,
            vehicleType: dispatchPayload.vehicleType,
            notes: dispatchPayload.notes
          },
          $setOnInsert: {
            assignmentId: `ASG-${Date.now().toString().slice(-4)}`,
            createdAt: new Date()
          }
        },
        { upsert: true }
      );
    } catch (e) {}

    // 6. Emit real-time Socket.IO notifications to driver
    const io = req.app.get("io");
    if (io) {
      const eventsToEmit = [
        "ride-dispatched",
        "ride_dispatched",
        "ride:dispatched",
        "ride-assigned",
        "ride_assigned",
        "ride:assigned",
        "new-assignment",
        "new_assignment",
        "driver-assigned",
        "driver_assigned"
      ];

      for (const ev of eventsToEmit) {
        // Direct to driver rooms
        io.to(driverStrId).emit(ev, dispatchPayload);
        io.to(`driver_${driverStrId}`).emit(ev, dispatchPayload);
        if (driverRefId && driverRefId !== driverStrId) {
          io.to(driverRefId).emit(ev, dispatchPayload);
          io.to(`driver_${driverRefId}`).emit(ev, dispatchPayload);
        }
        if (driverName) {
          io.to(driverName).emit(ev, dispatchPayload);
          io.to(`driver_${driverName}`).emit(ev, dispatchPayload);
        }
        // Broadcast to ensure client catches assignment
        io.emit(ev, dispatchPayload);
      }
      console.log(`📡 Dispatched ride ${rideId} to driver ${driverName} (${driverStrId}) via Socket.IO`);
    }

    res.status(200).json({
      success: true,
      message: "Driver assigned successfully",
      data: dispatchPayload
    });
  } catch (error) {
    res.status(500).json({ success: false, message: "Error assigning driver", error: error.message });
  }
};

// DRIVER & COMMON: Get assigned rides (or all active rides if driverId not provided)
exports.getAssignedRides = async (req, res) => {
  try {
    const rawDriverId = req.params.driverId || req.query.driverId || req.query.id;
    const mongoose = require("mongoose");
    const db = mongoose.connection;

    if (!db || mongoose.connection.readyState !== 1) {
      return res.status(200).json({ success: true, count: 0, data: [], rides: [] });
    }

    let driverOid = null;
    let driverStrId = rawDriverId ? rawDriverId.toString() : "";
    let driverRefId = rawDriverId ? rawDriverId.toString() : "";
    let driverName = "";

    if (rawDriverId && rawDriverId !== "assigned" && rawDriverId !== "all") {
      const isDriverOid = mongoose.Types.ObjectId.isValid(rawDriverId);
      try {
        let driverDoc = await db.collection("drivers").findOne({
          $or: [
            isDriverOid ? { _id: new mongoose.Types.ObjectId(rawDriverId) } : null,
            { _id: rawDriverId },
            { driverReferenceId: rawDriverId }
          ].filter(Boolean)
        }, { maxTimeMS: 4000 });

        if (driverDoc) {
          driverOid = driverDoc._id;
          driverStrId = driverDoc._id.toString();
          driverRefId = driverDoc.driverReferenceId || driverStrId;
          driverName = driverDoc.fullName || driverDoc.Name || "";
        }
      } catch (_) {}
    }

    const driverIdentifiers = [driverOid, driverStrId, driverRefId].filter(Boolean);

    // Helper: Normalize incoming / active status
    const normalizeRideStatus = (rawStatus, currentStatus) => {
      const s = (currentStatus || rawStatus || "").toString().trim().toUpperCase();
      if (
        s === "ASSIGNED" ||
        s === "AWAITING DRIVER ACCEPTANCE" ||
        s === "PENDING DISPATCH" ||
        s === "DISPATCHED" ||
        s === "WAITING FOR DRIVER" ||
        s === "PENDING" ||
        s === "VISIBLE"
      ) {
        return "ASSIGNED";
      }
      if (s === "ACCEPTED") return "ACCEPTED";
      if (s === "STARTED") return "STARTED";
      return s;
    };

    const terminalStatuses = ["REJECTED", "CANCELLED", "COMPLETED", "SUPERSEDED"];
    const allFormatted = [];

    const hasDriverFilter = driverIdentifiers.length > 0;
    const ridesQuery = hasDriverFilter
      ? {
          $or: [
            { driver: { $in: driverIdentifiers } },
            { driverId: { $in: driverIdentifiers } },
            ...(driverName ? [{ assignedDriver: { $in: [driverName, new RegExp(`^${driverName}$`, "i")] } }] : []),
            ...(driverName ? [{ "assignedDriverDetails.name": { $in: [driverName, new RegExp(`^${driverName}$`, "i")] } }] : []),
            ...(driverRefId ? [{ "assignedDriverDetails.driverCode": driverRefId }] : []),
            { "driverRequests.driverId": { $in: driverIdentifiers } }
          ]
        }
      : { status: { $nin: ["REJECTED", "CANCELLED", "COMPLETED", "SUPERSEDED", "rejected", "cancelled", "completed", "superseded"] } };

    const asgQuery = hasDriverFilter
      ? {
          driverId: { $in: driverIdentifiers },
          status: { $nin: ["REJECTED", "CANCELLED", "COMPLETED", "SUPERSEDED", "rejected", "cancelled", "completed", "superseded"] }
        }
      : { status: { $nin: ["REJECTED", "CANCELLED", "COMPLETED", "SUPERSEDED", "rejected", "cancelled", "completed", "superseded"] } };

    // Helper to safely extract address string from string or object
    const extractAddress = (loc) => {
      if (!loc) return "";
      if (typeof loc === "string") return loc.trim();
      if (typeof loc === "object") {
        return loc.address || loc.name || loc.formattedAddress || loc.street || "";
      }
      return "";
    };

    // Helper: Format raw document into consistent driver ride object
    const formatRawDoc = (doc, overrideStatus) => {
      if (!doc) return null;
      const rawStatus = doc.rawStatus || doc.status || "";
      const effectiveStatus = normalizeRideStatus(rawStatus, overrideStatus || doc.status);

      if (terminalStatuses.includes(effectiveStatus)) {
        return null;
      }

      const idStr = (doc._id ? doc._id.toString() : "") || (doc.id ? doc.id.toString() : "");
      const reqIdStr = doc.requestId || doc.id || (idStr ? `REQ-${idStr.substring(Math.max(0, idStr.length - 6)).toUpperCase()}` : "REQ-UNKNOWN");

      const custName =
        doc.customerName ||
        doc.passengerName ||
        (doc.passenger && (doc.passenger.name || doc.passenger.fullName)) ||
        (doc.customer && (doc.customer.fullName || doc.customer.Name || doc.customer.name)) ||
        (typeof doc.customer === "string" && !doc.customer.match(/^[0-9a-fA-F]{24}$/) ? doc.customer : "") ||
        "Customer";

      const custPhone =
        doc.passengerPhone ||
        doc.customerPhone ||
        doc.phone ||
        doc.PhoneNumber ||
        (doc.passenger && (doc.passenger.phone || doc.passenger.phoneNumber || doc.passenger.PhoneNumber)) ||
        (doc.customer && (doc.customer.PhoneNumber || doc.customer.phone || doc.customer.phoneNumber)) ||
        "";

      const pickup =
        extractAddress(doc.pickupLocation) ||
        extractAddress(doc.pickup) ||
        extractAddress(doc.route && doc.route.pickupLocation) ||
        extractAddress(doc.from) ||
        (effectiveStatus === "ASSIGNED" || doc.assignmentId ? "Pickup Location" : "");

      const drop =
        extractAddress(doc.dropLocation) ||
        extractAddress(doc.dropoffLocation) ||
        extractAddress(doc.drop) ||
        extractAddress(doc.route && doc.route.dropLocation) ||
        extractAddress(doc.to) ||
        (effectiveStatus === "ASSIGNED" || doc.assignmentId ? "Drop-off Location" : "");

      // If document is completely devoid of route and customer information AND has no status/assignment, ignore it
      if (!pickup && !drop && custName === "Customer" && !custPhone && !doc.assignmentId && effectiveStatus !== "ASSIGNED") {
        return null;
      }

      const dateStr =
        doc.startingFrom ||
        doc.date ||
        doc.bookingDate ||
        doc.scheduledDate ||
        (doc.customSchedule && doc.customSchedule.startDate) ||
        (doc.scheduledTime ? doc.scheduledTime.split(" ")[0] : "") ||
        "";

      const timeStr =
        doc.timeToLeave ||
        doc.timeToReach ||
        doc.offTime ||
        doc.timeSlot ||
        doc.scheduleTime ||
        doc.scheduledTime ||
        (doc.customSchedule && doc.customSchedule.fromTime) ||
        "";

      const scheduleTypeStr =
        doc.scheduleType ||
        (doc.customSchedule ? "Custom Schedule" : (doc.rideType || "Monthly Pick & Drop"));

      const pickupTimeStr =
        doc.timeToReach ||
        doc.scheduleTime ||
        doc.scheduledTime ||
        timeStr;

      const dropoffTimeStr =
        doc.timeToLeave ||
        doc.offTime ||
        timeStr;

      const selectedDaysVal =
        (doc.customSchedule && doc.customSchedule.selectedDays) ||
        doc.selectedDays ||
        [];

      const vehicleTypeStr =
        doc.vehicleType ||
        doc.vehiclePreference ||
        (doc.preferences && doc.preferences.vehicleType) ||
        doc.vehicle ||
        "Sedan";

      const acPrefStr =
        doc.acPreference ||
        (doc.preferences && doc.preferences.acPreference) ||
        (doc.acRequired !== false ? "AC Required" : "Non-AC");

      const notesStr =
        doc.notes ||
        doc.passengerNotes ||
        doc.additionalNotes ||
        doc.specialInstructions ||
        doc.remarks ||
        "";

      const resolvedFare = resolveFare(doc);

      return {
        _id: idStr,
        id: reqIdStr,
        requestId: reqIdStr,
        rideId: reqIdStr,
        customerName: custName,
        passengerName: custName,
        customerPhone: custPhone,
        passengerPhone: custPhone,
        pickupLocation: pickup,
        pickup: pickup,
        dropLocation: drop,
        dropoffLocation: drop,
        drop: drop,
        scheduleType: scheduleTypeStr,
        pickupTime: pickupTimeStr,
        timeToReach: pickupTimeStr,
        scheduleTime: pickupTimeStr,
        scheduledTime: pickupTimeStr,
        dropoffTime: dropoffTimeStr,
        timeToLeave: dropoffTimeStr,
        selectedDays: selectedDaysVal,
        customSchedule: doc.customSchedule || null,
        date: dateStr,
        startingFrom: dateStr,
        fare: resolvedFare,
        fareFormatted: resolvedFare,
        vehicleType: vehicleTypeStr,
        vehiclePreference: vehicleTypeStr,
        acPreference: acPrefStr,
        acRequired: doc.acRequired !== undefined ? doc.acRequired : true,
        notes: notesStr,
        passengerNotes: notesStr,
        status: effectiveStatus,
        rawStatus: effectiveStatus,
        assignedDriver: doc.assignedDriver || driverName || "",
        assignedDriverName: doc.assignedDriver || driverName || "",
        assignedDriverId: driverStrId || "",
        driver: driverStrId,
        driverId: driverStrId,
        seatsNeeded: doc.seatsNeeded || 1,
        rideType: doc.rideType || "Standard"
      };
    };

    // Parallel fetch across all collections with maxTimeMS timeout protection
    const [rrsRes, trsRes, asgRes, ridesRes, hireRes, rplRes] = await Promise.allSettled([
      db.collection("riderequests").find(ridesQuery).maxTimeMS(4000).limit(50).toArray(),
      db.collection("requests").find(ridesQuery).maxTimeMS(4000).limit(50).toArray(),
      db.collection("assignments").find(asgQuery).maxTimeMS(4000).limit(50).toArray(),
      db.collection("rides").find(ridesQuery).maxTimeMS(4000).limit(50).toArray(),
      db.collection("driverhirerequests").find(ridesQuery).maxTimeMS(4000).limit(50).toArray(),
      db.collection("replacementrequests").find(ridesQuery).maxTimeMS(4000).limit(50).toArray(),
    ]);

    // Index loaded requests by _id and requestId in-memory for instant O(1) matching with zero extra DB roundtrips
    const reqLookupMap = new Map();

    const processCollectionResults = (res, defaultPrefix) => {
      if (res.status === "fulfilled" && Array.isArray(res.value)) {
        for (const r of res.value) {
          if (!r.requestId && defaultPrefix) {
            const idStr = (r._id ? r._id.toString() : "") || (r.id ? r.id.toString() : "");
            if (idStr) r.requestId = `${defaultPrefix}-${idStr.substring(Math.max(0, idStr.length - 6)).toUpperCase()}`;
          }

          if (r._id && !reqLookupMap.has(r._id.toString())) reqLookupMap.set(r._id.toString(), r);
          if (r.requestId && !reqLookupMap.has(r.requestId.toString())) reqLookupMap.set(r.requestId.toString(), r);
          if (r.id && !reqLookupMap.has(r.id.toString())) reqLookupMap.set(r.id.toString(), r);
          const item = formatRawDoc(r);
          if (item) allFormatted.push(item);
        }
      }
    };

    processCollectionResults(rrsRes, "REQ");
    processCollectionResults(trsRes, "TT");
    processCollectionResults(ridesRes, "REQ");
    processCollectionResults(hireRes, "HDR");
    processCollectionResults(rplRes, "RPL");

    if (asgRes.status === "fulfilled" && Array.isArray(asgRes.value)) {
      const missingIds = [];
      for (const assignment of asgRes.value) {
        const asgReqId = assignment.requestId ? assignment.requestId.toString() : "";
        if (asgReqId && !reqLookupMap.has(asgReqId)) missingIds.push(asgReqId);
      }
      
      if (missingIds.length > 0) {
        const mongoose = require("mongoose");
        const missingOids = missingIds.filter(id => mongoose.Types.ObjectId.isValid(id)).map(id => new mongoose.Types.ObjectId(id));
        const missingFilter = { $or: [{ _id: { $in: missingOids } }, { requestId: { $in: missingIds } }, { id: { $in: missingIds } }] };
        try {
          const extraReqs = await Promise.all([
            db.collection("requests").find(missingFilter).toArray(),
            db.collection("riderequests").find(missingFilter).toArray(),
            db.collection("driverhirerequests").find(missingFilter).toArray(),
            db.collection("replacementrequests").find(missingFilter).toArray()
          ]);
          for (const r of extraReqs.flat()) {
            if (r._id) reqLookupMap.set(r._id.toString(), r);
            if (r.requestId) reqLookupMap.set(r.requestId.toString(), r);
            if (r.id) reqLookupMap.set(r.id.toString(), r);
          }
        } catch (e) {
          console.error("Error fetching missing requests for assignments", e);
        }
      }

      for (const assignment of asgRes.value) {
        const asgReqId = assignment.requestId ? assignment.requestId.toString() : "";
        const realReq = asgReqId ? reqLookupMap.get(asgReqId) : null;

        const docToFormat = realReq || assignment;
        const effectiveReqStatus = docToFormat.status || docToFormat.rawStatus || assignment.status || "ASSIGNED";
        const item = formatRawDoc(docToFormat, effectiveReqStatus);
        if (item) {
          item.assignmentId = assignment.assignmentId || assignment._id.toString();
          if (assignment.driverId) {
            const dIdStr = assignment.driverId.toString();
            item.driverId = dIdStr;
            item.driver = dIdStr;
            item.assignedDriverId = dIdStr;
          }
          if (assignment.driverDetails) {
            item.assignedDriver = assignment.driverDetails.name || item.assignedDriver;
            item.assignedDriverName = assignment.driverDetails.name || item.assignedDriverName;
            item.driverDetails = assignment.driverDetails;
          } else if (assignment.assignedDriverName || assignment.driverName) {
            const dName = (assignment.assignedDriverName || assignment.driverName).toString();
            item.assignedDriver = dName;
            item.assignedDriverName = dName;
          }
          allFormatted.push(item);
        }
      }
    }

    // Deduplicate rides by requestId and _id
    const seen = new Set();
    const finalRides = [];

    for (const r of allFormatted) {
      const key = r.requestId || r.id || r._id;
      if (key && !seen.has(key)) {
        seen.add(key);
        if (r._id) seen.add(r._id);
        if (r.requestId) seen.add(r.requestId);
        if (r.id) seen.add(r.id);
        finalRides.push(r);
      }
    }

    res.status(200).json({
      success: true,
      message: "Driver assigned rides retrieved successfully",
      data: { rides: finalRides, total: finalRides.length }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: "Error fetching assigned rides", error: error.message });
  }
};

// DRIVER: Update ride status (accept, reject, started, completed)
exports.updateRideStatus = async (req, res) => {
  try {
    const { rideId } = req.params; // This can be an assignment ID or request ID
    const { status, driverId } = req.body;
    const mongoose = require("mongoose");
    const db = mongoose.connection;

    const lowerStatus = status ? status.toLowerCase() : "";
    const validStatuses = ["accepted", "rejected", "started", "completed", "cancelled"];
    if (!validStatuses.includes(lowerStatus)) {
      return res.status(400).json({ success: false, message: "Invalid status" });
    }

    const isOid = mongoose.Types.ObjectId.isValid(rideId);
    const oid = isOid ? new mongoose.Types.ObjectId(rideId) : null;

    const idQueries = [
      oid ? { _id: oid } : null,
      { _id: rideId },
      { requestId: rideId },
      oid ? { requestId: oid } : null,
      { assignmentId: rideId },
      { id: rideId }
    ].filter(Boolean);

    let assignment = null;
    try {
      assignment = await db.collection("assignments").findOne({ $or: idQueries });
    } catch (_) {}

    // Find driver & vehicle info
    let targetDriverId = driverId || (assignment ? assignment.driverId : null);
    const driverDetails = await resolveDriverDetails(targetDriverId, null);

    let targetRequest = null;
    let targetRequestId = null;

    if (assignment) {
      // Optional driver authorization check
      if (driverId && assignment.driverId) {
        let isMatch = assignment.driverId.toString() === driverId.toString();
        if (!isMatch && driverId.startsWith("DRV-")) {
          const Driver = require("../schema/Driver");
          const driver = await Driver.findOne({ driverReferenceId: driverId });
          if (driver && driver._id.toString() === assignment.driverId.toString()) {
            isMatch = true;
          }
        }
        if (!isMatch) {
          return res.status(403).json({ success: false, message: "Not authorized to update this ride" });
        }
      }

      const updateFields = {
        status: status.toUpperCase(),
        rawStatus: status.toUpperCase(),
        updatedAt: new Date()
      };
      if (driverDetails) {
        updateFields.driverDetails = driverDetails;
      }

      await db.collection("assignments").updateOne(
        { _id: assignment._id },
        { $set: updateFields }
      );

      const asgReqId = assignment.requestId;
      const asgReqOid = asgReqId && mongoose.Types.ObjectId.isValid(asgReqId) ? new mongoose.Types.ObjectId(asgReqId) : null;

      const reqQuery = {
        $or: [
          asgReqOid ? { _id: asgReqOid } : null,
          { _id: asgReqId },
          { requestId: asgReqId },
          { id: asgReqId },
          { assignmentId: assignment.assignmentId }
        ].filter(Boolean)
      };

      try {
        targetRequest = await db.collection("requests").findOne(reqQuery);
        if (!targetRequest) {
          targetRequest = await db.collection("riderequests").findOne(reqQuery);
        }
      } catch (_) {}

      targetRequestId = targetRequest ? targetRequest._id : asgReqId;

      const reqUpdateFields = {
        status: status.toUpperCase(),
        rawStatus: status.toUpperCase(),
        updatedAt: new Date()
      };
      if (driverDetails) {
        reqUpdateFields.driverDetails = driverDetails;
        reqUpdateFields.driver = driverDetails.driverId;
        reqUpdateFields.assignedDriver = driverDetails.name;
      }

      try { await db.collection("requests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
      try { await db.collection("riderequests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
      try { await db.collection("driverhirerequests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
      try { await db.collection("replacementrequests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
      try {
        if (asgReqOid) {
          await Ride.findByIdAndUpdate(asgReqOid, { $set: { status: status.toUpperCase(), driver: driverDetails?.driverId || targetDriverId } });
        }
      } catch (_) {}
    } else {
      // Find request in requests, riderequests, or Ride
      const reqQuery = {
        $or: [
          oid ? { _id: oid } : null,
          { _id: rideId },
          { requestId: rideId },
          { id: rideId },
          { assignmentId: rideId }
        ].filter(Boolean)
      };

      try {
        targetRequest = await db.collection("requests").findOne(reqQuery);
        if (!targetRequest) {
          targetRequest = await db.collection("riderequests").findOne(reqQuery);
        }
        if (!targetRequest && isOid) {
          targetRequest = await Ride.findById(oid).lean();
        }
      } catch (_) {}

      if (targetRequest) {
        targetRequestId = targetRequest._id || targetRequest.requestId || rideId;
        const reqUpdateFields = {
          status: status.toUpperCase(),
          rawStatus: status.toUpperCase(),
          updatedAt: new Date()
        };
        if (driverDetails) {
          reqUpdateFields.driverDetails = driverDetails;
          reqUpdateFields.driver = driverDetails.driverId;
          reqUpdateFields.assignedDriver = driverDetails.name;
        }

        try { await db.collection("requests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
        try { await db.collection("riderequests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
        try { await db.collection("driverhirerequests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
        try { await db.collection("replacementrequests").updateOne(reqQuery, { $set: reqUpdateFields }); } catch (_) {}
        try {
          if (oid) {
            await Ride.findByIdAndUpdate(oid, { $set: { status: status.toUpperCase(), driver: driverDetails?.driverId || targetDriverId } });
          }
        } catch (_) {}

        const asgUpdateFields = {
          status: status.toUpperCase(),
          rawStatus: status.toUpperCase(),
          updatedAt: new Date()
        };
        if (driverDetails) {
          asgUpdateFields.driverDetails = driverDetails;
        }
        try {
          await db.collection("assignments").updateMany(
            { $or: [{ requestId: targetRequest._id }, { requestId: targetRequest.requestId }, { requestId: rideId }].filter(Boolean) },
            { $set: asgUpdateFields }
          );
        } catch (_) {}
      } else {
        // Fallback: create dynamic targetRequest object so state update and socket events proceed cleanly
        targetRequestId = rideId;
        targetRequest = {
          _id: rideId,
          requestId: rideId,
          status: status.toUpperCase(),
          rawStatus: status.toUpperCase(),
          driverDetails: driverDetails,
          pickupLocation: "Assigned Pickup",
          dropLocation: "Assigned Destination"
        };
      }
    }

    // Also update targetRequest in-memory object
    if (targetRequest && driverDetails) {
      targetRequest.driverDetails = driverDetails;
    }

    // ─── EMAIL NOTIFICATION TO CUSTOMER (ON ACCEPT OR START) ───────────────
    if (["accepted", "started"].includes(lowerStatus)) {
      try {
        let customerEmail = targetRequest?.passengerEmail || targetRequest?.customerEmail || targetRequest?.email;
        
        // If not directly on request, attempt to find by customerName or default customer in DB
        if (!customerEmail && targetRequest?.customerName) {
          const matchedCust = await db.collection("customers").findOne({
            fullName: { $regex: new RegExp(targetRequest.customerName.trim(), "i") }
          });
          if (matchedCust?.Email) {
            customerEmail = matchedCust.Email;
          }
        }

        if (!customerEmail) {
          // Fallback to any verified customer or first registered customer
          const fallbackCust = await db.collection("customers").findOne({ Email: { $exists: true, $ne: "" } });
          if (fallbackCust?.Email) {
            customerEmail = fallbackCust.Email;
          }
        }

        if (customerEmail && driverDetails) {
          await sendCustomerNotificationEmail(customerEmail, lowerStatus, driverDetails, targetRequest);
        }
      } catch (emailErr) {
        console.error(`❌ Failed to send ${lowerStatus} email:`, emailErr.message);
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Real-time Socket.IO Broadcast for status updates
    try {
      const io = req.app.get("io");
      if (io) {
        const payload = {
          rideId: (targetRequestId || rideId).toString(),
          assignmentId: assignment?._id?.toString() || assignment?.assignmentId || rideId,
          requestId: (targetRequest?.requestId || targetRequestId || rideId).toString(),
          id: (targetRequestId || rideId).toString(),
          status: status.toUpperCase(),
          rawStatus: status.toUpperCase(),
          driverId: driverDetails?.driverId || driverId || assignment?.driverId?.toString(),
          driverDetails: driverDetails,
          driver: driverDetails,
          pickupLocation: targetRequest?.pickupLocation || (targetRequest?.pickup && targetRequest.pickup.address) || "",
          dropLocation: targetRequest?.dropLocation || targetRequest?.dropoffLocation || (targetRequest?.drop && targetRequest.drop.address) || "",
          fare: resolveFare(targetRequest),
          date: targetRequest?.date || "",
          timeToLeave: targetRequest?.timeToLeave || "",
          customerName: targetRequest?.customerName || targetRequest?.passengerName || "",
          customerPhone: targetRequest?.customerPhone || targetRequest?.phone || "",
          updatedAt: new Date().toISOString()
        };

        if (lowerStatus === "accepted") {
          io.emit("ride_accepted", payload);
          io.emit("ride:accepted", payload);
          io.emit("driver_accepted", payload);
          io.emit("driver_assigned", payload);
        }
        io.emit("ride_status_updated", payload);
        io.emit("ride_updated", payload);
        io.emit("ride:updated", payload);

        if (driverId) {
          io.to(driverId.toString()).emit("ride_status_updated", payload);
          io.to(`driver_${driverId}`).emit("ride_status_updated", payload);
        }
        console.log(`📡 Emitted ride status update [${status.toUpperCase()}] with driver details to Socket.IO`);
      }
    } catch (_) {}

    res.status(200).json({
      success: true,
      message: `Ride status updated to ${status.toUpperCase()}`,
      data: {
        rideId,
        status: status.toUpperCase(),
        driverDetails
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: "Error updating ride status", error: error.message });
  }
};

// ADMIN: Dynamically adjust ride fare (PATCH /api/rides/:id)
exports.updateRideFare = async (req, res) => {
  try {
    const rideId = req.params.rideId || req.params.id;
    const { fare } = req.body;
    const mongoose = require("mongoose");
    const db = mongoose.connection;

    if (fare === undefined || fare === null) {
      return res.status(400).json({ success: false, message: "Fare value is required" });
    }

    // Format fare e.g. "Rs. 12,000" if numeric, otherwise preserve
    let formattedFare;
    if (typeof fare === "number") {
      formattedFare = `Rs. ${Number(fare).toLocaleString()}`;
    } else {
      const numOnly = fare.toString().replace(/[^0-9.]/g, "");
      const parsedNum = parseFloat(numOnly);
      if (!isNaN(parsedNum)) {
        formattedFare = `Rs. ${Number(parsedNum).toLocaleString()}`;
      } else {
        formattedFare = fare.toString();
      }
    }

    let updatedDoc = null;
    let driverId = null;

    // 1. Try finding and updating in riderequests
    try {
      const rideReqDoc = await db.collection("riderequests").findOne({
        $or: [
          isOid ? { _id: new mongoose.Types.ObjectId(rideId) } : null,
          { _id: rideId },
          { requestId: rideId },
          { rideId: rideId },
        ].filter(Boolean)
      });

      if (rideReqDoc) {
        const numFare = typeof fare === "number" ? fare : (parseFloat(fare.toString().replace(/[^0-9.]/g, "")) || 0);
        await db.collection("riderequests").updateOne(
          { _id: rideReqDoc._id },
          {
            $set: {
              fare: numFare,
              fareFormatted: formattedFare,
              rawFare: fare,
              updatedAt: new Date()
            }
          }
        );
        updatedDoc = { ...rideReqDoc, fare: formattedFare, fareFormatted: formattedFare };
        driverId = rideReqDoc.assignedDriverId || rideReqDoc.driver || rideReqDoc.driverId;
      }
    } catch (_) {}

    // 2. Try finding and updating in requests collection
    try {
      const reqDoc = await db.collection("requests").findOne({
        $or: [
          isOid ? { _id: new mongoose.Types.ObjectId(rideId) } : null,
          { _id: rideId },
          { requestId: rideId },
          { rideId: rideId },
        ].filter(Boolean)
      });

      if (reqDoc) {
        await db.collection("requests").updateOne(
          { _id: reqDoc._id },
          { 
            $set: { 
              fare: formattedFare, 
              fareFormatted: formattedFare,
              rawFare: fare,
              updatedAt: new Date() 
            } 
          }
        );
        if (!updatedDoc) updatedDoc = { ...reqDoc, fare: formattedFare };
        driverId = driverId || reqDoc.driver || reqDoc.driverId;
      }
    } catch (_) {}

    // 3. Also try finding/updating in assignments collection
    try {
      const asgDoc = await db.collection("assignments").findOne({
        $or: [
          isOid ? { _id: new mongoose.Types.ObjectId(rideId) } : null,
          isOid ? { requestId: new mongoose.Types.ObjectId(rideId) } : null,
          { requestId: rideId },
          { assignmentId: rideId },
        ].filter(Boolean)
      });

      if (asgDoc) {
        await db.collection("assignments").updateOne(
          { _id: asgDoc._id },
          { $set: { fare: formattedFare, updatedAt: new Date() } }
        );
        driverId = driverId || asgDoc.driverId;
        if (!updatedDoc) updatedDoc = { ...asgDoc, fare: formattedFare };
      }
    } catch (_) {}

    // 4. Also try finding/updating in Ride collection
    try {
      if (isOid) {
        const ride = await Ride.findById(rideId);
        if (ride) {
          ride.fare = typeof fare === "number" ? fare : parseFloat(fare.toString().replace(/[^0-9.]/g, "")) || 0;
          await ride.save();
          driverId = driverId || ride.driver;
          if (!updatedDoc) updatedDoc = formatRide(ride);
        }
      }
    } catch (_) {}

    if (!updatedDoc) {
      return res.status(404).json({ success: false, message: `Ride not found with id: ${rideId}` });
    }

    // 5. Real-time Socket.IO Broadcast
    const io = req.app.get("io");
    if (io) {
      const payload = {
        rideId,
        id: rideId,
        fare: formattedFare,
        rawFare: fare,
        driverId: driverId ? driverId.toString() : null,
        ride: updatedDoc,
        timestamp: new Date().toISOString(),
      };

      // Broadcast globally to all listeners
      io.emit("fare_updated", payload);
      io.emit("fare-updated", payload);
      io.emit("ride_updated", payload);
      io.emit("ride:updated", payload);
      io.emit("ride-updated", payload);

      // Also emit directly to the assigned driver's socket room if available
      if (driverId) {
        const dId = driverId.toString();
        io.to(dId).emit("fare_updated", payload);
        io.to(`driver_${dId}`).emit("fare_updated", payload);
        io.to(dId).emit("ride_updated", payload);
        io.to(`driver_${dId}`).emit("ride_updated", payload);
      }

      console.log(`📡 Real-time fare update emitted for ride ${rideId}: ${formattedFare}`);
    }

    return res.status(200).json({
      success: true,
      message: "Fare updated successfully",
      data: {
        _id: rideId,
        fare: formattedFare,
        rawFare: fare,
        ride: updatedDoc,
      },
    });
  } catch (error) {
    console.error("Update Fare Error:", error);
    return res.status(500).json({ success: false, message: "Error updating fare", error: error.message });
  }
};

// GET ride details by ID (GET /api/rides/:id)
exports.getRideById = async (req, res) => {
  try {
    const rideId = req.params.rideId || req.params.id;
    const mongoose = require("mongoose");
    const db = mongoose.connection;
    const isOid = mongoose.Types.ObjectId.isValid(rideId);

    // 1. Search riderequests
    try {
      const rReq = await db.collection("riderequests").findOne({
        $or: [
          isOid ? { _id: new mongoose.Types.ObjectId(rideId) } : null,
          { _id: rideId },
          { requestId: rideId },
          { rideId: rideId },
        ].filter(Boolean)
      });
      if (rReq) {
        const driverDetails = rReq.driverDetails || rReq.assignedDriverDetails || await resolveDriverDetails(rReq.driver || rReq.driverId || rReq.assignedDriverId, null);
        return res.status(200).json({
          success: true,
          data: {
            _id: rReq._id.toString(),
            requestId: rReq.requestId || `REQ-${rReq._id.toString().substring(18).toUpperCase()}`,
            customerName: rReq.passengerName || rReq.customerName || "Unknown",
            customerPhone: rReq.passengerPhone || rReq.customerPhone || rReq.phone || "",
            pickupLocation: rReq.pickupLocation || "",
            dropLocation: rReq.dropoffLocation || rReq.dropLocation || "",
            date: rReq.startingFrom || rReq.date || "",
            timeToLeave: rReq.timeToLeave || rReq.scheduleTime || "",
            fare: resolveFare(rReq),
            status: rReq.status ? rReq.status.toUpperCase() : "PENDING",
            rawStatus: rReq.rawStatus ? rReq.rawStatus.toUpperCase() : (rReq.status ? rReq.status.toUpperCase() : "PENDING"),
            driverId: rReq.assignedDriverId ? rReq.assignedDriverId.toString() : (rReq.driver ? rReq.driver.toString() : (driverDetails?.driverId || "")),
            driverDetails: driverDetails,
            driver: driverDetails,
          },
        });
      }
    } catch (_) {}

    // 2. Search requests collection
    try {
      const request = await db.collection("requests").findOne({
        $or: [
          isOid ? { _id: new mongoose.Types.ObjectId(rideId) } : null,
          { _id: rideId },
          { requestId: rideId },
          { rideId: rideId },
        ].filter(Boolean)
      });
      if (request) {
        const driverDetails = request.driverDetails || await resolveDriverDetails(request.driver || request.driverId, null);
        return res.status(200).json({
          success: true,
          data: {
            _id: request._id.toString(),
            requestId: request.requestId || `REQ-${request._id.toString().substring(18).toUpperCase()}`,
            customerName: request.customerName || request.passengerName || "Unknown",
            customerPhone: request.passengerPhone || request.customerPhone || request.phone || "",
            pickupLocation: request.pickupLocation || "",
            dropLocation: request.dropLocation || request.dropoffLocation || "",
            date: request.startingFrom || request.date || "",
            timeToLeave: request.timeToLeave || request.scheduleTime || "",
            fare: resolveFare(request),
            status: request.status ? request.status.toUpperCase() : "PENDING",
            rawStatus: request.rawStatus ? request.rawStatus.toUpperCase() : (request.status ? request.status.toUpperCase() : "PENDING"),
            driverId: request.driver ? request.driver.toString() : (driverDetails?.driverId || ""),
            driverDetails: driverDetails,
            driver: driverDetails,
          },
        });
      }
    } catch (_) {}

    // 3. Search assignments collection
    try {
      const assignment = await db.collection("assignments").findOne({
        $or: [
          isOid ? { _id: new mongoose.Types.ObjectId(rideId) } : null,
          { assignmentId: rideId },
        ].filter(Boolean)
      });
      if (assignment) {
        const reqDoc = assignment.requestId ? (await db.collection("riderequests").findOne({ _id: assignment.requestId }) || await db.collection("requests").findOne({ _id: assignment.requestId })) : null;
        const driverDetails = assignment.driverDetails || reqDoc?.driverDetails || await resolveDriverDetails(assignment.driverId, null);
        return res.status(200).json({
          success: true,
          data: {
            _id: assignment._id.toString(),
            requestId: reqDoc?.requestId || assignment.assignmentId || "",
            customerName: reqDoc?.passengerName || reqDoc?.customerName || "Unknown",
            customerPhone: reqDoc?.passengerPhone || reqDoc?.customerPhone || reqDoc?.phone || "",
            pickupLocation: reqDoc?.pickupLocation || "",
            dropLocation: reqDoc?.dropoffLocation || reqDoc?.dropLocation || "",
            date: reqDoc?.startingFrom || reqDoc?.date || "",
            timeToLeave: reqDoc?.timeToLeave || reqDoc?.scheduleTime || "",
            fare: resolveFare(reqDoc) || resolveFare(assignment),
            status: assignment.status ? assignment.status.toUpperCase() : "ASSIGNED",
            rawStatus: assignment.status ? assignment.status.toUpperCase() : "ASSIGNED",
            driverId: assignment.driverId ? assignment.driverId.toString() : "",
            driverDetails: driverDetails,
            driver: driverDetails,
          },
        });
      }
    } catch (_) {}

    // 4. Search Ride schema
    try {
      if (isOid) {
        const ride = await Ride.findById(rideId).populate("customer", "fullName PhoneNumber Email");
        if (ride) {
          const formatted = formatRide(ride);
          const driverDetails = await resolveDriverDetails(ride.driver, null);
          return res.status(200).json({
            success: true,
            data: {
              ...formatted,
              driverDetails: driverDetails,
              driver: driverDetails,
            },
          });
        }
      }
    } catch (_) {}

    return res.status(404).json({ success: false, message: "Ride not found" });
  } catch (error) {
    return res.status(500).json({ success: false, message: "Error fetching ride details", error: error.message });
  }
};

// GET active ride for customer (GET /api/rides/active/customer)
exports.getActiveRide = async (req, res) => {
  try {
    const mongoose = require("mongoose");
    const db = mongoose.connection;
    const { customerName, phone } = req.query;

    let query = {};
    if (customerName) {
      query.$or = [
        { customerName: { $regex: new RegExp(customerName.trim(), "i") } },
        { passengerName: { $regex: new RegExp(customerName.trim(), "i") } },
      ];
    }
    if (phone) {
      query.$or = [{ phone }, { customerPhone: phone }, { passengerPhone: phone }, { PhoneNumber: phone }];
    }

    // Find latest request (prioritizing ACCEPTED or active status, or just latest)
    let request = await db.collection("riderequests").findOne(
      { ...query, status: { $in: ["ACCEPTED", "STARTED", "ASSIGNED", "accepted", "started", "assigned"] } },
      { sort: { updatedAt: -1, createdAt: -1 } }
    );

    if (!request) {
      request = await db.collection("requests").findOne(
        { ...query, status: { $in: ["ACCEPTED", "STARTED", "ASSIGNED", "accepted", "started", "assigned"] } },
        { sort: { updatedAt: -1, createdAt: -1 } }
      );
    }

    if (!request) {
      request = await db.collection("riderequests").findOne(
        query,
        { sort: { updatedAt: -1, createdAt: -1 } }
      );
    }

    if (!request) {
      request = await db.collection("requests").findOne(
        query,
        { sort: { updatedAt: -1, createdAt: -1 } }
      );
    }

    if (!request) {
      return res.status(404).json({ success: false, message: "No active rides found" });
    }

    const driverDetails = request.driverDetails || request.assignedDriverDetails || await resolveDriverDetails(request.driver || request.driverId || request.assignedDriverId, null);

    return res.status(200).json({
      success: true,
      data: {
        _id: request._id.toString(),
        requestId: request.requestId || `REQ-${request._id.toString().substring(18).toUpperCase()}`,
        customerName: request.passengerName || request.customerName || "Unknown",
        customerPhone: request.passengerPhone || request.customerPhone || request.phone || "",
        pickupLocation: request.pickupLocation || "",
        dropLocation: request.dropoffLocation || request.dropLocation || "",
        date: request.startingFrom || request.date || "",
        timeToLeave: request.timeToLeave || request.scheduleTime || "",
        fare: resolveFare(request),
        status: request.status ? request.status.toUpperCase() : "PENDING",
        rawStatus: request.rawStatus ? request.rawStatus.toUpperCase() : (request.status ? request.status.toUpperCase() : "PENDING"),
        driverId: request.assignedDriverId ? request.assignedDriverId.toString() : (request.driver ? request.driver.toString() : (driverDetails?.driverId || "")),
        driverDetails: driverDetails,
        driver: driverDetails,
      },
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: "Error fetching active ride", error: error.message });
  }
};

