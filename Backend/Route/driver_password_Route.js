const express = require("express");
const router = express.Router();

const {
    sendForgotPasswordOTP,
    checkPasswordResetStatus,
} = require("../Controller/driver_forgetPassword");

const {
    resetPassword,
} = require("../Controller/driver_ResetPassword");

// 1. SEND OTP
router.post(
    "/send-otp",
    sendForgotPasswordOTP
);

// 2. CHECK STATUS
router.get(
    "/status",
    checkPasswordResetStatus
);

// 4. RESET PASSWORD
router.post(
    "/reset-password",
    resetPassword
);

module.exports = router;
