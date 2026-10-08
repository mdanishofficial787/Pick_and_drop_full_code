const express = require("express");
const router = express.Router();
const { redirectToLinkedIn, linkedinCallback } = require("../Controller/linkedinAuth");

// User browser mein is endpoint par jayega redirect hone ke liye
router.get("/linkedin", redirectToLinkedIn);

// LinkedIn callback response yahan aayega
router.get("/linkedin/callback", linkedinCallback);

module.exports = router;
