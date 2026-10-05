const Joi = require("joi");

const DriverValidationSchema = Joi.object({
  Name: Joi.string()
    .trim()
    .min(2)
    .max(100)
    .required()
    .messages({
      "string.empty": "Name is required",
      "string.min": "Name must be at least 2 characters long",
      "string.max": "Name must not exceed 100 characters",
      "any.required": "Name is required",
    }),

  PhoneNumber: Joi.string()
    .trim()
    .pattern(/^\+?[0-9]{7,15}$/)
    .required()
    .messages({
      "string.empty": "Phone number is required",
      "string.pattern.base":
        "Phone number must contain 7 to 15 digits (e.g. +447400123458 or +923001234567)",
      "any.required": "Phone number is required",
    }),

  Email: Joi.string()
    .email()
    .lowercase()
    .trim()
    .required()
    .messages({
      "string.empty": "Email is required",
      "string.email": "Invalid email format",
      "any.required": "Email is required",
    }),

  CnicNumber: Joi.string()
    .trim()
    .pattern(/^[0-9]{5}-[0-9]{7}-[0-9]{1}$/)
    .required()
    .messages({
      "string.empty": "CNIC number is required",
      "string.pattern.base":
        "Invalid CNIC format. Example: 35202-1234567-1",
      "any.required": "CNIC number is required",
    }),

  Password: Joi.string()
    .min(6)
    .max(128)
    .required()
    .messages({
      "string.empty": "Password is required",
      "string.min":
        "Password must be at least 6 characters long",
      "string.max":
        "Password must not exceed 128 characters",
      "any.required": "Password is required",
    }),

  ConfirmPassword: Joi.string()
    .required()
    .valid(Joi.ref("Password"))
    .messages({
      "string.empty": "Confirm Password is required",
      "any.only":
        "Confirm Password must match Password",
      "any.required":
        "Confirm Password is required",
    }),

  License: Joi.string()
    .trim()
    .required()
    .messages({
      "string.empty": "License number is required",
      "any.required": "License number is required",
    }),

  LicenseExpiryDate: Joi.date()
    .iso()
    .greater("now")
    .required()
    .messages({
      "date.format":
        "License expiry date must be in YYYY-MM-DD format",
      "date.base":
        "Invalid license expiry date",
      "date.greater":
        "License expiry date must be a future date",
      "any.required":
        "License expiry date is required",
    }),

  backgroundCheckConsent: Joi.boolean()
    .truthy("true", "1")
    .falsy("false", "0")
    .valid(true)
    .required()
    .messages({
      "boolean.base":
        "Background check consent must be true",
      "any.only":
        "You must give consent for the background check",
      "any.required":
        "Background check consent is required",
    }),
}).unknown(true);

module.exports = DriverValidationSchema;
