const mongoose = require("mongoose");
const Vehicle = require("../schema/Vehicle");
const cloudinary = require("../config/cloudinary");

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

const updateVehicle = async (req, res) => {
  const newUploadedPublicIds = [];
  const oldPublicIdsToDelete = [];

  try {
    const driverId = req.user?.id;

    if (!driverId || !mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized: Invalid driver token.",
      });
    }

    const { id } = req.params;

    if (!id || !mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: "Invalid Vehicle ID format.",
      });
    }

    const vehicle = await Vehicle.findOne({
      _id: id,
      driver: driverId,
    });

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: "Vehicle not found.",
      });
    }

    delete req.body.driver;
    delete req.body.createdBy;
    delete req.body.updatedBy;
    delete req.body.verificationStatus;

    if (req.body.registrationNumber !== undefined) {
      const formattedRegNum = String(req.body.registrationNumber)
        .trim()
        .toUpperCase();

      if (!formattedRegNum) {
        return res.status(400).json({
          success: false,
          message: "Registration number cannot be empty.",
        });
      }

      const existingVehicle = await Vehicle.findOne({
        registrationNumber: formattedRegNum,
        _id: { $ne: id },
      });

      if (existingVehicle) {
        return res.status(409).json({
          success: false,
          message: "Registration number already belongs to another vehicle.",
        });
      }

      vehicle.registrationNumber = formattedRegNum;
    }

    const textFields = [
      "vehicleMake",
      "vehicleModel",
      "variant",
      "numberOfSeats",
      "vehicleColor",
    ];

    textFields.forEach((field) => {
      if (req.body[field] !== undefined) {
        vehicle[field] =
          typeof req.body[field] === "string"
            ? req.body[field].trim()
            : req.body[field];
      }
    });

    if (req.body.numberOfSeats !== undefined) {
      const seats = Number(req.body.numberOfSeats);

      if (!Number.isInteger(seats) || seats < 1) {
        return res.status(400).json({
          success: false,
          message: "Number of seats must be a valid number greater than 0.",
        });
      }

      vehicle.numberOfSeats = seats;
    }

    const files = req.files || {};
    const registrationBook = files.registrationBook?.[0];
    const frontView = files.frontView?.[0];

    const allowedImageTypes = [
      "image/jpeg",
      "image/jpg",
      "image/png",
    ];

    if (registrationBook) {
      if (!allowedImageTypes.includes(registrationBook.mimetype)) {
        return res.status(400).json({
          success: false,
          message: "Registration book must be JPG, JPEG or PNG image.",
        });
      }

      if (vehicle.registrationBook?.public_id) {
        oldPublicIdsToDelete.push(vehicle.registrationBook.public_id);
      }

      const uploadResult = await uploadToCloudinary(
        registrationBook,
        "vehicles/registrationBooks"
      );

      newUploadedPublicIds.push(uploadResult.public_id);

      vehicle.registrationBook = {
        url: uploadResult.url,
        public_id: uploadResult.public_id,
      };
    }

    if (frontView) {
      if (!allowedImageTypes.includes(frontView.mimetype)) {
        return res.status(400).json({
          success: false,
          message: "Front vehicle image must be JPG, JPEG or PNG.",
        });
      }

      if (vehicle.vehicleImages?.frontView?.public_id) {
        oldPublicIdsToDelete.push(vehicle.vehicleImages.frontView.public_id);
      }

      const uploadResult = await uploadToCloudinary(
        frontView,
        "vehicles/images"
      );

      newUploadedPublicIds.push(uploadResult.public_id);

      vehicle.vehicleImages.frontView = {
        url: uploadResult.url,
        public_id: uploadResult.public_id,
      };

      vehicle.markModified("vehicleImages.frontView");
    }

    vehicle.updatedBy = driverId;

    const updatedVehicle = await vehicle.save();

    if (oldPublicIdsToDelete.length > 0) {
      await Promise.allSettled(
        oldPublicIdsToDelete.map((publicId) =>
          deleteFromCloudinary(publicId)
        )
      );
    }

    return res.status(200).json({
      success: true,
      message: "Vehicle updated successfully.",
      vehicle: updatedVehicle,
    });
  } catch (error) {
    console.error("Vehicle update error:", error);

    if (newUploadedPublicIds.length > 0) {
      await Promise.allSettled(
        newUploadedPublicIds.map((publicId) =>
          deleteFromCloudinary(publicId)
        )
      );
    }

    if (error.code === 11000) {
      const duplicateField = Object.keys(error.keyPattern || {})[0];
      return res.status(409).json({
        success: false,
        message:
          duplicateField === "registrationNumber"
            ? "Registration number already exists."
            : "Vehicle already exists.",
      });
    }

    if (error.name === "ValidationError") {
      const errors = Object.values(error.errors).map((err) => err.message);
      return res.status(400).json({
        success: false,
        message: "Vehicle validation failed.",
        errors,
      });
    }

    return res.status(500).json({
      success: false,
      message: "Failed to update vehicle.",
      error: error.message,
    });
  }
};

module.exports = {
  updateVehicle,
};
