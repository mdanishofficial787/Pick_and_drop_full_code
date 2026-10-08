const { OAuth2Client } = require("google-auth-library");
const jwt = require("jsonwebtoken");
const Customer = require("../schema/user");

const client = new OAuth2Client(
    process.env.GOOGLE_CLIENT_ID
);

module.exports.googleSignup = async (req, res) => {
    try {
        const { accessToken } = req.body;

        console.log("Google authentication: ACCESS TOKEN");

        // -----------------------------------
        // 1. Check access token
        // -----------------------------------

        if (!accessToken) {
            return res.status(400).json({
                success: false,
                message: "Google access token is required"
            });
        }

        // -----------------------------------
        // 2. Verify Google access token
        // -----------------------------------

        const tokenInfo = await client.getTokenInfo(accessToken);

console.log("========== GOOGLE TOKEN DEBUG ==========");
console.log("Token audience:", tokenInfo.aud);
console.log("Backend GOOGLE_CLIENT_ID:", process.env.GOOGLE_CLIENT_ID);
console.log("Audience matches:", tokenInfo.aud === process.env.GOOGLE_CLIENT_ID);
console.log("Token scopes:", tokenInfo.scope);
console.log("Token expires:", tokenInfo.exp);
console.log("========================================");

        // -----------------------------------
        // 3. Check Google Client ID
        // -----------------------------------

        if (tokenInfo.aud !== process.env.GOOGLE_CLIENT_ID) {
            return res.status(401).json({
                success: false,
                message: "Invalid Google client ID"
            });
        }

        // -----------------------------------
        // 4. Get Google user information
        // -----------------------------------

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

        // -----------------------------------
        // 5. Extract user information
        // -----------------------------------

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

        const normalizedEmail = email.toLowerCase();

        // -----------------------------------
        // 6. Find existing customer
        // -----------------------------------

        let customer = await Customer.findOne({
            $or: [
                { Email: normalizedEmail },
                { googleId: googleId }
            ]
        });

        let isNewCustomer = false;

        // -----------------------------------
        // 7. Create new customer
        // -----------------------------------

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

            // -----------------------------------
            // Existing customer
            // -----------------------------------

            let isModified = false;

            if (!customer.googleId) {
                customer.googleId = googleId;
                isModified = true;
            }

            if (!customer.isVerified) {
                customer.isVerified = true;
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

        // -----------------------------------
        // 8. Generate application JWT
        // -----------------------------------

        const token = jwt.sign(
            {
                customerId: customer._id,
                email: customer.Email
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "7d"
            }
        );

        // -----------------------------------
        // 9. Send response
        // -----------------------------------

        return res.status(
            isNewCustomer ? 201 : 200
        ).json({
            success: true,

            message: isNewCustomer
                ? "Google signup successful"
                : "Google login successful",

            token,

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
