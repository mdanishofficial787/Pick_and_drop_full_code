const Customer = require("../schema/user");
const OTP = require("../schema/otp");
const bcrypt = require("bcrypt");
const sendOTPEmail = require("../utils/Email");
const { cloudinary } = require("../utils/cloudinary");
const streamifier = require("streamifier");

module.exports.signup = async (req, res) => {
    try {

        const {
            fullName,
            PhoneNumber,
            countryCode,
            Email,
            Password,
            confirmPassword,
            termsAccepted,
            tcVersion
        } = req.body;
       console.log("SIGNUP DATA RECEIVED:", req.body);
console.log("TERMS VALUE:", termsAccepted);
console.log("PASSWORD:", Password);
console.log("CONFIRM PASSWORD:", confirmPassword);

        // 1. T&C Validation
        if (!termsAccepted) {
            return res.status(400).json({
                success: false,
                message: "Please accept Terms & Conditions"
            });
        }


        // 2. Password Match Check
        if (Password !== confirmPassword) {
            return res.status(400).json({
                success: false,
                message: "Password and confirm password do not match"
            });
        }


        // 3. Phone Duplicate Check
        const phoneExists = await Customer.findOne({
            PhoneNumber
        });

        if (phoneExists) {
            return res.status(409).json({
                success: false,
                message: "Phone number already exists"
            });
        }

        const normalizedEmail = Email.trim().toLowerCase();

        // 3b. Email Duplicate Check
        const emailExists = await Customer.findOne({ Email: normalizedEmail });
        if (emailExists) {
            return res.status(409).json({
                success: false,
                message: "An account with this email already exists. Please login instead."
            });
        }

        // 4. Password Hashing
        const hashedPassword = await bcrypt.hash(
            Password,
            10
        );


        // 5. Cloudinary Upload
        let imageUrl = null;
        let imagePublicId = null;

        console.log("File:", req.file);

        if (req.file) {
            try {
                const result = await new Promise((resolve, reject) => {
                    const uploadStream = cloudinary.uploader.upload_stream(
                        {
                            folder: "customers",
                            resource_type: "image"
                        },
                        (error, result) => {
                            if (error) {
                                reject(error);
                            } else {
                                resolve(result);
                            }
                        }
                    );

                    streamifier.createReadStream(req.file.buffer).pipe(uploadStream);
                });

                // Save both Cloudinary URL and public_id
                imageUrl = result.secure_url;
                imagePublicId = result.public_id;
                console.log("Cloudinary upload successful:", imageUrl);
            } catch (cloudErr) {
                console.warn("Cloudinary upload notice:", cloudErr.message);
            }
        }


        // 6. T&C Timestamp
        const acceptedAtTimestamp =
            new Date().toISOString();


        // 7. Create Customer
        const newCustomer = new Customer({

            fullName,

            PhoneNumber,

            countryCode,

            Email: normalizedEmail,

            Password: hashedPassword,

            CustomerPhoto: {
                url: imageUrl,
                public_id: imagePublicId
            },

            isVerified: false,

            termsAccepted: {
                accepted: true,

                version:
                    tcVersion || "1.0",

                acceptedAt:
                    acceptedAtTimestamp
            }

        });


        await newCustomer.save();


        // 8. Generate OTP
const otp = Math.floor(
    100000 + Math.random() * 900000
).toString();

console.log("Generated OTP:", otp);

// 9. Hash OTP
const hashedOTP = await bcrypt.hash(
    otp,
    10
);

// 10. Save OTP
await OTP.create({
    customerId: newCustomer._id,

    email: normalizedEmail,

    otp: hashedOTP,

    otpExpiresAt: new Date(
        Date.now() + 2 * 60 * 1000
    ),

    otpAttempts: 0,

    verified: false,

    resendCount: 0,

    lastResendAt: null
});
// 11. Send OTP to Email
try {

    await sendOTPEmail(
        normalizedEmail,
        otp
    );

    console.log(
        "OTP email sent successfully to:",
        Email
    );

} catch (err) {

    console.error(
        "Email Sending Error:",
        err
    );

    await Customer.findByIdAndDelete(
        newCustomer._id
    );

    await OTP.deleteMany({
        customerId: newCustomer._id
    });

    return res.status(500).json({
        success: false,
        message:
            "OTP email could not be sent. Please try again."
    });
}

// 12. Success Response
return res.status(201).json({

    success: true,

    message:
        "Signup successful. OTP sent to your email",

    userId:
        newCustomer._id

});


    } catch (err) {

        console.error(
            "Signup Error:",
            err
        );

        return res.status(500).json({
            success: false,
            message: "Internal Server Error",
            error: err.message
        });
    }
};

module.exports.updateProfile = async (req, res) => {
  try {
    const { fullName, Email, PhoneNumber, customerId } = req.body;
    let userId = req.user ? (req.user._id || req.user.id) : customerId;

    if (!userId && req.body.userId) userId = req.body.userId;

    let user = null;
    if (userId) {
      user = await Customer.findById(userId);
    }
    if (!user && Email) {
      user = await Customer.findOne({ Email: Email.trim().toLowerCase() });
    }
    if (!user && PhoneNumber) {
      user = await Customer.findOne({ PhoneNumber: PhoneNumber.trim() });
    }

    if (!user) {
      return res.status(404).json({
        success: false,
        message: "Customer account not found"
      });
    }

    if (fullName) user.fullName = fullName.trim();
    if (Email) user.Email = Email.trim().toLowerCase();
    if (PhoneNumber) user.PhoneNumber = PhoneNumber.trim();

    if (req.file) {
      try {
        const result = await new Promise((resolve, reject) => {
          const uploadStream = cloudinary.uploader.upload_stream(
            {
              folder: "customers",
              resource_type: "image"
            },
            (error, result) => {
              if (error) reject(error);
              else resolve(result);
            }
          );
          streamifier.createReadStream(req.file.buffer).pipe(uploadStream);
        });
        user.CustomerPhoto = result.secure_url;
      } catch (uploadErr) {
        console.warn("Cloudinary upload failed, keeping old photo:", uploadErr.message);
      }
    }

    await user.save();

    return res.status(200).json({
      success: true,
      message: "Profile updated successfully",
      customer: {
        id: user._id,
        fullName: user.fullName,
        email: user.Email,
        phoneNumber: user.PhoneNumber,
        countryCode: user.countryCode || "+92",
        CustomerPhoto: user.CustomerPhoto,
        isVerified: user.isVerified || true
      }
    });
  } catch (err) {
    console.error("Update Profile Error:", err);
    return res.status(500).json({
      success: false,
      message: "Failed to update profile",
      error: err.message
    });
  }
};