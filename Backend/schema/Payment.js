const mongoose = require("mongoose");

const PaymentSchema = new mongoose.Schema(
  {
    customerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Customer",
      required: true,
      index: true
    },
    customerName: {
      type: String,
      default: "Unknown"
    },
    customerPhone: {
      type: String,
      default: "Unknown"
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
      required: true
    },
    paymentProofId: {
      type: String,
      required: true
    },
    status: {
      type: String,
      enum: ["PENDING VERIFICATION", "VERIFIED", "REJECTED"],
      default: "PENDING VERIFICATION"
    },
    adminRemarks: {
      type: String,
      default: ""
    }
  },
  { timestamps: true }
);

module.exports = mongoose.model("Payment", PaymentSchema);
