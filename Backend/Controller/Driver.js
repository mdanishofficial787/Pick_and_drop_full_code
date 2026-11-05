const Driver = require("../schema/Driver");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const cloudinary = require("../config/cloudinary");
const { parseGlobalPhoneNumber } = require("../utils/CountryCode");

const generateToken = (id) => {
  return jwt.sign({ id }, process.env.JWT_SECRET, {
    expiresIn: "7d",
  });
};

const generateDriverReferenceId = () => {
  const random = Math.random().toString(36).substring(2, 8).toUpperCase();
  return `DRV-${Date.now()}-${random}`;
};

const uploadToCloudinary = (buffer, folder) => {
  return new Promise((resolve, reject) => {
    cloudinary.uploader
      .upload_stream(
        {
          folder,
          resource_type: "image",
        },
        (error, result) => {
          if (error) {
            return reject(error);
          }
          resolve({
            url: result.secure_url,
            public_id: result.public_id,
          });
        }
      )
      .end(buffer);
  });
};

const registerDriver = async (req, res) => {
  try {
    let {
      Name,
      CountryCode,
      PhoneNumber,
      Email,
      Password,
      CnicNumber,
      License,
      LicenseExpiryDate,
      CountryIso,
      backgroundCheckConsent,
    } = req.body;

    if (!Name || !PhoneNumber || !Password || !Email) {
      return res.status(400).json({
        success: false,
        message:
          "Please fill all required fields: Name, PhoneNumber, Password and Email",
      });
    }

    const cleanPhone = (PhoneNumber || "").toString().replace(/[\s\-()]/g, '');
    const pakPhoneRegex = /^((\+92|92)?(0)?3[0-9]{9})$/;
    if (!pakPhoneRegex.test(cleanPhone)) {
      return res.status(400).json({
        success: false,
        message: "Please enter a valid Pakistani phone number (e.g. 03328904416)",
      });
    }

    const files = req.files || {};
    const requiredImages = [
      "driverPhoto",
      "CnicFront",
      "CnicBack",
      "LicenseFront",
      "LicenseBack",
    ];

    for (const field of requiredImages) {
      if (!files[field]?.[0]) {
        return res.status(400).json({
          success: false,
          message: `Missing required image: ${field}`,
        });
      }
    }

    const rawInput =
      CountryCode && !PhoneNumber.startsWith("+")
        ? `${CountryCode}${PhoneNumber}`
        : PhoneNumber;

    const parsedPhone = parseGlobalPhoneNumber(rawInput, CountryIso || "PK");

    if (!parsedPhone || !parsedPhone.isValid) {
      return res.status(400).json({
        success: false,
        message: "Invalid phone number or country code.",
      });
    }

    const finalCountryCode = parsedPhone.countryCode;
    const finalPhoneNumber = parsedPhone.formattedLocal;
    const finalCountryIso = parsedPhone.countryIso;

    const cleanEmail = Email.toLowerCase().trim();

    const coreReg = finalPhoneNumber.replace(/\D/g, "").replace(/^92/, "").replace(/^0/, "");
    const regVariants = [finalPhoneNumber, coreReg, "0" + coreReg, "+92" + coreReg, "92" + coreReg];

    const existingDriver = await Driver.findOne({
      $or: [
        {
          PhoneNumber: { $in: regVariants },
        },
        {
          Email: cleanEmail,
        },
      ],
    });

    if (existingDriver) {
      return res.status(400).json({
        success: false,
        message: "Driver already exists with this phone number or email",
      });
    }

    const driverPhoto = await uploadToCloudinary(
      files.driverPhoto[0].buffer,
      "drivers/driverphoto"
    );
    const CnicFront = await uploadToCloudinary(
      files.CnicFront[0].buffer,
      "drivers/cnic"
    );
    const CnicBack = await uploadToCloudinary(
      files.CnicBack[0].buffer,
      "drivers/cnic"
    );
    const LicenseFront = await uploadToCloudinary(
      files.LicenseFront[0].buffer,
      "drivers/license"
    );
    const LicenseBack = await uploadToCloudinary(
      files.LicenseBack[0].buffer,
      "drivers/license"
    );

    const hashedPassword = await bcrypt.hash(Password, 10);
    const driverReferenceId = generateDriverReferenceId();

    const newDriver = new Driver({
      Name: Name.trim(),
      CountryCode: finalCountryCode,
      PhoneNumber: finalPhoneNumber,
      CountryIso: finalCountryIso,
      Email: cleanEmail,
      Password: hashedPassword,
      CnicNumber: CnicNumber ? CnicNumber.trim() : undefined,
      License: License ? License.trim() : undefined,
      LicenseExpiryDate,
      backgroundCheckConsent:
        backgroundCheckConsent === true || backgroundCheckConsent === "true",
      driverReferenceId,
      driverPhoto,
      CnicFront,
      CnicBack,
      LicenseFront,
      LicenseBack,
    });

    await newDriver.save();

    const token = generateToken(newDriver._id);
    const driverResponse = newDriver.toObject();
    delete driverResponse.Password;

    return res.status(201).json({
      success: true,
      message: "Driver registered successfully",
      token,
      driver: driverResponse,
    });
  } catch (error) {
    console.error("Register Driver Error:", error);

    if (error.code === 11000) {
      const duplicateField = Object.keys(error.keyPattern || {})[0];
      return res.status(409).json({
        success: false,
        message: `Driver already exists with this ${duplicateField}`,
      });
    }

    if (error.name === "ValidationError") {
      const validationErrors = Object.values(error.errors).map(
        (err) => err.message
      );
      return res.status(400).json({
        success: false,
        message: "Driver data validation failed",
        errors: validationErrors,
      });
    }

    if (error.http_code || error.name === "UploadError") {
      return res.status(500).json({
        success: false,
        message: "Document upload failed. Please try again.",
      });
    }

    return res.status(500).json({
      success: false,
      message: "Unable to register driver. Please try again later.",
    });
  }
};

