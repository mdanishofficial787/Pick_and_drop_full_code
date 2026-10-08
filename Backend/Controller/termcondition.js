const TermCondition = require("../schema/termCondition");

module.exports.getTermsConditions = async (req, res) => {
    try {
        const terms = await TermCondition.findOne({
            isActive: true
        }).sort({ createdAt: -1 });

        if (!terms) {
            return res.status(404).json({
                success: false,
                message: "Terms & Conditions not found"
            });
        }

        res.status(200).json({
            success: true,
            message: "Terms & Conditions fetched successfully",
            data: {
                version: terms.version,
                pdfUrl: terms.pdfUrl
            }
        });

    } catch (error) {
        res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: error.message
        });
    }
};
