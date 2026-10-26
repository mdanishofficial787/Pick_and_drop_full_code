const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const Driver = require("../schema/Driver");

const loginDriver = async (req, res) => {
    try {
        const {
            CountryCode,
            PhoneNumber,
            Password,
        } = req.body;

        if (
            !PhoneNumber ||
            !Password
        ) {
            return res.status(400).json({
                success: false,
                message:
                    "Phone number and password are required",
            });
        }

        const cleanCountryCode = (CountryCode || "+92").toString().trim();
        const rawPhone = (PhoneNumber || "").toString().trim();

        // Flexible phone matching - support with/without 0, with/without country code, and email
        const digitsOnly = rawPhone.replace(/\D/g, "");
        const core = digitsOnly.replace(/^92/, "").replace(/^0/, "");
        const phoneVariants = Array.from(new Set([
            rawPhone,
            digitsOnly,
            core,
            "0" + core,
            "+92" + core,
            "92" + core,
            cleanCountryCode + core
        ])).filter(Boolean);
        const escapedRaw = rawPhone.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

        const driver = await Driver.findOne({
            $or: [
                { PhoneNumber: { $in: phoneVariants } },
                {
                    CountryCode: { $in: ["+92", "92", cleanCountryCode] },
                    PhoneNumber: { $in: phoneVariants }
                },
                { Email: rawPhone.toLowerCase() },
                { Email: { $regex: new RegExp('^' + escapedRaw + '$', 'i') } }
            ]
        });

        if (!driver) {
            return res.status(401).json({
                success: false,
                message: "Invalid phone number or password",
            });
        }

        let isPasswordValid = await bcrypt.compare(
            Password,
            driver.Password
        );
        if (!isPasswordValid && typeof Password === "string" && Password.trim() !== Password) {
            isPasswordValid = await bcrypt.compare(Password.trim(), driver.Password);
        }

        if (!isPasswordValid) {
            return res.status(401).json({
                success: false,
                message: "Invalid phone number or password",
            });
        }

        if (
            driver.verificationStatus !== "Approved" &&
            driver.verificationStatus !== "Verified"
        ) {
            return res.status(403).json({
                success: false,
                isApproved: false,
                verificationStatus: driver.verificationStatus,
                message:
                    "Your account is pending admin verification. You cannot login until your account is approved.",
            });
        }

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
            message: "Login successful",
            isApproved: true,
            verificationStatus: driver.verificationStatus,
            token,
            driver: driverResponse,
        });
    } catch (error) {
        console.error("Login Driver Error:", error);

        return res.status(500).json({
            success: false,
            message: "Server error",
            error: error.message,
        });
    }
};

module.exports = {
    loginDriver,
};
