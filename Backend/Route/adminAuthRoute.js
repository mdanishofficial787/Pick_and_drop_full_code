const express = require("express");
const router = express.Router();

const adminAuth = require("../Middleware/admin_auth");
const { loginAdmin, getAdminProfile } = require("../Controller/AdminAuthController");

// 1. ADMIN LOGIN
router.post("/login", loginAdmin);

// 2. GET LOGGED-IN ADMIN (verify token / restore session in React on refresh)
router.get("/me", adminAuth, getAdminProfile);

module.exports = router;
