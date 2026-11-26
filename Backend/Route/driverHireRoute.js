const express = require("express");
const router = express.Router();
const {
  createDriverHireRequest,
  getAllDriverHireRequests,
  dispatchDriverHire,
  updateDriverHire
} = require("../Controller/DriverHireController");

// Customer hire driver booking
router.post("/", createDriverHireRequest);

// Admin Console
router.get("/", getAllDriverHireRequests);
router.patch("/:id/dispatch", dispatchDriverHire);
router.post("/:id/dispatch", dispatchDriverHire);
router.patch("/:id", updateDriverHire);
router.put("/:id", updateDriverHire);
router.patch("/:id/driver-response", updateDriverHire);
router.post("/:id/driver-response", updateDriverHire);
router.put("/:id/driver-response", updateDriverHire);
router.patch("/status/:id", updateDriverHire);
router.put("/status/:id", updateDriverHire);

module.exports = router;
