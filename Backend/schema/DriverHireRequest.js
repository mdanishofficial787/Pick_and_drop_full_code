const mongoose = require("mongoose");

const DriverHireRequestSchema = new mongoose.Schema(
  {
    requestId: {
      type: String,
      unique: true,
      index: true
    },
    customerId: {
      type: mongoose.Schema.Types.Mixed,
      required: false,
      default: null
    },
    customerName: {
      type: String,
      required: true,
      trim: true
    },
    customerPhone: {
      type: String,
      required: true,
      trim: true
    },
    customerEmail: {
      type: String,
      trim: true,
      lowercase: true
    },
    cnic: {
      type: String,
      required: true,
      trim: true
    },
    bookingDate: {
      type: String,
      required: true
    },
    pickupLocation: {
      type: String,
      required: true,
      trim: true
    },
    dropoffLocation: {
      type: String,
      required: true,
      trim: true
    },
    timeToReach: {
      type: String,
      required: true
    },
    offTime: {
      type: String,
      required: true
    },
    fare: {
      type: Number,
      default: 3500
    },
    status: {
      type: String,
      default: "Pending Dispatch",
      index: true
    },
    assignedDriverId: {
      type: mongoose.Schema.Types.Mixed,
      default: null
    },
    assignedDriverName: {
      type: String,
      default: null
    },
    notes: {
      type: String,
      default: ""
    }
  },
  {
    timestamps: true
  }
);

// Pre-save hook to generate sequential requestId like HDR-8001
DriverHireRequestSchema.pre("save", async function () {
  if (!this.requestId) {
    try {
      const latest = await this.constructor.findOne().sort({ createdAt: -1 });
      if (latest && latest.requestId && latest.requestId.startsWith("HDR-")) {
        const lastNum = parseInt(latest.requestId.replace("HDR-", ""), 10);
        if (!isNaN(lastNum)) {
          this.requestId = `HDR-${lastNum + 1}`;
        } else {
          this.requestId = `HDR-${8000 + Math.floor(100 + Math.random() * 900)}`;
        }
      } else {
        this.requestId = "HDR-8001";
      }
    } catch (err) {
      this.requestId = `HDR-${Date.now().toString().slice(-4)}`;
    }
  }
});

module.exports = mongoose.model("DriverHireRequest", DriverHireRequestSchema);
