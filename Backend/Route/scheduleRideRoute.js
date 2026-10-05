const express = require("express");
const router = express.Router();
const {
  createScheduleRide,
  getAllScheduleRides,
  getCustomerScheduleRides,
  dispatchScheduleRide,
  updateScheduleRide
} = require("../Controller/ScheduleRideController");

// Customer booking
router.post("/", createScheduleRide);
router.get("/customer", getCustomerScheduleRides);

// Admin Console
router.get("/", getAllScheduleRides);
router.patch("/:id/dispatch", dispatchScheduleRide);
router.post("/:id/dispatch", dispatchScheduleRide);
router.patch("/:id", updateScheduleRide);
router.put("/:id", updateScheduleRide);

module.exports = router;
