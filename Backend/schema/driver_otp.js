const mongoose = require("mongoose");

const driverOtpSchema = new mongoose.Schema(
    {
        driverId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "Driver",
            required: true,
            index: true,
        },
        Email: {
            type: String,
            required: true,
            lowercase: true,
            trim: true,
            index: true,
        },
        Otp: {
            type: String,
            required: true,
        },
        otpExpiresAt: {
            type: Date,
            required: true,
        },
        verified: {
            type: Boolean,
            default: false,
        },
        otpAttempts: {
            type: Number,
            default: 0,
        },
        resendCount: {
            type: Number,
            default: 0,
        },
        lastResendAt: {
            type: Date,
            default: null,
        },
    },
    {
        timestamps: true,
    }
);

driverOtpSchema.index(
    { createdAt: 1 },
    { expireAfterSeconds: 120 }
);

module.exports = mongoose.model("DriverOtp", driverOtpSchema);
