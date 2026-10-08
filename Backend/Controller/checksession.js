const Customer = require("../schema/user");


module.exports.checkSession = async (req, res) => {

    try {

        const customer = await Customer.findById(req.user.id)
            .select("-Password");


        if (!customer) {

            return res.status(404).json({
                success: false,
                isLoggedIn: false,
                message: "User not found"
            });

        }


        return res.status(200).json({

            success: true,
            isLoggedIn: true,
            message: "Active session found",
            customer

        });


    } catch (error) {

        return res.status(500).json({

            success: false,
            message: error.message

        });

    }

};
