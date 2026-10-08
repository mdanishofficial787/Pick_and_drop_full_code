const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");
const Driver = require("../schema/Driver");

module.exports = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader) {
      return res.status(401).json({
        success: false,
        isLoggedIn: false,
        message: "No token provided",
      });
    }

    let token = authHeader.trim();

    if (/^Bearer\s+/i.test(token)) {
      token = token.replace(/^Bearer\s+/i, "").trim();
    }

    if (!token) {
      return res.status(401).json({
        success: false,
        isLoggedIn: false,
        message: "Invalid authorization format",
      });
    }

    if (!process.env.JWT_SECRET) {
      return res.status(500).json({
        success: false,
        message: "JWT_SECRET is not configured",
      });
    }

    let decoded;
    try {
      decoded = jwt.verify(token, process.env.JWT_SECRET);
    } catch (jwtError) {
      return res.status(401).json({
        success: false,
        isLoggedIn: false,
        message: "Invalid or expired token",
      });
    }

    const driverId = decoded.id;

    if (!driverId) {
      return res.status(401).json({
        success: false,
        isLoggedIn: false,
        message: "Token does not contain driver ID",
      });
    }

    if (!mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(401).json({
        success: false,
        isLoggedIn: false,
        message: "Invalid driver ID in token",
      });
    }

    const driver = await Driver.findById(driverId);

    if (!driver) {
      return res.status(401).json({
        success: false,
        isLoggedIn: false,
        message: "Driver not found",
      });
    }

    req.user = {
      id: driver._id.toString(),
      driver: driver,
    };

    next();
  } catch (error) {
    console.error("Auth Middleware Error:", error.message);

    return res.status(401).json({
      success: false,
      isLoggedIn: false,
      message: "Session expired or invalid token",
    });
  }
};
