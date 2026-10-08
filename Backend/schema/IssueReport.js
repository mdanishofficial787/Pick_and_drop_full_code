const mongoose = require("mongoose");

const issueReportSchema = new mongoose.Schema(
  {
    driver: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Driver",
      default: null,
    },
    driverName: {
      type: String,
      default: "Driver",
    },
    fromDate: {
      type: Date,
      default: Date.now,
    },
    toDate: {
      type: Date,
      default: Date.now,
    },
    fromTime: {
      type: String,
      default: "",
    },
    toTime: {
      type: String,
      default: "",
    },
    reason: {
      type: String,
      required: true,
      default: "Vehicle Issue",
    },
    details: {
      type: String,
      default: "",
    },
    // Associated Customer and Trip details (if reported for a specific request)
    requestId: {
      type: String,
      default: "",
    },
    customerName: {
      type: String,
      default: "",
    },
    customerPhone: {
      type: String,
      default: "",
    },
    pickupLocation: {
      type: String,
      default: "",
    },
    dropoffLocation: {
      type: String,
      default: "",
    },
    fare: {
      type: String,
      default: "",
    },
    ride: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Ride",
      default: null,
    },
    status: {
      type: String,
      enum: ["Pending", "In Review", "Resolved", "Dismissed"],
      default: "Pending",
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("IssueReport", issueReportSchema);
