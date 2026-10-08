const Joi = require("joi");

const DriverLoginValidationSchema = Joi.object({
    CountryCode: Joi.string()
        .trim()
        .pattern(/^\+[0-9]{1,4}$/)
        .default("+92")
        .messages({
            "string.pattern.base": "Invalid country code format (e.g. +92)",
        }),

    PhoneNumber: Joi.string()
        .trim()
        .pattern(/^[0-9]{7,15}$/)
        .required()
        .messages({
            "string.empty": "Phone number is required",
            "string.pattern.base": "Phone number must contain 7 to 15 digits",
            "any.required": "Phone number is required",
        }),

    Password: Joi.string()
        .required()
        .messages({
            "string.empty": "Password is required",
            "any.required": "Password is required",
        }),
});

module.exports = DriverLoginValidationSchema;