const getDrivers = async (req, res) => {
  try {
    const filter = {};
    if (req.query.status) filter.verificationStatus = req.query.status;
    if (req.query.complete !== undefined) {
      filter.registrationComplete = req.query.complete === "true";
    }

    const drivers = await Driver.find(filter).select("-Password");

    return res.status(200).json({
      success: true,
      count: drivers.length,
      drivers,
    });
  } catch (error) {
    console.error("Get Drivers Error:", error);
    return res.status(500).json({
      success: false,
      message: "Unable to retrieve drivers. Please try again later.",
    });
  }
};

const getDriverById = async (req, res) => {
  try {
    const driver = await Driver.findById(req.params.id).select("-Password");

    if (!driver) {
      return res.status(404).json({
        success: false,
        message: "Driver not found",
      });
    }

    return res.status(200).json({
      success: true,
      driver,
    });
  } catch (error) {
    console.error("Get Driver By ID Error:", error);
    return res.status(500).json({
      success: false,
      message: "Unable to retrieve driver. Please try again later.",
    });
  }
};

const updateDriver = async (req, res) => {
  try {
    const updates = { ...req.body };

    delete updates.Password;
    delete updates.ConfirmPassword;
    delete updates.driverReferenceId;

    if (typeof updates.availability === 'string') {
      updates.tripStatus = updates.availability;
      delete updates.availability;
    }

    const phoneInput = updates.PhoneNumber || updates.phoneNumber || updates.phone;
    if (phoneInput !== undefined && phoneInput !== null && phoneInput.toString().trim().length > 0) {
      const cleanPhone = phoneInput.toString().replace(/[\s\-()]/g, "");
      const pakPhoneRegex = /^((\+92|92)?(0)?3[0-9]{9})$/;
      if (!pakPhoneRegex.test(cleanPhone)) {
        return res.status(400).json({
          success: false,
          message: "Please enter a valid Pakistani phone number (e.g. 03328904416)",
        });
      }

      let formattedPhone = cleanPhone;
      if (formattedPhone.startsWith("+92")) {
        formattedPhone = "0" + formattedPhone.slice(3);
      } else if (formattedPhone.startsWith("92") && formattedPhone.length === 12) {
        formattedPhone = "0" + formattedPhone.slice(2);
      } else if (formattedPhone.startsWith("3")) {
        formattedPhone = "0" + formattedPhone;
      }

      const coreDigits = formattedPhone.replace(/\D/g, "").replace(/^92/, "").replace(/^0/, "");
      const checkVariants = [formattedPhone, coreDigits, "0" + coreDigits, "+92" + coreDigits, "92" + coreDigits];
      const existingDriver = await Driver.findOne({
        PhoneNumber: { $in: checkVariants },
        _id: { $ne: req.params.id },
      });
      if (existingDriver) {
        return res.status(400).json({
          success: false,
          message: "Phone number is already registered with another account",
        });
      }

      updates.PhoneNumber = formattedPhone;
      updates.CountryCode = "+92";
      updates.CountryIso = "PK";
      delete updates.phoneNumber;
      delete updates.phone;
    }

    const files = req.files || {};

    if (files.driverPhoto?.[0]) {
      updates.driverPhoto = await uploadToCloudinary(
        files.driverPhoto[0].buffer,
        "drivers/driverphoto"
      );
    }
    if (files.CnicFront?.[0]) {
      updates.CnicFront = await uploadToCloudinary(
        files.CnicFront[0].buffer,
        "drivers/cnic"
      );
    }
    if (files.CnicBack?.[0]) {
      updates.CnicBack = await uploadToCloudinary(
        files.CnicBack[0].buffer,
        "drivers/cnic"
      );
    }
    if (files.LicenseFront?.[0]) {
      updates.LicenseFront = await uploadToCloudinary(
        files.LicenseFront[0].buffer,
        "drivers/license"
      );
    }
    if (files.LicenseBack?.[0]) {
      updates.LicenseBack = await uploadToCloudinary(
        files.LicenseBack[0].buffer,
        "drivers/license"
      );
    }

    const updatedDriver = await Driver.findByIdAndUpdate(
      req.params.id,
      { $set: updates },
      { new: true, runValidators: true }
    ).select("-Password");

    if (!updatedDriver) {
      return res.status(404).json({
        success: false,
        message: "Driver not found",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Driver updated successfully",
      driver: updatedDriver,
    });
  } catch (error) {
    console.error("Update Driver Error:", error);

    if (error.code === 11000) {
      const duplicateField = Object.keys(error.keyPattern || {})[0];
      return res.status(409).json({
        success: false,
        message: `Driver already exists with this ${duplicateField}`,
      });
    }

    if (error.name === "ValidationError") {
      const validationErrors = Object.values(error.errors).map(
        (err) => err.message
      );
      return res.status(400).json({
        success: false,
        message: "Driver data validation failed",
        errors: validationErrors,
      });
    }

    return res.status(500).json({
      success: false,
      message: "Unable to update driver. Please try again later.",
    });
  }
};

const savePreferredRoutes = async (req, res) => {
  try {
    const { driverId, startPoint, endPoint, time } = req.body;

    if (!driverId) {
      return res.status(400).json({ success: false, message: "Driver ID is required" });
    }

    if (!startPoint) {
      return res.status(400).json({ success: false, message: "Start Point is required" });
    }

    const updatedDriver = await Driver.findByIdAndUpdate(
      driverId,
      {
        $set: {
          preferredRoutes: {
            startPoint,
            endPoint: endPoint || "",
            time: time || "",
          },
        },
      },
      { new: true }
    ).select("-Password");

    if (!updatedDriver) {
      return res.status(404).json({ success: false, message: "Driver not found" });
    }

    return res.status(200).json({
      success: true,
      message: "Preferred routes saved successfully",
      driver: updatedDriver,
    });
  } catch (error) {
    console.error("Save Preferred Routes Error:", error);
    return res.status(500).json({
      success: false,
      message: "Unable to save preferred routes. Please try again later.",
    });
  }
};

const saveAvailability = async (req, res) => {
  try {
    const { driverId, availability } = req.body;

    if (!driverId) {
      return res.status(400).json({ success: false, message: "Driver ID is required" });
    }

    let updatePayload = { availability };
    if (typeof availability === 'string') {
      updatePayload = { tripStatus: availability };
    }

    const updatedDriver = await Driver.findByIdAndUpdate(
      driverId,
      { $set: updatePayload },
      { new: true }
    ).select("-Password");

    if (!updatedDriver) {
      return res.status(404).json({ success: false, message: "Driver not found" });
    }

    return res.status(200).json({
      success: true,
      message: "Availability saved successfully",
      driver: updatedDriver,
    });
  } catch (error) {
    console.error("Save Availability Error:", error);
    return res.status(500).json({
      success: false,
      message: "Unable to save availability. Please try again later.",
    });
  }
};

const IssueReport = require("../schema/IssueReport");
const RideRequest = require("../schema/RideRequest");
const CustomerNotification = require("../schema/CustomerNotification");
const mongoose = require("mongoose");

const reportIssue = async (req, res) => {
  try {
    const {
      driverId,
      driverName: inputDriverName,
      mode = "Separate",
      issueType,
      reason,
      message,
      details,
      passengers = [],
      passengerId,
      canBePicked,
      reasonNote,
      requestId,
      customerName,
      customerPhone,
      pickupLocation,
      dropoffLocation,
      fare,
      rideId,
      fromDate,
      toDate,
      fromTime,
      toTime,
    } = req.body;

    const finalReason = (issueType || reasonNote || reason || "Heavy Rain").trim();
    const finalDetails = (message || details || reasonNote || "").trim();

    // 1. Resolve Driver
    let driverObjId = null;
    let driverName = inputDriverName || "Driver";
    if (driverId) {
      if (mongoose.Types.ObjectId.isValid(driverId)) {
        driverObjId = driverId;
        const d = await Driver.findById(driverId).select("Name PhoneNumber Email driverReferenceId").lean();
        if (d && d.Name) driverName = d.Name;
      } else {
        const d = await Driver.findOne({
          $or: [
            { driverReferenceId: driverId },
            { PhoneNumber: driverId },
            { Name: new RegExp("^" + driverId.trim() + "$", "i") }
          ]
        }).lean();
        if (d) {
          driverObjId = d._id;
          if (d.Name) driverName = d.Name;
        }
      }
    }

    // 2. Prepare passengers list
    let passengersList = Array.isArray(passengers) ? [...passengers] : [];
    if (passengerId && passengersList.length === 0) {
      passengersList.push({
        id: passengerId,
        name: customerName || "Passenger",
        canBePicked: canBePicked !== false,
        reasonNote: reasonNote || finalReason
      });
    }

    // 3. Save IssueReport document
    let rideObjId = null;
    if (rideId && mongoose.Types.ObjectId.isValid(rideId)) {
      rideObjId = rideId;
    }

    const newIssue = new IssueReport({
      driver: driverObjId,
      driverName: driverName,
      mode: mode,
      issueType: finalReason,
      reason: finalReason,
      message: finalDetails,
      details: finalDetails,
      passengers: passengersList,
      requestId: requestId || (passengersList.length > 0 ? passengersList[0].id : ""),
      customerName: customerName || (passengersList.length > 0 ? passengersList[0].name : ""),
      customerPhone: customerPhone || "",
      pickupLocation: pickupLocation || "",
      dropoffLocation: dropoffLocation || "",
      fare: fare || "",
      ride: rideObjId,
      status: "Pending",
      fromDate: fromDate ? new Date(fromDate) : new Date(),
      toDate: toDate ? new Date(toDate) : new Date(),
      fromTime: fromTime || "",
      toTime: toTime || "",
    });

    await newIssue.save();

    // 4. Update RideRequest documents in DB for affected passengers
    const updatedRideIds = [];
    if (passengersList.length > 0) {
      for (const p of passengersList) {
        const pId = p.id || p.rideId || p.requestId;
        const pReason = p.reasonNote || finalReason;
        const pCanBePicked = p.canBePicked !== false;

        const driverIssueData = {
          issueType: finalReason,
          reportedReason: pReason,
          reasonNote: pReason,
          additionalDetails: finalDetails,
          canBePicked: pCanBePicked,
          driverId: driverId || (driverObjId ? driverObjId.toString() : ""),
          driverName: driverName,
          mode: mode,
          reportedAt: new Date(),
          issueReportId: newIssue._id
        };

        const updateSet = {
          driverIssue: driverIssueData
        };

        if (!pCanBePicked) {
          updateSet.status = "Driver Unavailable";
        }

        let updatedRide = null;
        if (pId) {
          const idQuery = [];
          if (mongoose.Types.ObjectId.isValid(pId)) {
            idQuery.push({ _id: new mongoose.Types.ObjectId(pId) });
          }
          idQuery.push({ requestId: pId });
          updatedRide = await RideRequest.findOneAndUpdate(
            { $or: idQuery },
            { $set: updateSet },
            { returnDocument: 'after' }
          );
        }

        if (!updatedRide && p.name) {
          updatedRide = await RideRequest.findOneAndUpdate(
            { passengerName: new RegExp("^" + p.name.trim() + "$", "i") },
            { $set: updateSet },
            { returnDocument: 'after' }
          );
        }

        if (updatedRide) {
          updatedRideIds.push(updatedRide.requestId || updatedRide._id.toString());

          // Create customer notification if driver is unavailable
          if (!pCanBePicked) {
            const custId = updatedRide.customerId;
            await CustomerNotification.create({
              customerId: custId || null,
              userId: custId || null,
              driverId: driverObjId || driverId || null,
              driverName: driverName,
              passengerName: updatedRide.passengerName,
              passengerPhone: updatedRide.passengerPhone,
              rideId: updatedRide.requestId || updatedRide._id.toString(),
              requestId: updatedRide.requestId || updatedRide._id.toString(),
              type: "DRIVER_UNAVAILABLE",
              title: "Driver Unavailable",
              subtitle: "Your assigned driver reported: " + pReason + ". Replacement requested.",
              reason: pReason,
              reportedReason: pReason,
              additionalDetails: finalDetails || pReason,
              details: finalDetails || pReason,
              status: "UNAVAILABLE",
              canRequestReplacement: true,
              replacementRequested: false
            }).catch(() => {});
          }
        }
      }
    } else if (requestId || rideId) {
      const targetRideId = requestId || rideId;
      const queryOr = [];
      if (mongoose.Types.ObjectId.isValid(targetRideId)) {
        queryOr.push({ _id: new mongoose.Types.ObjectId(targetRideId) });
      }
      queryOr.push({ requestId: targetRideId });

      await RideRequest.updateMany(
        { $or: queryOr },
        {
          $set: {
            status: "Driver Unavailable",
            driverIssue: {
              issueType: finalReason,
              reportedReason: finalReason,
              reasonNote: finalReason,
              additionalDetails: finalDetails,
              canBePicked: false,
              driverId: driverId || (driverObjId ? driverObjId.toString() : ""),
              driverName: driverName,
              reportedAt: new Date(),
              issueReportId: newIssue._id
            }
          }
        }
      );
      updatedRideIds.push(targetRideId);
    }

    // 5. Broadcast real-time socket events
    const io = req.app.get("io");
    if (io) {
      io.emit("new_issue_report", newIssue);
      io.emit("admin_issue_reported", newIssue);
      io.emit("driver-issue-reported", {
        issueId: newIssue._id,
        driverId,
        driverName,
        issueType: finalReason,
        passengers: passengersList,
        updatedRideIds
      });
    }

    return res.status(200).json({
      success: true,
      message: "Issue reported and saved successfully",
      issue: newIssue,
      updatedRideIds
    });
  } catch (error) {
    console.error("Report Issue Error:", error);
    return res.status(500).json({
      success: false,
      message: "Unable to submit issue report. Please try again later.",
      error: error.message,
    });
  }
};

module.exports = {
  registerDriver,
  getDrivers,
  getDriverById,
  updateDriver,
  savePreferredRoutes,
  saveAvailability,
  reportIssue,
};
