const mongoose = require("mongoose");

const passwordResetRequestSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
    },
    userType: {
      type: String,
      enum: ["Customer", "Driver"],
      required: true,
    },
    status: {
      type: String,
      enum: ["Pending", "Approved", "Rejected"],
      default: "Pending",
    },
    resetToken: {
      type: String,
      default: null,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.models.PasswordResetRequest || mongoose.model("PasswordResetRequest", passwordResetRequestSchema);
