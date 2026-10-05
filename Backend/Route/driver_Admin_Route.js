const express = require("express");
const router = express.Router();

const adminAuth = require("../Middleware/admin_auth");

const {
    getPendingDrivers,
    getAllDrivers,
    getVerifiedDrivers,
    getRejectedDrivers,
    updateVerificationStatus,
    getPendingVehicles,
    getAllVehicles,
    getVerifiedVehicles,
    getRejectedVehicles,
    updateVehicleVerificationStatus,
    exportDriversCSV,
    exportVehiclesCSV,
    getPendingPasswordResets,
    updatePasswordResetStatus,
} = require("../Controller/Admincontroller");

// All routes below require a valid admin JWT (Authorization: Bearer <token>)
router.use(adminAuth);

// DRIVER ROUTES
router.get("/driver/export", exportDriversCSV);
router.get("/driver/pending", getPendingDrivers);
router.get("/driver", getAllDrivers);
router.get("/driver/verified", getVerifiedDrivers);
router.get("/driver/rejected", getRejectedDrivers);
router.patch("/driver/:id/verification", updateVerificationStatus);

// VEHICLE ROUTES
router.get("/vehicle/export", exportVehiclesCSV);
router.get("/vehicle/pending", getPendingVehicles);
router.get("/vehicle", getAllVehicles);
router.get("/vehicle/verified", getVerifiedVehicles);
router.get("/vehicle/rejected", getRejectedVehicles);
router.patch("/vehicle/:id/verification", updateVehicleVerificationStatus);

// PASSWORD RESET ROUTES
router.get("/password-resets/pending", getPendingPasswordResets);
router.patch("/password-resets/:id/status", updatePasswordResetStatus);

module.exports = router;
