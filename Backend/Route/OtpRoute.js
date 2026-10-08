const express = require("express");
const router = express.Router();

const verifyOTPController = require("../Controller/verifyOTP");
const resendOTPController = require("../Controller/resendOtp");

const {
    validateVerifyOTP
} = require("../Middleware/validationSchema");

// Verify OTP
router.post(
    "/verify-otp",
    validateVerifyOTP,
    verifyOTPController.verifyOTP
);

// Resend OTP
router.post(
    "/resend-otp",
    resendOTPController.resendOTP
);

module.exports = router;
