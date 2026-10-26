const DriverSchema = require("../Validation/driver");

const validateDriver = (req, res, next) => {
  const { error, value } = DriverSchema.validate(req.body, {
    abortEarly: false,
    allowUnknown: true,
  });

  if (error) {
    return res.status(400).json({
      success: false,
      message: "Validation failed",
      errors: error.details.map((detail) => detail.message),
    });
  }

  req.body = { ...req.body, ...value };
  next();
};

const validateDriverUpdate = (req, res, next) => {
  const phone = req.body.PhoneNumber || req.body.phoneNumber || req.body.phone;
  if (phone !== undefined && phone !== null && phone.toString().trim().length > 0) {
    const cleanPhone = phone.toString().replace(/[\s\-()]/g, "");
    const pakPhoneRegex = /^((\+92|92)?(0)?3[0-9]{9})$/;
    if (!pakPhoneRegex.test(cleanPhone)) {
      return res.status(400).json({
        success: false,
        message: "Please enter a valid Pakistani phone number (e.g. 03328904416)",
      });
    }
  }
  next();
};

module.exports = { validateDriver, validateDriverUpdate };
