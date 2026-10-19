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
  dismissCustomerNotification,
  clearAllCustomerNotifications,
  respondToFare,
  getSuggestedRoutes,
  createSuggestedRoute,
  acceptSuggestedRoute,
  setPreferredRoute,
  getDriverNotifications,
  markDriverNotificationRead,
  dismissDriverNotification,
  clearAllDriverNotifications,
  acceptRideByCustomer
} = require("../Controller/RideController");

// Suggested Routes & Match Setup
router.get("/suggested-routes", getSuggestedRoutes);
router.post("/suggested-routes", createSuggestedRoute);
router.post("/accept-route", acceptSuggestedRoute);
router.patch("/suggested-routes/:id/preferred", setPreferredRoute);

// Driver Notifications
router.get("/driver-notifications", getDriverNotifications);
router.patch("/driver-notifications/:id/read", markDriverNotificationRead);
router.post("/driver-notifications/:id/read", markDriverNotificationRead);
router.post("/driver-notifications/:id/dismiss", dismissDriverNotification);
router.delete("/driver-notifications/:id", dismissDriverNotification);
router.post("/driver-notifications/clear-all", clearAllDriverNotifications);

// Customer booking & Ride Acceptance
router.post("/customer-accept", acceptRideByCustomer);
router.post("/:id/customer-accept", acceptRideByCustomer);
router.post("/monthly", createMonthlyRide);
router.post("/", createMonthlyRide);
router.get("/customer", getCustomerRides);
router.get("/customer-notifications", getCustomerNotifications);
router.post("/customer-notifications/:id/dismiss", dismissCustomerNotification);
router.delete("/customer-notifications/:id", dismissCustomerNotification);
router.post("/customer-notifications/clear-all", clearAllCustomerNotifications);
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
