const multer = require("multer");

const storage = multer.memoryStorage();

const fileFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png/;

  const extName = allowedTypes.test(
    file.originalname.toLowerCase()
  );

  const mimeType = allowedTypes.test(file.mimetype);

  if (extName && mimeType) {
    cb(null, true);
  } else {
    cb(new Error("Only JPEG, JPG and PNG files are allowed"));
  }
};

const uploadDriver = multer({
  storage: storage,
  limits: {
    fileSize: 20 * 1024 * 1024, // 20 MB
  },
  fileFilter: fileFilter,
});

module.exports = uploadDriver;
