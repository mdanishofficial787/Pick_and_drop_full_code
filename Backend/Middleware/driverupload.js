const uploadDriver = require("../Multer/UploadDriver");

const driverUpload = uploadDriver.fields([
  {
    name: "driverPhoto",
    maxCount: 1,
  },
  {
    name: "CnicFront",
    maxCount: 1,
  },
  {
    name: "CnicBack",
    maxCount: 1,
  },
  {
    name: "LicenseFront",
    maxCount: 1,
  },
  {
    name: "LicenseBack",
    maxCount: 1,
  },
]);

module.exports = driverUpload;
