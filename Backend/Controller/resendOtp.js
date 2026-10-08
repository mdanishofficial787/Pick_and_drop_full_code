const Customer = require("../schema/user");
const OTP = require("../schema/otp");
const bcrypt = require("bcrypt");
const sendOTPEmail = require("../utils/Email");

module.exports.resendOTP = async (req, res) => {
    try {
        const { email } = req.body;

if (!email) {
    return res.status(400).json({
        success: false,
        message: "Email is required"
    });
}

const customer = await Customer.findOne({
    Email: email
});

        if (!customer) {
            return res.status(404).json({
                success: false,
                message: "Customer not found"
            });
        }

        // Check if already verified
        if (customer.isVerified) {
            return res.status(400).json({
                success: false,
                message: "Customer is already verified"
            });
        }

        // Find OTP record
        const otpData = await OTP.findOne({
            customerId: customer._id
        });

        if (!otpData) {
            return res.status(404).json({
                success: false,
                message: "OTP record not found"
            });
        }

        const now = new Date();

        // 3 seconds cooldown
        if (
            otpData.lastResendAt &&
            now - otpData.lastResendAt < 3 * 1000
        ) {
            return res.status(429).json({
                success: false,
                message: "Please wait 3 seconds before requesting another OTP."
            });
        }

        // Reset resend count after 10 minutes
        if (
            otpData.lastResendAt &&
            now - otpData.lastResendAt >= 10 * 60 * 1000
        ) {
            otpData.resendCount = 0;
        }

        // Maximum 3 resend attempts within 10 minutes
        if (otpData.resendCount >= 3) {
            return res.status(429).json({
                success: false,
                message: "Resend limit exceeded. Please try again after 10 minutes."
            });
        }

        // Generate new OTP
        const newOTP = Math.floor(
            100000 + Math.random() * 900000
        ).toString();

        // Hash OTP
        const hashedOTP = await bcrypt.hash(newOTP, 10);

        // OTP expires after 5 minutes
        const otpExpiresAt = new Date(
            now.getTime() + 5 * 60 * 1000
        );

        // Update OTP record
        otpData.otp = hashedOTP;
        otpData.otpExpiresAt = otpExpiresAt;
        otpData.otpAttempts = 0;
        otpData.resendCount += 1;
        otpData.lastResendAt = now;

        await otpData.save();

await sendOTPEmail(
    customer.Email,
    newOTP
);

console.log(
    "New OTP sent to:",
    customer.Email
);

        // Testing purpose
        console.log("New OTP:", newOTP);

        return res.status(200).json({
            success: true,
            message: "OTP resent successfully",
            data: {
                otpExpiresAt: otpExpiresAt
            }
        });

    } catch (err) {
        console.log("Resend OTP Error:", err);

        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: err.message
        });
    }
};
