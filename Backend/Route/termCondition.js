const express = require("express");
const router = express.Router();

const termConditionController = require("../Controller/termcondition");

router.get(
    "/terms-conditions",
    termConditionController.getTermsConditions
);

module.exports = router;
