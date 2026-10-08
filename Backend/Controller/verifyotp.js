const Customer = require("../schema/user");
const OTP = require("../schema/otp");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");



    module.exports.verifyOTP = async (req, res) => {
    try {
        const { email, otp } = req.body;

        // ==========================================
        // 1. Required Fields
        // ==========================================

        if (!email || !otp) {
            return res.status(400).json({
                success: false,
                message: "Email and OTP are required"
            });
        }

        // ==========================================
        // 2. Find Customer by Email
        // ==========================================

        const customer = await Customer.findOne({
            Email: email
        });

        if (!customer) {
            return res.status(404).json({
                success: false,
                message: "Customer not found"
            });
        }

        // ==========================================
        // 3. Check Already Verified
        // ==========================================

        if (customer.isVerified === true) {
            return res.status(400).json({
                success: false,
                message: "Customer is already verified"
            });
        }

        // ==========================================
        // 4. Find Latest OTP
        // ==========================================

        const otpData = await OTP.findOne({
            customerId: customer._id
        }).sort({
            createdAt: -1
        });

        if (!otpData) {
            return res.status(404).json({
                success: false,
                message: "OTP not found"
            });
        }

        // ==========================================
        // 5. Maximum Attempts Check
        // ==========================================

        if (otpData.otpAttempts >= 3) {
            return res.status(400).json({
                success: false,
                message: "Maximum OTP attempts exceeded"
            });
        }

        // ==========================================
        // 6. OTP Expiry Check
        // ==========================================

        if (
            !otpData.otpExpiresAt ||
            new Date() > otpData.otpExpiresAt
        ) {
            return res.status(400).json({
                success: false,
                message: "OTP expired"
            });
        }

        // ==========================================
        // 7. Compare OTP
        // ==========================================

        const isMatch = await bcrypt.compare(
            otp.toString(),
            otpData.otp
        );

        // ==========================================
        // 8. Invalid OTP
        // ==========================================

        if (!isMatch) {
            otpData.otpAttempts += 1;

            await otpData.save();

            if (otpData.otpAttempts >= 3) {
                return res.status(400).json({
                    success: false,
                    message: "Maximum OTP attempts exceeded"
                });
            }

            return res.status(400).json({
                success: false,
                message: "Invalid OTP"
            });
        }

        // ==========================================
        // 9. Mark Customer as Verified
        // ==========================================

        customer.isVerified = true;

console.log("BEFORE SAVE:");
console.log("Customer ID:", customer._id);
console.log("Customer Email:", customer.Email);
console.log("isVerified:", customer.isVerified);

const savedCustomer = await customer.save();

console.log("AFTER SAVE:");
console.log("Customer ID:", savedCustomer._id);
console.log("Customer Email:", savedCustomer.Email);
console.log("isVerified:", savedCustomer.isVerified);
        // ==========================================
        // 10. Mark OTP as Verified
        // ==========================================

        otpData.verified = true;

        await otpData.save();

        // ==========================================
        // 11. Delete OTP
        // ==========================================

        await OTP.findByIdAndDelete(
            otpData._id
        );

        // ==========================================
        // 12. Generate JWT Token
        // ==========================================

        const token = jwt.sign(
            {
                id: customer._id,
                email: customer.Email
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "7d"
            }
        );

        // ==========================================
        // 13. Success Response
        // ==========================================

        return res.status(200).json({
            success: true,
            message: "OTP verified successfully",
            token: token,
            customer: {
                id: customer._id,
                fullName: customer.fullName,
                Email: customer.Email,
                phoneNumber: customer.PhoneNumber,
                isVerified: customer.isVerified
            }
        });

    } catch (err) {
        console.log(
            "OTP Verify Error:",
            err
        );

        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: err.message
        });
    }
};
