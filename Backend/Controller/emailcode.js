const Customer = require("../schema/user");
const OTP = require("../schema/otp");
const bcrypt = require("bcrypt");

const verifyOTP = async (req, res) => {

    try {
        const {
            customerId,
            otp
        } = req.body;

        // Customer find

        const customer = await Customer.findById(customerId);
        if(!customer){

            return res.status(404).json({

                success:false,

                message:"Customer not found"

            });

        }
        // OTP find

        const otpData = await OTP.findOne({

            customerId: customerId

        });

        if(!otpData){

            return res.status(404).json({

                success:false,

                message:"OTP not found"

            });

        }
        // Attempts check

        if(otpData.otpAttempts >= 3){

            return res.status(400).json({

                success:false,

                message:"Maximum OTP attempts exceeded"

            });

        }
        // Expiry check

        if(new Date() > otpData.otpExpiresAt){
            return res.status(400).json({
                success:false,
                message:"OTP expired"

            });

        }
        // Compare OTP

        const isMatch = await bcrypt.compare(

            otp,

            otpData.otp

        );

  if(!isMatch){

            otpData.otpAttempts += 1;

            await otpData.save();
            return res.status(400).json({

                success:false,

                message:"Invalid OTP"

            });

        }
        // Verify customer

        customer.isVerified = true;

        await customer.save();
        // Update OTP

        otpData.verified = true;

        await otpData.save();
        return res.status(200).json({

            success:true,

            message:"OTP verified successfully"

        });



    } catch(err){

        console.log(err);


        return res.status(500).json({

            success:false,

            message:"Internal Server Error",

            error:err.message

        });

    }

};



module.exports = {
    signup,
    verifyOTP
};
