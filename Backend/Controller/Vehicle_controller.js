const mongoose = require("mongoose");
const Vehicle = require("../schema/Vehicle");
const Driver = require("../schema/Driver");
const cloudinary = require("../config/cloudinary");
const sendEmail = require("../utils/sendemail");

const uploadToCloudinary = (file, folder) => {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
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
    );

    stream.end(file.buffer);
  });
};

const deleteFromCloudinary = (publicId) => {
  return new Promise((resolve, reject) => {
    if (!publicId) {
      return resolve();
    }

    cloudinary.uploader.destroy(
      publicId,
      {
        resource_type: "image",
      },
      (error, result) => {
        if (error) {
          console.error(
            `Failed to delete Cloudinary image: ${publicId}`,
            error
          );

          return reject(error);
        }

        resolve(result);
      }
    );
  });
};

const createVehicle = async (req, res) => {
  const uploadedPublicIds = [];

  try {
    const driverId = req.user?.id;

    if (
      !driverId ||
      !mongoose.Types.ObjectId.isValid(driverId)
    ) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized: Invalid driver token",
      });
    }

    const driver = await Driver.findById(driverId);

    if (!driver) {
      return res.status(404).json({
        success: false,
        message: "Driver account not found",
      });
    }

    const {
      vehicleMake,
      vehicleModel,
      variant,
      numberOfSeats,
      registrationNumber,
      vehicleColor,
    } = req.body;

    if (
      !vehicleMake ||
      !vehicleModel ||
      !variant ||
      !numberOfSeats ||
      !registrationNumber ||
      !vehicleColor
    ) {
      return res.status(400).json({
        success: false,
        message:
          "Please provide all required vehicle information",
      });
    }

    const existingVehicle = await Vehicle.findOne({
      registrationNumber: registrationNumber.trim(),
    });

    if (existingVehicle) {
      return res.status(409).json({
        success: false,
        message:
          "Vehicle with this registration number already exists",
      });
    }

    const files = req.files || {};
    const registrationBook = files.registrationBook?.[0];
    const frontView = files.frontView?.[0];

    if (!registrationBook) {
      return res.status(400).json({
        success: false,
        message: "Registration book image is required",
      });
    }

    if (!frontView) {
      return res.status(400).json({
        success: false,
        message: "Front vehicle image is required",
      });
    }

    const allowedImageTypes = [
      "image/jpeg",
      "image/jpg",
      "image/png",
    ];

    if (!allowedImageTypes.includes(registrationBook.mimetype)) {
      return res.status(400).json({
        success: false,
        message: "Registration book must be JPG, JPEG or PNG image",
      });
    }

    if (!allowedImageTypes.includes(frontView.mimetype)) {
      return res.status(400).json({
        success: false,
        message: "Front vehicle image must be JPG, JPEG or PNG",
      });
    }

    const [
      registrationBookUpload,
      frontViewUpload,
    ] = await Promise.all([
      uploadToCloudinary(
        registrationBook,
        "vehicles/registrationBooks"
      ),
      uploadToCloudinary(
        frontView,
        "vehicles/images"
      ),
    ]);

    uploadedPublicIds.push(
      registrationBookUpload.public_id,
      frontViewUpload.public_id
    );

    const vehicle = await Vehicle.create({
      driver: driverId,
      vehicleMake: vehicleMake.trim(),
      vehicleModel: vehicleModel.trim(),
      variant: variant.trim(),
      numberOfSeats,
      registrationNumber: registrationNumber.trim(),
      vehicleColor: vehicleColor.trim(),
      registrationBook: {
        url: registrationBookUpload.url,
        public_id: registrationBookUpload.public_id,
      },
      vehicleImages: {
        frontView: {
          url: frontViewUpload.url,
          public_id: frontViewUpload.public_id,
        },
      },
      createdBy: driverId,
    });

    driver.registrationComplete = true;
    await driver.save();

    if (process.env.ADMIN_EMAIL) {
      try {
        await sendEmail({
          to: process.env.ADMIN_EMAIL,
          subject: "New Driver Application Ready for Review",
          text:
            `Driver "${driver.Name}" (Ref: ${driver.driverReferenceId}) has completed ` +
            `both driver and vehicle registration and is awaiting verification.\n\n` +
            `Driver ID: ${driver._id}\n` +
            `Vehicle: ${vehicle.vehicleMake} ${vehicle.vehicleModel} (${vehicle.registrationNumber})`,
        });
      } catch (emailErr) {
        console.error("Admin notification email failed:", emailErr);
      }
    }

    return res.status(201).json({
      success: true,
      message: "Vehicle registered successfully. Application sent to admin for review.",
      vehicle,
    });
  } catch (error) {
    console.error("Vehicle registration error:", error);

    if (uploadedPublicIds.length > 0) {
      await Promise.allSettled(
        uploadedPublicIds.map((publicId) =>
          deleteFromCloudinary(publicId)
        )
      );
    }

    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        message: "Vehicle with this registration number already exists",
      });
    }

    return res.status(500).json({
      success: false,
      message: "Failed to register vehicle",
      error: error.message,
    });
  }
};

const getVehicles = async (req, res) => {
  try {
    const driverId = req.user?.id;

    if (!driverId || !mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized",
      });
    }

    const vehicles = await Vehicle.find({
      driver: driverId,
    }).populate("driver", "Name PhoneNumber");

    return res.status(200).json({
      success: true,
      count: vehicles.length,
      vehicles,
    });
  } catch (error) {
    console.error("Get vehicles error:", error);

    return res.status(500).json({
      success: false,
      message: "Failed to get vehicles",
      error: error.message,
    });
  }
};

const getVehicleById = async (req, res) => {
  try {
    const { id } = req.params;
    const driverId = req.user?.id;

    if (!driverId || !mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized",
      });
    }

    if (!id || !mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: "Invalid Vehicle ID format",
      });
    }

    const vehicle = await Vehicle.findOne({
      _id: id,
      driver: driverId,
    }).populate("driver", "Name PhoneNumber");

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: "Vehicle not found",
      });
    }

    return res.status(200).json({
      success: true,
      vehicle,
    });
  } catch (error) {
    console.error("Get vehicle by ID error:", error);

    return res.status(500).json({
      success: false,
      message: "Failed to get vehicle",
      error: error.message,
    });
  }
};

const deleteVehicle = async (req, res) => {
  try {
    const { id } = req.params;
    const driverId = req.user?.id;

    if (!driverId || !mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized",
      });
    }

    if (!id || !mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: "Invalid Vehicle ID format",
      });
    }

    const vehicle = await Vehicle.findOne({
      _id: id,
      driver: driverId,
    });

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: "Vehicle not found",
      });
    }

    const publicIdsToDelete = [];

    if (vehicle.registrationBook?.public_id) {
      publicIdsToDelete.push(vehicle.registrationBook.public_id);
    }

    if (vehicle.vehicleImages?.frontView?.public_id) {
      publicIdsToDelete.push(vehicle.vehicleImages.frontView.public_id);
    }

    if (publicIdsToDelete.length > 0) {
      await Promise.allSettled(
        publicIdsToDelete.map((publicId) =>
          deleteFromCloudinary(publicId)
        )
      );
    }

    await Vehicle.findByIdAndDelete(id);

    return res.status(200).json({
      success: true,
      message: "Vehicle and related media deleted successfully",
    });
  } catch (error) {
    console.error("Delete vehicle error:", error);

    return res.status(500).json({
      success: false,
      message: "Failed to delete vehicle",
      error: error.message,
    });
  }
};

module.exports = {
  createVehicle,
  getVehicles,
  getVehicleById,
  deleteVehicle,
};
