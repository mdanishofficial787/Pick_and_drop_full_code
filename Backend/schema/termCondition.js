const mongoose = require("mongoose");

const termConditionSchema = new mongoose.Schema({

    version: {
        type: String,
        required: true
    },

    pdfUrl: {
        type: String,
        required: true
    },

    publicId: {
        type: String
    },

    isActive: {
        type: Boolean,
        default: true
    }

}, {
    timestamps: true
});


module.exports = mongoose.model(
    "TermsCondition",
    termConditionSchema
);
