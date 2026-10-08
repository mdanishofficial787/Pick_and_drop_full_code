const express = require("express");
const router = express.Router();

const driverAuth = require("../Middleware/driver_auth");
const driverUpload = require("../Middleware/driverupload");
const { validateDriver, validateDriverUpdate } = require("../Middleware/drivervalidation");

const {
  registerDriver,
  getDrivers,
  getDriverById,
  updateDriver,
  savePreferredRoutes,
  saveAvailability,
  reportIssue,
} = require("../Controller/Driver");

const {
  loginDriver,
} = require("../Controller/driver_login");

// 1. REGISTER DRIVER
router.post(
  "/register",
  driverUpload,
  validateDriver,
  registerDriver
);

// 2. LOGIN DRIVER
router.post(
  "/login",
  loginDriver
);

// 3. GET ALL DRIVERS
router.get(
  "/",
  driverAuth,
  getDrivers
);

// 4. GET DRIVER BY ID
router.get(
  "/:id",
  driverAuth,
  getDriverById
);

// 5. UPDATE DRIVER
router.patch("/:id", driverAuth, driverUpload, validateDriverUpdate, updateDriver);

// 6. SAVE PREFERRED ROUTES
router.post(
  "/preferred-routes",
  savePreferredRoutes
);

// 7. SAVE AVAILABILITY
router.post(
  "/availability",
  saveAvailability
);

// 8. GET AVAILABILITY (No Auth Required for Frontend retrieval)
router.get(
  "/:id/availability",
  async (req, res) => {
    try {
      const driver = await require("../schema/Driver").findById(req.params.id).select("availability");
      if (!driver) return res.status(404).json({ success: false, message: "Driver not found" });
      return res.status(200).json({ success: true, availability: driver.availability });
    } catch(err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }
);

// 9. REPORT AN ISSUE
router.post(
  "/report-issue",
  reportIssue
);
router.post(
  "/report_issue",
  reportIssue
);
router.post(
  "/issue",
  reportIssue
);

module.exports = router;
