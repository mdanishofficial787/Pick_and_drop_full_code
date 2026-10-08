const Driver = require("../schema/Driver");
const PasswordResetRequest = require("../schema/PasswordResetRequest");

const sendForgotPasswordOTP = async (req, res) => {
    try {
        const { Email } = req.body;

        if (!Email) {
            return res.status(400).json({
                success: false,
                message: "Email is required",
            });
        }

        const cleanEmail = Email.toLowerCase().trim();

        const driver = await Driver.findOne({
            $or: [
                { Email: cleanEmail },
                { PhoneNumber: Email.trim() }
            ]
        });

        if (!driver) {
            return res.status(404).json({
                success: false,
                message: "No driver account found with this phone number or email",
            });
        }

        // Check for existing recent requests to enforce 15-minute cooldown
        const existingRequest = await PasswordResetRequest.findOne({
            email: cleanEmail,
            userType: "Driver",
            status: "Pending"
        }).sort({ createdAt: -1 });

        if (existingRequest) {
            const timeSinceLastRequest = Date.now() - new Date(existingRequest.createdAt).getTime();
            const fifteenMinutes = 15 * 60 * 1000;

            if (timeSinceLastRequest < fifteenMinutes) {
                const minutesLeft = Math.ceil((fifteenMinutes - timeSinceLastRequest) / 60000);
                return res.status(429).json({
                    success: false,
                    message: `Please wait ${minutesLeft} minute(s) before sending another request.`,
                });
            }
        }

        // Clear any previous Pending requests that are OLDER than 15 minutes
        await PasswordResetRequest.deleteMany({ email: cleanEmail, userType: "Driver", status: "Pending" });

        // Create a new request for Admin Approval
        await PasswordResetRequest.create({
            email: cleanEmail,
            userType: "Driver",
            status: "Pending"
        });

        console.log("Password reset request sent for admin approval:", cleanEmail);

        return res.status(200).json({
            success: true,
            message: "Request sent to Admin for approval.",
        });
    } catch (error) {
        console.error("Send Forgot Password Request Error:", error);

        return res.status(500).json({
            success: false,
            message: "Server error",
        });
    }
};

const checkPasswordResetStatus = async (req, res) => {
    try {
        const { email } = req.query;

        if (!email) {
            return res.status(400).json({
                success: false,
                message: "Email is required"
            });
        }

        const cleanEmail = email.toLowerCase().trim();

        const request = await PasswordResetRequest.findOne({
            email: cleanEmail,
            userType: "Driver"
        }).sort({ createdAt: -1 });

        if (!request) {
            return res.status(404).json({
                success: false,
                message: "No password reset request found."
            });
        }

        return res.status(200).json({
            success: true,
            status: request.status,
            resetToken: request.resetToken
        });
    } catch (error) {
        console.error("Check Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Server error",
        });
    }
};

module.exports = {
    sendForgotPasswordOTP,
    checkPasswordResetStatus,
};
