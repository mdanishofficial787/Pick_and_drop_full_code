const mongoose = require("mongoose");

const customerSchema = new mongoose.Schema(
  {
    fullName: {
      type: String,
      required: true,
      trim: true
    },

    PhoneNumber: {
    type: String,
    required: function () {
        return this.SignupMethod === "Phone" ||
               this.SignupMethod === "Email";
    },
    unique: true,
    sparse: true
},

    countryCode: {
      type: String,
      default: "+92"
    },

    Email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true
    },
    googleId: {
    type: String,
    default: null
},

SignupMethod: {
    type: String,
    enum: ["Phone", "Email", "Google"],
    default: "Email"
},

   Password: {
  type: String,
  required: function () {
    return this.SignupMethod === "Email";
  }
},
  
CustomerPhoto: {
      url: {
        type: String,
        default: null
      },
        public_id: {
        type: String,
        default: null
    }
     
    },
    isVerified: {
      type: Boolean,
      default: false
    },
    termsAccepted: {
    accepted: {
        type: Boolean,
        default: true
    },

    version: {
        type: String,
        default: "1.0"
    },

    acceptedAt: {
        type: Date,
        default: Date.now
    }
}
  },
  {
    timestamps: true
  }
);
module.exports = mongoose.model("Customer", customerSchema);