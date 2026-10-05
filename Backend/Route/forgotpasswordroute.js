const express = require("express");
const router = express.Router();

const forgotPasswordController = require("../Controller/forgotPassword");

// Send OTP to email for password reset
router.post(
    "/forgot-password/send-otp",
    forgotPasswordController.sendForgotPasswordOtp
);

// Verify OTP for password reset
router.post(
    "/forgot-password/verify-otp",
    forgotPasswordController.verifyForgotPasswordOtp
);

// Check password reset status
router.get(
    "/forgot-password/status",
    forgotPasswordController.checkPasswordResetStatus
);

// Reset the password using the token from verify-otp
router.post(
    "/forgot-password/reset-password",
    forgotPasswordController.resetPassword
);

module.exports = router;