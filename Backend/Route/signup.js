const express = require("express");
const router = express.Router();

const signupController = require("../Controller/Signup");
const checkSession = require("../Controller/checkSession");
const checkPhoneController = require("../Controller/checkphone");
const passport = require("passport");
const authMiddleware = require("../Middleware/Authr");

// HERE: Destructure karein uploadSingleImage ko
const { uploadSingleImage } = require("../Multer/imageupload"); 
const googleAuthController = require("../Controller/googleAuth");

const {
  validateSignup
} = require("../Middleware/validationSchema");


// Customer Signup
router.post(
  "/signup",
  uploadSingleImage("CustomerPhoto"), // HERE: Function call karein
  (req, res, next) => {
    next();
  },
  validateSignup,
  signupController.signup
);

// Google Signup / Login
router.post(
  "/google",
  googleAuthController.googleSignup
);

// Check Phone Availability
router.get(
  "/check-phone/:number",
  checkPhoneController.checkPhone
);

// Check Active Session
router.get(
  "/check-session",
  authMiddleware,
  checkSession.checkSession
);

// Update Customer Profile
router.put(
  "/update-profile",
  uploadSingleImage("CustomerPhoto"),
  signupController.updateProfile
);

module.exports = router;