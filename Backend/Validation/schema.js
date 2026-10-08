const Joi = require("joi");
const signupSchema = Joi.object({
  fullName: Joi.string()
    .trim()
    .required()
    .messages({
      "string.empty": "Full name cannot be empty",
      "any.required": "Full name is required"
    }),

  PhoneNumber: Joi.string()
    .length(11)
    .pattern(/^[0-9]{11}$/)
    .required()
    .messages({
      "string.length": "Phone number must be 11 digits",
      "string.pattern.base": "Invalid phone number",
      "any.required": "Phone number is required"
    }),

  countryCode: Joi.string()
    .valid(
      "+92", "+91", "+1", "+44", "+971", "+966", "+974", "+965", 
      "+973", "+968", "+880", "+94", "+93", "+86", "+81", "+82", 
      "+65", "+60", "+66", "+84", "+62", "+63", "+61", "+64", 
      "+49", "+33", "+39", "+34", "+31", "+90"
    )
    .required()
    .messages({
      "any.only": "Invalid country code",
      "any.required": "Country code is required"
    }),

  Email: Joi.string()
    .trim()
    .lowercase()
    .pattern(/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)
    .required()
    .messages({
      "string.pattern.base": "Please enter a valid email address (e.g. user@example.com)",
      "string.empty": "Email cannot be empty",
      "any.required": "Email is required"
    }),

  Password: Joi.string()
    .min(8)
    .max(30)
    .pattern(/^[a-zA-Z0-9@#$%^&*!]{8,30}$/)
    .required()
    .messages({
      "string.min": "Password must be at least 8 characters long",
      "string.max": "Password cannot exceed 30 characters",
      "string.pattern.base": "Password contains invalid characters or does not meet criteria",
      "any.required": "Password is required"
    }),

  confirmPassword: Joi.string()
    .valid(Joi.ref("Password"))
    .required()
    .messages({
      "any.only": "Password and confirm password do not match",
      "any.required": "Confirm password is required"
    }),

  termsAccepted: Joi.alternatives()
    .try(Joi.boolean(), Joi.string())
    .optional()
    .default(true),

  tcVersion: Joi.string()
    .optional()
    .default("1.0")
});
// Verify OTP Validation Schema

const verifyOTPSchema = Joi.object({
  phoneNumber: Joi.string()
    .length(11)
    .pattern(/^[0-9]{11}$/)
    .required()
    .messages({
      "string.length": "Phone number must be 11 digits",
      "string.pattern.base": "Invalid phone number",
      "any.required": "Phone number is required"
    }),

  otp: Joi.string()
    .length(6)
    .pattern(/^[0-9]{6}$/)
    .required()
    .messages({
      "string.length": "OTP must be 6 digits",
      "string.pattern.base": "OTP must contain only numbers",
      "any.required": "OTP is required"
    })
});
// Middlewares
const validateSignup = (req, res, next) => {
  const { error, value } = signupSchema.validate(req.body, { abortEarly: false });

  if (error) {
    return res.status(400).json({
      success: false,
      message: error.details.map((detail) => detail.message).join(", ")
    });
  }

  req.body = value;
  next();
};

const validateVerifyOTP = (req, res, next) => {
  const { error, value } = verifyOTPSchema.validate(req.body, { abortEarly: false });

  if (error) {
    return res.status(400).json({
      success: false,
      message: error.details.map((detail) => detail.message).join(", ")
    });
  }

  req.body = value;
  next();
};

module.exports = {
  validateSignup,
  validateVerifyOTP
};
