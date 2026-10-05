const mongoose = require("mongoose");

const TravelTourismRequestSchema = new mongoose.Schema(
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
    passengerName: {
      type: String,
      required: true,
      trim: true
    },
    passengerPhone: {
      type: String,
      required: true,
      trim: true
    },
    passengerEmail: {
      type: String,
      trim: true,
      lowercase: true
    },
    cnic: {
      type: String,
      required: true,
      trim: true
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
    travelDate: {
      type: String,
      required: true
    },
    travelTime: {
      type: String,
      default: "09:00 AM"
    },
    returnDate: {
      type: String,
      default: ""
    },
    returnTime: {
      type: String,
      default: ""
    },
    returnPickupLocation: {
      type: String,
      default: ""
    },
    returnDropoffLocation: {
      type: String,
      default: ""
    },
    vehicleType: {
      type: String,
      default: "SUV"
    },
    acPreference: {
      type: String,
      default: "AC"
    },
    passengersCount: {
      type: Number,
      default: 4
    },
    fare: {
      type: Number,
      default: 15000
    },
    fareStatus: {
      type: String,
      default: "Pending"
    },
    notes: {
      type: String,
      default: ""
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
    assignedDriverDetails: {
      type: mongoose.Schema.Types.Mixed,
      default: null
    },
    requestType: {
      type: String,
      default: "Travel & Tourism"
    }
  },
  {
    timestamps: true
  }
);

// Pre-save hook: TT-7001+
TravelTourismRequestSchema.pre("save", async function () {
  if (!this.requestId) {
    try {
      const all = await this.constructor.find({}, { requestId: 1 }).lean();
      let maxNum = 7000;
      all.forEach((r) => {
        if (r.requestId && r.requestId.startsWith("TT-")) {
          const n = parseInt(r.requestId.replace("TT-", ""), 10);
          if (!isNaN(n) && n > maxNum) maxNum = n;
        }
      });
      this.requestId = `TT-${maxNum + 1}`;
    } catch (_) {
      this.requestId = `TT-${7001 + Math.floor(Math.random() * 100)}`;
    }
  }
});

module.exports = mongoose.model("TravelTourismRequest", TravelTourismRequestSchema);
