const Joi = require("joi");
const fs = require("fs");

// Delete uploaded file if validation fails
const deleteUploadedFile = (req) => {

  if (req.file && req.file.path) {

    fs.unlink(req.file.path, (err) => {

      if (err) {
        console.error("Image delete error:", err);
      }

    });

  }

};


// ==============================
// Signup Validation
// ==============================

const signupSchema = Joi.object({

  fullName: Joi.string()
    .trim()
    .min(3)
    .required(),

  PhoneNumber: Joi.string()
    .pattern(/^[0-9]{7,15}$/)
    .required(),

  countryCode: Joi.string()
    .valid(
      "+92",
      "+91",
      "+1",
      "+44",
      "+971",
      "+966",
      "+974",
      "+965",
      "+973",
      "+968",
      "+880",
      "+94",
      "+93",
      "+86",
      "+81",
      "+82",
      "+65",
      "+60",
      "+66",
      "+84",
      "+62",
      "+63",
      "+61",
      "+64",
      "+49",
      "+33",
      "+39",
      "+34",
      "+31",
      "+90"
    )
    .required(),

  Email: Joi.string()
    .email()
    .required(),

  Password: Joi.string()
    .min(8)
    .max(30)
    .pattern(/^[a-zA-Z0-9@#$%^&*!]+$/)
    .required(),

  confirmPassword: Joi.string()
    .valid(Joi.ref("Password"))
    .required()
    .messages({
      "any.only":
        "Password and confirm password do not match"
    }),

  ReferralCode: Joi.string()
    .allow("", null),

termsAccepted: Joi.alternatives()
    .try(
      Joi.boolean(),
      Joi.string()
    )
    .optional()
    .default(true),

  SignupMethod: Joi.string()
    .valid(
      "Email",
      "Google",
      "LinkedIn",
      "Phone",
      "Apple"
    )
    .optional()
    .allow("", null),

    tcVersion: Joi.string()
  .optional()
  .default("1.0")


});


// ==============================
// Verify OTP Validation
// ==============================

const verifyOTPSchema = Joi.object({
    email: Joi.string()
        .email()
        .required()
        .messages({
            "any.required":
                "Email is required",

            "string.empty":
                "Email is required",

            "string.email":
                "Please enter a valid email address"
        }),

    otp: Joi.string()
        .length(6)
        .pattern(/^[0-9]+$/)
        .required()
        .messages({
            "any.required":
                "OTP is required",

            "string.empty":
                "OTP is required",

            "string.length":
                "OTP must be 6 digits",

            "string.pattern.base":
                "OTP must contain only numbers"
        })
});


// ==============================
// Signup Middleware
// ==============================

const validateSignup = (req, res, next) => {

  console.log("VALIDATION BODY:", req.body);

  const { error } = signupSchema.validate(
    req.body,
    {
      abortEarly: false
    }
  );

  console.log("VALIDATION ERROR:", error);


  if (error) {

    deleteUploadedFile(req);

    return res.status(400).json({

      success: false,

      message: error.details
        .map(detail => detail.message)
        .join(", ")

    });

  }


  next();

};


// ==============================
// Verify OTP Middleware
// ==============================

const validateVerifyOTP = (req, res, next) => {

  const { error } = verifyOTPSchema.validate(
    req.body,
    {
      abortEarly: false
    }
  );


  if (error) {

    return res.status(400).json({

      success: false,

      message: error.details
        .map(detail => detail.message)
        .join(", ")

    });

  }


  next();

};


// ==============================
// Export
// ==============================

module.exports = {

  validateSignup,

  validateVerifyOTP

};
