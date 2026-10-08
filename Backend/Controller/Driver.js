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

    const existingDriver = await Driver.findOne({
      $or: [
        {
          PhoneNumber: finalPhoneNumber,
          CountryCode: finalCountryCode,
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

    if (updates.PhoneNumber) {
      const rawInput =
        updates.CountryCode && !updates.PhoneNumber.startsWith("+")
          ? `${updates.CountryCode}${updates.PhoneNumber}`
          : updates.PhoneNumber;

      const parsedPhone = parseGlobalPhoneNumber(
        rawInput,
        updates.CountryIso || "PK"
      );

      if (parsedPhone && parsedPhone.isValid) {
        updates.CountryCode = parsedPhone.countryCode;
        updates.PhoneNumber = parsedPhone.formattedLocal;
        updates.CountryIso = parsedPhone.countryIso;
      }
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
const mongoose = require("mongoose");

const reportIssue = async (req, res) => {
  try {
    const {
      driverId,
      fromDate,
      toDate,
      fromTime,
      toTime,
      reason,
      details,
      requestId,
      customerName,
      customerPhone,
      pickupLocation,
      dropoffLocation,
      fare,
      rideId,
    } = req.body;
    let driverName = "Driver";
    let driverObjId = null;

    if (driverId && mongoose.Types.ObjectId.isValid(driverId)) {
      driverObjId = driverId;
      const driver = await Driver.findById(driverId).select("Name PhoneNumber Email driverReferenceId").lean();
      if (driver) {
        driverName = driver.Name || "Driver";
      }
    }

    let rideObjId = null;
    if (rideId && mongoose.Types.ObjectId.isValid(rideId)) {
      rideObjId = rideId;
    }

    const newIssue = new IssueReport({
      driver: driverObjId,
      driverName: req.body.driverName || driverName,
      fromDate: fromDate ? new Date(fromDate) : new Date(),
      toDate: toDate ? new Date(toDate) : new Date(),
      fromTime: fromTime || "",
      toTime: toTime || "",
      reason: reason || "Vehicle Issue",
      details: details || "",
      requestId: requestId || "",
      customerName: customerName || "",
      customerPhone: customerPhone || "",
      pickupLocation: pickupLocation || "",
      dropoffLocation: dropoffLocation || "",
      fare: fare || "",
      ride: rideObjId,
      status: "Pending",
    });

    await newIssue.save();

    // Broadcast via socket.io to admin
    const io = req.app.get("io");
    if (io) {
      io.emit("new_issue_report", newIssue);
      io.emit("admin_issue_reported", newIssue);
    }

    return res.status(201).json({
      success: true,
      message: "Issue reported to admin successfully",
      issue: newIssue,
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
