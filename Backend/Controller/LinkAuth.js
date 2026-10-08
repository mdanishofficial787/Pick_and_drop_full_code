const axios = require("axios");
const jwt = require("jsonwebtoken");
const User = require("../schema/user"); // Apne User Schema Model ka path verify karein

/**
 * 1. User ko LinkedIn Auth Page par redirect karne ka URL
 */
module.exports.redirectToLinkedIn = (req, res) => {
  const rootUrl = "https://www.linkedin.com/oauth/v2/authorization";
  const options = {
    response_type: "code",
    client_id: process.env.LINKEDIN_CLIENT_ID,
    redirect_uri: process.env.LINKEDIN_REDIRECT_URI,
    state: "random_state_string",
    scope: "openid profile email" // Standard OpenID Connect scopes
  };

  const queryString = new URLSearchParams(options).toString();
  return res.redirect(`${rootUrl}?${queryString}`);
};

/**
 * 2. LinkedIn Callback URL (Code exchange -> User Details -> Signup/Login -> JWT Token)
 */
module.exports.linkedinCallback = async (req, res) => {
  const { code } = req.query;

  if (!code) {
    return res.status(400).json({ success: false, message: "Authorization code missing" });
  }

  try {
    // A) Authorization Code ke badle Access Token lein
    const tokenResponse = await axios.post(
      "https://www.linkedin.com/oauth/v2/accessToken",
      new URLSearchParams({
        grant_type: "authorization_code",
        code: code,
        redirect_uri: process.env.LINKEDIN_REDIRECT_URI,
        client_id: process.env.LINKEDIN_CLIENT_ID,
        client_secret: process.env.LINKEDIN_CLIENT_SECRET
      }),
      {
        headers: { "Content-Type": "application/x-www-form-urlencoded" }
      }
    );

    const accessToken = tokenResponse.data.access_token;

    // B) Access Token se User ki details fetch karein
    const userResponse = await axios.get("https://api.linkedin.com/v2/userinfo", {
      headers: {
        Authorization: `Bearer ${accessToken}`
      }
    });

    const { sub: linkedinId, name, email, picture } = userResponse.data;

    // C) SIGNUP / LOGIN LOGIC: Check karein user DB mein hai ya nahi
    let user = await User.findOne({ $or: [{ linkedinId }, { email }] });

    if (!user) {
      // User exist nahi karta -> Naya User Signup karein
      user = new User({
        name: name,
        email: email,
        linkedinId: linkedinId,
        CustomerPhoto: { url: picture, public_id: null }
      });
      await user.save();
    } else if (!user.linkedinId) {
      // Email pehle se exist karti hai lekin LinkedIn linked nahi tha -> LinkedIn ID attach karein
      user.linkedinId = linkedinId;
      await user.save();
    }

    // D) JWT Auth Token Generate karein
    const token = jwt.sign(
      { _id: user._id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );

    return res.status(200).json({
      success: true,
      message: "LinkedIn authentication successful",
      token: token,
      user: user
    });

  } catch (error) {
    console.error("LinkedIn OAuth Error:", error.response?.data || error.message);
    return res.status(500).json({
      success: false,
      message: "LinkedIn authentication failed",
      error: error.message
    });
  }
};
