const mongoose = require("mongoose");

const PaymentSchema = new mongoose.Schema(
  {
    customerId: {
      type: mongoose.Schema.Types.Mixed,
      ref: "Customer",
      required: false,
      index: true
    },
    customerName: {
      type: String,
      default: "Unknown"
    },
    customerPhone: {
      type: String,
      default: "Unknown",
      index: true
    },
    rideId: {
      type: String,
      required: true,
      index: true
    },
    fare: {
      type: String,
      required: true
    },
    paymentProofUrl: {
      type: String,
      required: false,
      default: ""
    },
    paymentProofId: {
      type: String,
      required: false,
      default: ""
    },
    status: {
      type: String,
      enum: ["PENDING PAYMENT", "PENDING VERIFICATION", "VERIFIED", "REJECTED", "PAID"],
      default: "PENDING PAYMENT"
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
    adminRemarks: {
      type: String,
      default: ""
    }
  },
  { timestamps: true }
);

module.exports = mongoose.model("Payment", PaymentSchema);
