const mongoose = require("mongoose");

const otpSchema = new mongoose.Schema(
    {
        customerId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: "Customer",
            required: true
        },
email: {
    type: String,
    required: true,
    lowercase: true,
    trim: true
},
        

        otp: {
            type: String,
            required: true
        },

        otpExpiresAt: {
            type: Date,
            required: true
        },

        otpAttempts: {
            type: Number,
            default: 0
        },

        verified: {
            type: Boolean,
            default: false
        },

        resendCount: {
            type: Number,
            default: 0
        },

        lastResendAt: {
            type: Date,
            default: null
        }
    },

    {
        timestamps: true
    }
);

module.exports = mongoose.model("OTP", otpSchema);
