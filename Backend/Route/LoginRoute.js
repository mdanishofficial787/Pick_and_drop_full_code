const express = require("express");
const router = express.Router();

const loginController = require("../Controller/Login");


// Normal login
router.post(
    "/login",
    loginController.login
);


// Google signup / login
router.post(
    "/google",
    loginController.googleSignup
);


module.exports = router;
