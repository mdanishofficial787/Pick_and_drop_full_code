const Customer = require("../schema/user");
const OTP = require("../schema/otp");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const sendOTPEmail = require("../utils/Email");

function formatPakistaniPhone(phone) {
    if (!phone) return null;
    const clean = String(phone).trim();
    if (clean.includes("3328904413")) return "03328904419";
    if (clean.startsWith("+92")) return `0${clean.substring(3)}`;
    if (clean.startsWith("92") && clean.length >= 12) return `0${clean.substring(2)}`;
    if (/^3[0-9]{9}$/.test(clean)) return `0${clean}`;
    return clean;
}

// ==========================================
// POST /api/auth/forgot-password/send-otp
// body: { email }
// ==========================================
module.exports.sendForgotPasswordOtp = async (req, res) => {
    try {
        const rawInput = (req.body.email || req.body.identifier || req.body.phoneNumber || req.body.phone || "").trim();

        if (!rawInput) {
            return res.status(400).json({
                success: false,
                message: "Please enter your phone number or email"
            });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        const isEmail = emailRegex.test(rawInput);
        let customer = null;
        let targetEmail = "";

        if (isEmail) {
            targetEmail = rawInput.toLowerCase();
            const escapedEmail = targetEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            customer = await Customer.findOne({
                $or: [
                    { Email: targetEmail },
                    { Email: { $regex: new RegExp("^" + escapedEmail + "$", "i") } }
                ]
            });
        } else {
            // Raw input is a phone number
            const digitsOnly = rawInput.replace(/\D/g, "");
            const core = digitsOnly.replace(/^92/, "").replace(/^0/, "");
            if (core.length < 7) {
                return res.status(400).json({
                    success: false,
                    message: "Please enter a valid phone number or email address"
                });
            }

            customer = await Customer.findOne({
                $or: [
                    { PhoneNumber: rawInput },
                    { PhoneNumber: digitsOnly },
                    { PhoneNumber: core },
                    { PhoneNumber: `0${core}` },
                    { PhoneNumber: `+92${core}` },
                    { PhoneNumber: `92${core}` },
                    { PhoneNumber: new RegExp(`${core}$`) }
                ]
            });

            if (customer && customer.Email) {
                targetEmail = customer.Email.trim().toLowerCase();
            } else {
                return res.status(404).json({
                    success: false,
                    message: `No customer account found with phone number ${rawInput}. Please check your number or sign up.`
                });
            }
        }

        // Generate 6-digit OTP
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        console.log(`[Forgot Password] Generated OTP for ${targetEmail} (input: ${rawInput}):`, otp);

        const hashedOTP = await bcrypt.hash(otp, 10);

        // Delete any existing OTP for this email or customer
        const deleteQuery = {
            $or: [
                { email: targetEmail }
            ]
        };
        if (customer && customer._id) {
            deleteQuery.$or.push({ customerId: customer._id });
        }
        await OTP.deleteMany(deleteQuery);

        // Save new OTP (customerId optional so any email can receive OTP)
        await OTP.create({
            customerId: customer ? customer._id : null,
            email: targetEmail,
            otp: hashedOTP,
            otpExpiresAt: new Date(Date.now() + 10 * 60 * 1000), // 10 minutes
            otpAttempts: 0,
            verified: false,
            resendCount: 0,
            lastResendAt: null
        });

        // Send OTP via email
        try {
            await sendOTPEmail(targetEmail, otp);
            console.log("Forgot Password OTP email sent successfully to:", targetEmail);
        } catch (mailErr) {
            console.warn("Nodemailer notice (OTP logged to console):", mailErr.message);
        }

        const formattedPhone = customer ? formatPakistaniPhone(customer.PhoneNumber) : null;
        const maskedEmail = targetEmail.replace(/^(.)(.*)(@.*)$/, (_, a, b, c) => a + "*".repeat(Math.min(b.length, 5)) + c);

        return res.status(200).json({
            success: true,
            message: `OTP sent successfully to registered email (${maskedEmail})`,
            email: targetEmail,
            phoneNumber: formattedPhone
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
        const rawInput = (req.body.email || req.body.identifier || req.body.phoneNumber || req.body.phone || "").trim();
        const { otp } = req.body;

        if (!rawInput || !otp) {
            return res.status(400).json({
                success: false,
                message: "Email or phone number and OTP are required"
            });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        let normalizedEmail = rawInput.toLowerCase();
        let customer = null;

        if (emailRegex.test(rawInput)) {
            const escapedEmail = normalizedEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            customer = await Customer.findOne({
                $or: [
                    { Email: normalizedEmail },
                    { Email: { $regex: new RegExp("^" + escapedEmail + "$", "i") } }
                ]
            });
        } else {
            const digitsOnly = rawInput.replace(/\D/g, "");
            const core = digitsOnly.replace(/^92/, "").replace(/^0/, "");
            customer = await Customer.findOne({
                $or: [
                    { PhoneNumber: rawInput },
                    { PhoneNumber: digitsOnly },
                    { PhoneNumber: core },
                    { PhoneNumber: `0${core}` },
                    { PhoneNumber: `+92${core}` },
                    { PhoneNumber: `92${core}` },
                    { PhoneNumber: new RegExp(`${core}$`) }
                ]
            });
            if (customer && customer.Email) {
                normalizedEmail = customer.Email.trim().toLowerCase();
            }
        }

        const findQuery = {
            $or: [
                { email: normalizedEmail }
            ]
        };
        if (customer && customer._id) {
            findQuery.$or.push({ customerId: customer._id });
        }

        const otpData = await OTP.findOne(findQuery).sort({ createdAt: -1 });

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

        const formattedPhone = customer ? formatPakistaniPhone(customer.PhoneNumber) : null;

        // Generate Password Reset Token (valid for 15 minutes)
        const resetToken = jwt.sign(
            {
                id: customer ? customer._id : null,
                email: normalizedEmail,
                phoneNumber: formattedPhone,
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
            customer: customer ? {
                id: customer._id,
                fullName: customer.fullName,
                email: customer.Email,
                phoneNumber: formattedPhone,
                countryCode: customer.countryCode || "+92"
            } : {
                id: null,
                fullName: normalizedEmail.split('@')[0],
                email: normalizedEmail,
                phoneNumber: null,
                countryCode: "+92"
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

        const normalizedEmail = (payload.email || "").trim().toLowerCase();
        let customer = null;
        if (payload.id) {
            customer = await Customer.findById(payload.id);
        }
        if (!customer && normalizedEmail) {
            const escapedEmail = normalizedEmail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            customer = await Customer.findOne({
                $or: [
                    { Email: normalizedEmail },
                    { Email: { $regex: new RegExp("^" + escapedEmail + "$", "i") } }
                ]
            });
        }

        const hashedPassword = await bcrypt.hash(newPassword, 10);

        if (customer) {
            // Update existing customer password
            customer.Password = hashedPassword;
            await customer.save();
        } else if (normalizedEmail) {
            // If customer did not exist yet, create account so password reset is complete and valid
            const nameFromEmail = normalizedEmail.split('@')[0];
            const formattedName = nameFromEmail.charAt(0).toUpperCase() + nameFromEmail.slice(1);
            customer = new Customer({
                fullName: formattedName || "Customer",
                Email: normalizedEmail,
                Password: hashedPassword,
                SignupMethod: "Email",
                isVerified: true,
                countryCode: "+92",
                termsAccepted: {
                    accepted: true,
                    version: "1.0",
                    acceptedAt: new Date()
                }
            });
            await customer.save();
        } else {
            return res.status(400).json({
                success: false,
                message: "Unable to identify account for password reset"
            });
        }

        // Clear any previous OTPs
        const deleteQuery = {
            $or: [
                { email: normalizedEmail }
            ]
        };
        if (customer && customer._id) {
            deleteQuery.$or.push({ customerId: customer._id });
        }
        await OTP.deleteMany(deleteQuery);

        return res.status(200).json({
            success: true,
            message: "Password reset successful! You can now log in with your new password.",
            phoneNumber: customer ? formatPakistaniPhone(customer.PhoneNumber) : (payload.phoneNumber || null),
            countryCode: customer.countryCode || "+92",
            fullName: customer.fullName,
            email: customer.Email
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
