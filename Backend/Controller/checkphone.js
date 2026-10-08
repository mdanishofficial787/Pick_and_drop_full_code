const Customer = require("../schema/user");

module.exports.checkPhone = async (req, res) => {
    try {

        const { number } = req.params;


        // Phone number validation
        if (!/^[0-9]{11}$/.test(number)) {
            return res.status(400).json({
                success: false,
                message: "Phone number must be 11 digits"
            });
        }


        const user = await Customer.findOne({
            PhoneNumber: number
        });


        if (user) {
            return res.status(200).json({
                success: true,
                available: false,
                message: "Phone number already registered"
            });
        }


        return res.status(200).json({
            success: true,
            available: true,
            message: "Phone number is available"
        });


    } catch (error) {

        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: error.message
        });

    }
};
