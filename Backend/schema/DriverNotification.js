const mongoose = require("mongoose");

const DriverNotificationSchema = new mongoose.Schema(
  {
    driverId: {
      type: mongoose.Schema.Types.Mixed,
      required: false,
      default: null,
      index: true
    },
    driverReferenceId: {
      type: String,
      required: false,
      default: ""
    },
    title: {
      type: String,
      required: true
    },
    subtitle: {
      type: String,
      required: true
    },
    routeId: {
      type: String,
      default: ""
    },
    routeName: {
      type: String,
      default: ""
    },
    customerCount: {
      type: Number,
      default: 0
    },
    type: {
      type: String,
      default: "ROUTE_NOTIFICATION"
    },
    pickup: {
      type: String,
      default: ""
    },
    destination: {
      type: String,
      default: ""
    },
    timeRange: {
      type: String,
      default: ""
    },
    fareFormatted: {
      type: String,
      default: ""
    },
    isRead: {
      type: Boolean,
      default: false
    }
  },
  {
    timestamps: true
  }
);

module.exports = mongoose.model("DriverNotification", DriverNotificationSchema);
