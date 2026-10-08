const express = require("express");
const router = express.Router();
// Signup Page
router.get("/signup", (req, res) => {
    res.render("register");
});
// Login Page
router.get("/login", (req, res) => {
    res.render("login");
});
module.exports = router;
