const mongoose = require("mongoose");

const VehicleSchema = new mongoose.Schema(
  {
    driver: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Driver",
      required: true,
      unique: true,
    },
    vehicleMake: {
      type: String,
      required: [true, "Vehicle make is required"],
      trim: true,
    },
    vehicleModel: {
      type: String,
      required: [true, "Vehicle model is required"],
      trim: true,
    },
    variant: {
      type: String,
      required: [true, "Vehicle variant is required"],
      trim: true,
    },
    numberOfSeats: {
      type: Number,
      required: [true, "Number of seats is required"],
      min: [1, "Number of seats must be at least 1"],
    },
    registrationNumber: {
      type: String,
      required: [true, "Registration number is required"],
      trim: true,
      unique: true,
    },
    vehicleColor: {
      type: String,
      required: [true, "Vehicle color is required"],
      trim: true,
    },
    registrationBook: {
      url: {
        type: String,
        required: true,
      },
      public_id: {
        type: String,
        required: true,
      },
    },
    vehicleImages: {
      frontView: {
        url: {
          type: String,
          required: true,
        },
        public_id: {
          type: String,
          required: true,
        },
      },
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Driver",
      required: true,
    },
    updatedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Driver",
      default: null,
    },
    verificationStatus: {
      type: String,
      enum: ["Pending", "Verified", "Approved", "Rejected"],
      default: "Pending",
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.models.Vehicle || mongoose.model("Vehicle", VehicleSchema);
