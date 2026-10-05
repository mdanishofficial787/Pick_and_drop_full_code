const mongoose = require("mongoose");

const CustomerNotificationSchema = new mongoose.Schema(
  {
    customerId: {
      type: mongoose.Schema.Types.Mixed,
      required: false,
      default: null,
      index: true
    },
    passengerPhone: {
      type: String,
      required: false,
      index: true
    },
    passengerEmail: {
      type: String,
      required: false
    },
    rideId: {
      type: String,
      required: true,
      index: true
    },
    mongoId: {
      type: String,
      required: false
    },
    notificationId: {
      type: String,
      required: false,
      unique: true,
      sparse: true,
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
    status: {
      type: String,
      required: true
    },
    fareFormatted: {
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
    driverName: {
      type: String,
      default: ""
    },
    driverPhone: {
      type: String,
      default: ""
    },
    driverCode: {
      type: String,
      default: ""
    },
    rating: {
      type: String,
      default: ""
    },
    vehicle: {
      type: String,
      default: ""
    },
    numberPlate: {
      type: String,
      default: ""
    },
    isDriverUnavailable: {
      type: Boolean,
      default: false
    },
    affectedDate: {
      type: String,
      default: ""
    },
    affectedTime: {
      type: String,
      default: ""
    },
    reportedReason: {
      type: String,
      default: ""
    },
    additionalDetails: {
      type: String,
      default: ""
    },
    fareResponseStatus: {
      type: String,
      default: "Pending"
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

module.exports = mongoose.model("CustomerNotification", CustomerNotificationSchema);
