const express = require("express");
const router = express.Router();
const {
  createTravelRequest,
  getAllTravelRequests,
  getCustomerTravelRequests,
  dispatchTravelRequest,
  updateTravelRequest
} = require("../Controller/TravelTourismController");

// Customer booking
router.post("/", createTravelRequest);
router.get("/customer", getCustomerTravelRequests);

// Admin Console
router.get("/", getAllTravelRequests);
router.patch("/:id/dispatch", dispatchTravelRequest);
router.post("/:id/dispatch", dispatchTravelRequest);
router.patch("/:id", updateTravelRequest);
router.put("/:id", updateTravelRequest);

module.exports = router;
