const express = require("express");
const router = express.Router();

const driverAuth = require("../Middleware/driver_auth");

const {
  vehicleCreateUpload,
  vehicleUpdateUpload,
} = require("../Middleware/vehicle_upload");

const validateVehicle = require("../Middleware/vehicle_Validation");

const {
  createVehicle,
  getVehicles,
  getVehicleById,
  deleteVehicle,
} = require("../Controller/Vehicle_controller");

const {
  updateVehicle,
} = require("../Controller/update_vehicle");

// 1. CREATE VEHICLE
router.post(
  "/register",
  driverAuth,
  vehicleCreateUpload,
  validateVehicle,
  createVehicle
);

// 2. UPDATE VEHICLE
router.patch(
  "/:id",
  driverAuth,
  vehicleUpdateUpload,
  validateVehicle,
  updateVehicle
);

// 3. GET ALL VEHICLES
router.get(
  "/",
  driverAuth,
  getVehicles
);

// 4. GET VEHICLE BY ID
router.get(
  "/:id",
  driverAuth,
  getVehicleById
);

// 5. DELETE VEHICLE
router.delete(
  "/:id",
  driverAuth,
  deleteVehicle
);

module.exports = router;
