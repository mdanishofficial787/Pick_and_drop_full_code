const mongoose = require("mongoose");

const RideRequestSchema = new mongoose.Schema(
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
    scheduleType: {
      type: String,
      default: "Mon - Fri"
    },
    scheduleTime: {
      type: String,
      default: "9:00 AM"
    },
    customSchedule: {
      type: mongoose.Schema.Types.Mixed,
      default: {}
    },
    tripType: {
      type: String,
      default: "One Way"
    },
    genderPreference: {
      type: String,
      default: "Both"
    },
    vehicleTypeSelection: {
      type: String,
      default: "Separate"
    },
    seatingArrangement: {
      type: String,
      default: "Sedan Executive"
    },
    vehicleType: {
      type: String,
      default: "Sedan"
    },
    acPreference: {
      type: String,
      default: "AC"
    },
    passengersCount: {
      type: Number,
      default: 1
    },
    fare: {
      type: Number,
      default: 9500
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
    },
    cnic: {
      type: String,
      default: ""
    },
    destination: {
      type: String,
      default: ""
    },
    driverIssue: {
      type: mongoose.Schema.Types.Mixed,
      default: null
    },
    replacementPreferences: {
      type: mongoose.Schema.Types.Mixed,
      default: null
    }
  },
  {
    timestamps: true
  }
);

// Pre-save hook to generate sequential / formatted requestId (TT-7001+, SCH-9001+, REQ-8031+, HIR-7001+)
RideRequestSchema.pre("save", async function () {
  if (!this.requestId) {
    try {
      const allRides = await this.constructor.find({}, { requestId: 1, scheduleType: 1 }).lean();
      const schedType = (this.scheduleType || "").toLowerCase();

      if (schedType.includes("travel") || schedType.includes("tourism") || schedType.includes("tt")) {
        // Travel & Tourism: Prefix TT-7001+
        let maxNum = 7000;
        allRides.forEach((r) => {
          if (r.requestId && typeof r.requestId === "string" && r.requestId.startsWith("TT-")) {
            const num = parseInt(r.requestId.replace("TT-", ""), 10);
            if (!isNaN(num) && num > maxNum) maxNum = num;
          }
        });
        this.requestId = `TT-${maxNum + 1}`;
      } else if (schedType.includes("schedule") || schedType.includes("sch")) {
        // Schedule Ride: Prefix SCH-9001+
        let maxNum = 9000;
        allRides.forEach((r) => {
          if (r.requestId && typeof r.requestId === "string" && r.requestId.startsWith("SCH-")) {
            const num = parseInt(r.requestId.replace("SCH-", ""), 10);
            if (!isNaN(num) && num > maxNum) maxNum = num;
          }
        });
        this.requestId = `SCH-${maxNum + 1}`;
      } else if (schedType.includes("hire") || schedType.includes("driver")) {
        // Hire Driver: Prefix HIR-7001+
        let maxNum = 7000;
        allRides.forEach((r) => {
          if (r.requestId && typeof r.requestId === "string" && r.requestId.startsWith("HIR-")) {
            const num = parseInt(r.requestId.replace("HIR-", ""), 10);
            if (!isNaN(num) && num > maxNum) maxNum = num;
          }
        });
        this.requestId = `HIR-${maxNum + 1}`;
      } else {
        // Monthly Ride: Prefix REQ-8031+
        let maxNum = 8030;
        allRides.forEach((r) => {
          if (r.requestId && typeof r.requestId === "string" && r.requestId.startsWith("REQ-")) {
            const num = parseInt(r.requestId.replace("REQ-", ""), 10);
            if (!isNaN(num) && num > maxNum) maxNum = num;
          }
        });
        this.requestId = `REQ-${maxNum + 1}`;
      }
    } catch (err) {
      this.requestId = `TT-${7001 + Math.floor(Math.random() * 50)}`;
    }
  }
});

module.exports = mongoose.model("RideRequest", RideRequestSchema);
