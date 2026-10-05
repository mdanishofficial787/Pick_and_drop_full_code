const express = require("express");
const router = express.Router();
const {
  createMonthlyRide,
  getAllRides,
  getRideById,
  dispatchRide,
  getCustomerRides,
  updateRide,
  reportDriverUnavailable,
  requestReplacementDriver,
  getCustomerNotifications,
  respondToFare
} = require("../Controller/RideController");

// Customer booking
router.post("/monthly", createMonthlyRide);
router.post("/", createMonthlyRide);
router.get("/customer", getCustomerRides);
router.get("/customer-notifications", getCustomerNotifications);
router.post("/respond-fare", respondToFare);
router.post("/:id/respond-fare", respondToFare);

// Driver Unavailable & Replacement Requests
router.post("/driver-unavailable", reportDriverUnavailable);
router.post("/:id/driver-unavailable", reportDriverUnavailable);
router.post("/request-replacement", requestReplacementDriver);
router.post("/:id/request-replacement", requestReplacementDriver);

// Admin & Dispatch Console
router.get("/", getAllRides);
router.get("/dispatch-console", getAllRides);
router.get("/:id", getRideById);
router.patch("/:id/dispatch", dispatchRide);
router.post("/:id/dispatch", dispatchRide);
router.patch("/:id", updateRide);
router.put("/:id", updateRide);

module.exports = router;
