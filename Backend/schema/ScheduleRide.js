const mongoose = require("mongoose");

const ScheduleRideSchema = new mongoose.Schema(
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
    startingFrom: {
      type: String,
      required: true
    },
    timeToReach: {
      type: String,
      default: "08:30 AM"
    },
    timeToLeave: {
      type: String,
      default: "05:00 PM"
    },
    rideType: {
      type: String,
      default: "One Way" // "One Way" or "Two Way"
    },
    vehicleType: {
      type: String,
      default: "Sedan Executive"
    },
    acPreference: {
      type: String,
      default: "AC"
    },
    genderPreference: {
      type: String,
      default: "Both"
    },
    fare: {
      type: Number,
      default: 7500
    },
    fareStatus: {
      type: String,
      default: "Pending"
    },
    notes: {
      type: String,
      default: ""
    },
    customSchedule: {
      type: mongoose.Schema.Types.Mixed,
      default: {}
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
      default: "Schedule Ride"
    }
  },
  {
    timestamps: true
  }
);

// Pre-save hook: SCH-9001+
ScheduleRideSchema.pre("save", async function () {
  if (!this.requestId) {
    try {
      const all = await this.constructor.find({}, { requestId: 1 }).lean();
      let maxNum = 9000;
      all.forEach((r) => {
        if (r.requestId && r.requestId.startsWith("SCH-")) {
          const n = parseInt(r.requestId.replace("SCH-", ""), 10);
          if (!isNaN(n) && n > maxNum) maxNum = n;
        }
      });
      this.requestId = `SCH-${maxNum + 1}`;
    } catch (_) {
      this.requestId = `SCH-${9001 + Math.floor(Math.random() * 100)}`;
    }
  }
});

module.exports = mongoose.model("ScheduleRide", ScheduleRideSchema);
