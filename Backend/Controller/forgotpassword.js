const Customer = require("../schema/user");
const OTP = require("../schema/otp");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const sendOTPEmail = require("../utils/Email");

// ==========================================
// POST /api/auth/forgot-password/send-otp
// body: { email }
// ==========================================
module.exports.sendForgotPasswordOtp = async (req, res) => {
    try {
        const { email } = req.body;

        if (!email) {
            return res.status(400).json({
                success: false,
                message: "Email is required"
            });
        }

        const normalizedEmail = email.trim().toLowerCase();
        const escapedEmail = normalizedEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

        const customer = await Customer.findOne({
            $or: [
                { Email: normalizedEmail },
                { Email: { $regex: new RegExp("^" + escapedEmail + "$", "i") } }
            ]
        });

        if (!customer) {
            return res.status(404).json({
                success: false,
                message: "No customer account found with this email"
            });
        }

        // Generate 6-digit OTP
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        console.log(`[Forgot Password] Generated OTP for ${normalizedEmail}:`, otp);

        const hashedOTP = await bcrypt.hash(otp, 10);

        // Delete any existing OTP for this customer
        await OTP.deleteMany({ customerId: customer._id });

        // Save new OTP
        await OTP.create({
            customerId: customer._id,
            email: normalizedEmail,
            otp: hashedOTP,
            otpExpiresAt: new Date(Date.now() + 10 * 60 * 1000), // 10 minutes
            otpAttempts: 0,
            verified: false,
            resendCount: 0,
            lastResendAt: null
        });

        // Send OTP via email
        try {
            await sendOTPEmail(normalizedEmail, otp);
            console.log("Forgot Password OTP email sent successfully to:", normalizedEmail);
        } catch (mailErr) {
            console.warn("Nodemailer notice (OTP logged to console):", mailErr.message);
        }

        return res.status(200).json({
            success: true,
            message: "OTP sent to your email successfully",
            email: normalizedEmail,
            phoneNumber: customer.PhoneNumber
        });

    } catch (err) {
        console.error("Send Forgot Password OTP Error:", err);
        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: err.message
        });
    }
};

// ==========================================
// POST /api/auth/forgot-password/verify-otp
// body: { email, otp }
// ==========================================
module.exports.verifyForgotPasswordOtp = async (req, res) => {
    try {
        const { email, otp } = req.body;

        if (!email || !otp) {
            return res.status(400).json({
                success: false,
                message: "Email and OTP are required"
            });
        }

        const normalizedEmail = email.trim().toLowerCase();
        const escapedEmail = normalizedEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

        const customer = await Customer.findOne({
            $or: [
                { Email: normalizedEmail },
                { Email: { $regex: new RegExp("^" + escapedEmail + "$", "i") } }
            ]
        });

        if (!customer) {
            return res.status(404).json({
                success: false,
                message: "Customer not found"
            });
        }

        const otpData = await OTP.findOne({
            customerId: customer._id
        }).sort({ createdAt: -1 });

        if (!otpData) {
            return res.status(404).json({
                success: false,
                message: "OTP not found or expired. Please request a new one."
            });
        }

        if (otpData.otpAttempts >= 5) {
            return res.status(400).json({
                success: false,
                message: "Maximum OTP attempts exceeded. Please request a new OTP."
            });
        }

        if (!otpData.otpExpiresAt || new Date() > otpData.otpExpiresAt) {
            return res.status(400).json({
                success: false,
                message: "OTP has expired. Please request a new code."
            });
        }

        const isMatch = await bcrypt.compare(otp.toString().trim(), otpData.otp);

        if (!isMatch) {
            otpData.otpAttempts += 1;
            await otpData.save();
            return res.status(400).json({
                success: false,
                message: "Invalid OTP code. Please try again."
            });
        }

        // Clean up OTP record
        await OTP.findByIdAndDelete(otpData._id);

        // Generate Password Reset Token (valid for 15 minutes)
        const resetToken = jwt.sign(
            {
                id: customer._id,
                email: customer.Email,
                purpose: "password_reset"
            },
            process.env.JWT_SECRET || "default_jwt_secret_key_ride_and_serve",
            {
                expiresIn: "15m"
            }
        );

        return res.status(200).json({
            success: true,
            message: "OTP verified successfully",
            resetToken: resetToken,
            customer: {
                id: customer._id,
                fullName: customer.fullName,
                email: customer.Email,
                phoneNumber: customer.PhoneNumber,
                countryCode: customer.countryCode
            }
        });

    } catch (err) {
        console.error("Verify Forgot Password OTP Error:", err);
        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: err.message
        });
    }
};

// ==========================================
// GET /api/auth/forgot-password/status?email=xyz (backwards compatibility)
// ==========================================
module.exports.checkPasswordResetStatus = async (req, res) => {
    return res.status(200).json({
        success: true,
        message: "Status endpoint available"
    });
};

// ==========================================
// POST /api/auth/forgot-password/reset-password
// body: { resetToken, newPassword, confirmPassword }
// ==========================================
module.exports.resetPassword = async (req, res) => {
    try {
        const { resetToken, newPassword, confirmPassword } = req.body;

        if (!resetToken || !newPassword || !confirmPassword) {
            return res.status(400).json({
                success: false,
                message: "resetToken, newPassword and confirmPassword are required"
            });
        }

        if (newPassword !== confirmPassword) {
            return res.status(400).json({
                success: false,
                message: "Passwords do not match"
            });
        }

        if (newPassword.length < 8) {
            return res.status(400).json({
                success: false,
                message: "Password must be at least 8 characters long"
            });
        }

        let payload;
        try {
            payload = jwt.verify(resetToken, process.env.JWT_SECRET || "default_jwt_secret_key_ride_and_serve");
        } catch (err) {
            return res.status(400).json({
                success: false,
                message: "Reset token has expired or is invalid. Please request a new OTP."
            });
        }

        if (payload.purpose !== "password_reset") {
            return res.status(400).json({
                success: false,
                message: "Invalid reset token"
            });
        }

        const customer = await Customer.findById(payload.id);

        if (!customer) {
            return res.status(404).json({
                success: false,
                message: "Customer account not found"
            });
        }

        const hashedPassword = await bcrypt.hash(newPassword, 10);
        customer.Password = hashedPassword;
        await customer.save();

        // Clear any previous OTPs
        await OTP.deleteMany({ customerId: customer._id });

        return res.status(200).json({
            success: true,
            message: "Password reset successful! You can now log in with your new password.",
            phoneNumber: customer.PhoneNumber,
            countryCode: customer.countryCode,
            fullName: customer.fullName
        });

    } catch (err) {
        console.error("Reset Password Error:", err);
        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: err.message
        });
    }
};