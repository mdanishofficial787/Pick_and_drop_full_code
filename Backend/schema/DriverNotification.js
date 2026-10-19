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
    driverName: {
      type: String,
      default: ""
    },
    rideId: {
      type: String,
      default: "",
      index: true
    },
    notificationId: {
      type: String,
      default: "",
      index: true
    },
    title: {
      type: String,
      required: true
    },
    subtitle: {
      type: String,
      required: true
    },
    customerName: {
      type: String,
      default: ""
    },
    customerPhone: {
      type: String,
      default: ""
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
    status: {
      type: String,
      default: ""
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
    },
    isDismissed: {
      type: Boolean,
      default: false,
      index: true
    },
    payload: {
      type: mongoose.Schema.Types.Mixed,
      default: {}
    }
  },
  {
    timestamps: true
  }
);

module.exports = mongoose.model("DriverNotification", DriverNotificationSchema);
