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
            !CountryCode ||
            !PhoneNumber ||
            !Password
        ) {
            return res.status(400).json({
                success: false,
                message:
                    "Country code, phone number and password are required",
            });
        }

        const cleanCountryCode = CountryCode.trim();
        let cleanPhoneNumber = PhoneNumber.toString().trim();

        if (cleanPhoneNumber.startsWith(cleanCountryCode)) {
            cleanPhoneNumber = cleanPhoneNumber
                .slice(cleanCountryCode.length)
                .trim();
        }

        if (cleanPhoneNumber.startsWith("0")) {
            cleanPhoneNumber = cleanPhoneNumber.substring(1);
        }

        const driver = await Driver.findOne({
            CountryCode: cleanCountryCode,
            PhoneNumber: cleanPhoneNumber,
        });

        if (!driver) {
            return res.status(401).json({
                success: false,
                message: "Invalid phone number or password",
            });
        }

        const isPasswordValid = await bcrypt.compare(
            Password,
            driver.Password
        );

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
        });
    }
};

module.exports = {
    loginDriver,
};
