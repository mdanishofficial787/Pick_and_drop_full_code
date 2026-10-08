const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const Driver = require("../schema/Driver");
const PasswordResetRequest = require("../schema/PasswordResetRequest");

const resetPassword = async (req, res) => {
    try {
        const {
            resetToken,
            NewPassword,
            ConfirmPassword,
        } = req.body;

        if (!resetToken || !NewPassword || !ConfirmPassword) {
            return res.status(400).json({
                success: false,
                message:
                    "resetToken, NewPassword and ConfirmPassword are required",
            });
        }

        if (NewPassword !== ConfirmPassword) {
            return res.status(400).json({
                success: false,
                message:
                    "New password and confirm password do not match",
            });
        }

        let payload;
        try {
            payload = jwt.verify(resetToken, process.env.JWT_SECRET);
        } catch (err) {
            return res.status(400).json({
                success: false,
                message: "Reset link expired or invalid."
            });
        }

        if (payload.purpose !== "password_reset") {
            return res.status(400).json({
                success: false,
                message: "Invalid reset token"
            });
        }

        const driver = await Driver.findById(payload.id);

        if (!driver) {
            return res.status(404).json({
                success: false,
                message: "Driver account not found",
            });
        }

        const hashedPassword = await bcrypt.hash(
            NewPassword,
            10
        );

        driver.Password = hashedPassword;
        await driver.save();

        await PasswordResetRequest.deleteMany({
            email: driver.Email, userType: "Driver"
        });

        const token = jwt.sign(
            {
                id: driver._id.toString(),
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "7d",
            }
        );

        const driverResponse = driver.toObject();
        delete driverResponse.Password;

        return res.status(200).json({
            success: true,
            message: "Password reset successfully",
            token,
            driver: driverResponse,
        });

    } catch (error) {
        console.error(
            "Reset Password Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Server error",
            error: error.message,
        });
    }
};

module.exports = {
    resetPassword,
};
