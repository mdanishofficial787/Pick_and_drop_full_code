const mongoose = require("mongoose");

const RouteCustomerSchema = new mongoose.Schema({
  requestId: { type: String, default: "" },
  customerId: { type: mongoose.Schema.Types.Mixed, default: null },
  customerName: { type: String, required: true },
  phone: { type: String, default: "" },
  email: { type: String, default: "" },
  pickupLocation: { type: String, required: true },
  dropoffLocation: { type: String, required: true },
  time: { type: String, default: "" },
  fare: { type: Number, default: 9500 },
  fareFormatted: { type: String, default: "Rs. 9,500" },
  vehicleType: { type: String, default: "Sedan" },
  status: { type: String, default: "Pending Acceptance" }, // "Pending Acceptance" | "ACCEPTED"
});

const SuggestedRouteSchema = new mongoose.Schema(
  {
    routeId: { type: String, unique: true, index: true },
    routeName: { type: String, required: true }, // e.g. "Route A", "Route B", "Route C"
    pickupPoint: { type: String, default: "Pickup Point" },
    dropoffPoint: { type: String, default: "Drop Point" },
    timeRange: { type: String, default: "7:00 AM - 9:00 AM" }, // e.g. "7:00 AM - 9:00 AM"
    customerCount: { type: Number, default: 0 },
    customers: [RouteCustomerSchema],
    driverId: { type: String, default: null },
    isPreferred: { type: Boolean, default: false },
    status: { type: String, default: "Pending" }, // "Pending" | "ACCEPTED"
    acceptedAt: { type: Date, default: null },
    acceptedByDriver: { type: String, default: null },
  },
  { timestamps: true }
);

module.exports = mongoose.model("SuggestedRoute", SuggestedRouteSchema);
