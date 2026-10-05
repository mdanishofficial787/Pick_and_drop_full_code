const Customer = require("../schema/user");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const { OAuth2Client } = require("google-auth-library");

const googleClient = new OAuth2Client(
    process.env.GOOGLE_CLIENT_ID
);


// =====================================================
// NORMAL PHONE + PASSWORD LOGIN
// =====================================================

module.exports.login = async (req, res) => {
    try {
        const {
            PhoneNumber,
            countryCode,
            Password
        } = req.body;

        // 1. Validate required fields
        if (!PhoneNumber || !Password) {
            return res.status(400).json({
                success: false,
                message: "Phone number and password are required"
            });
        }

        // 2. Find customer
        const customer = await Customer.findOne({
            PhoneNumber: PhoneNumber.trim()
        });

        // 3. Customer doesn't exist
        if (!customer) {
            return res.status(401).json({
                success: false,
                message: "Invalid phone number or password"
            });
        }

        // 4. Check verification
        if (!customer.isVerified) {
            return res.status(403).json({
                success: false,
                message: "Please verify your account before logging in"
            });
        }

        // 5. Check password exists
        if (!customer.Password) {
            return res.status(401).json({
                success: false,
                message: "This account does not use password login"
            });
        }

        // 6. Compare password
        const isPasswordCorrect = await bcrypt.compare(
            Password,
            customer.Password
        );

        // 7. Wrong password
        if (!isPasswordCorrect) {
            return res.status(401).json({
                success: false,
                message: "Invalid phone number or password"
            });
        }

        // 8. Generate JWT
        const token = jwt.sign(
            {
                id: customer._id,
                email: customer.Email,
                phoneNumber: customer.PhoneNumber
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "7d"
            }
        );

        // 9. Successful login
        return res.status(200).json({
            success: true,
            message: "Login successful",
            token: token,
            customer: {
                id: customer._id,
                fullName: customer.fullName,
                Email: customer.Email,
                phoneNumber: customer.PhoneNumber,
                countryCode: customer.countryCode,
                isVerified: customer.isVerified,
                photo: customer.CustomerPhoto?.url || null
            }
        });

    } catch (error) {
        console.error("Login Error:", error);

        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: error.message
        });
    }
};



// =====================================================
// GOOGLE SIGNUP / LOGIN
// =====================================================

module.exports.googleSignup = async (req, res) => {
    try {

        const { accessToken } = req.body;

        console.log("Google authentication: ACCESS TOKEN");


        // -------------------------------------------------
        // 1. Check access token
        // -------------------------------------------------

        if (!accessToken) {
            return res.status(400).json({
                success: false,
                message: "Google access token is required"
            });
        }


        // -------------------------------------------------
        // 2. Verify access token with Google
        // -------------------------------------------------

        const tokenInfo = await googleClient.getTokenInfo(
            accessToken
        );

        console.log("Google token info:", tokenInfo);


        // -------------------------------------------------
        // 3. Verify client ID
        // -------------------------------------------------

        if (
            tokenInfo.aud !==
            process.env.GOOGLE_CLIENT_ID
        ) {
            return res.status(401).json({
                success: false,
                message: "Invalid Google client ID"
            });
        }


        // -------------------------------------------------
        // 4. Get Google user information
        // -------------------------------------------------

        const googleResponse = await fetch(
            "https://www.googleapis.com/oauth2/v3/userinfo",
            {
                headers: {
                    Authorization: `Bearer ${accessToken}`
                }
            }
        );


        if (!googleResponse.ok) {
            return res.status(401).json({
                success: false,
                message: "Unable to get Google user information"
            });
        }


        const googleUser = await googleResponse.json();

        console.log("Google user:", googleUser);


        // -------------------------------------------------
        // 5. Extract Google information
        // -------------------------------------------------

        const googleId = googleUser.sub;
        const email = googleUser.email;
        const fullName = googleUser.name || "Google User";
        const profilePicture = googleUser.picture || null;


        if (!email) {
            return res.status(400).json({
                success: false,
                message: "Google account email not found"
            });
        }


        const normalizedEmail =
            email.toLowerCase();


        // -------------------------------------------------
        // 6. Find existing customer
        // -------------------------------------------------

        let customer = await Customer.findOne({
            $or: [
                {
                    Email: normalizedEmail
                },
                {
                    googleId: googleId
                }
            ]
        });


        let isNewCustomer = false;


        // -------------------------------------------------
        // 7. Create new Google customer
        // -------------------------------------------------

        if (!customer) {

            customer = await Customer.create({

                fullName: fullName,

                Email: normalizedEmail,

                googleId: googleId,

                SignupMethod: "Google",

                CustomerPhoto: {
                    url: profilePicture
                },

                isVerified: true
            });

            isNewCustomer = true;

            console.log(
                "New Google customer created:",
                customer._id
            );

        } else {

            // -------------------------------------------------
            // 8. Existing customer
            // -------------------------------------------------

            let isModified = false;


            // Link Google account
            if (!customer.googleId) {
                customer.googleId = googleId;
                isModified = true;
            }


            // Google email is verified
            if (!customer.isVerified) {
                customer.isVerified = true;
                isModified = true;
            }


            // Update Google profile picture if empty
            if (
                !customer.CustomerPhoto?.url &&
                profilePicture
            ) {
                customer.CustomerPhoto = {
                    url: profilePicture
                };

                isModified = true;
            }


            if (isModified) {
                await customer.save();
            }


            console.log(
                "Existing customer logged in:",
                customer._id
            );
        }


        // -------------------------------------------------
        // 9. Generate your application's JWT
        // -------------------------------------------------

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


        // -------------------------------------------------
        // 10. Send response
        // -------------------------------------------------

        return res.status(
            isNewCustomer ? 201 : 200
        ).json({

            success: true,

            message: isNewCustomer
                ? "Google signup successful"
                : "Google login successful",

            token: token,

            customer: {
                id: customer._id,
                fullName: customer.fullName,
                Email: customer.Email,
                SignupMethod: customer.SignupMethod,
                isVerified: customer.isVerified,
                photo:
                    customer.CustomerPhoto?.url || null
            }
        });


    } catch (error) {

        console.error(
            "Google Auth Error:",
            error
        );

        return res.status(401).json({
            success: false,
            message: "Google authentication failed",
            error: error.message
        });
    }
};