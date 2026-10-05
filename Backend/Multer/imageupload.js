// middleware/uploadMiddleware.js
const multer = require("multer");

const storage = multer.memoryStorage();

const fileFilter = (req, file, cb) => {
  const isImageMime = file.mimetype && file.mimetype.startsWith("image/");
  const isImageExt = /\.(jpe?g|png|webp|gif|bmp|heic|svg)$/i.test(file.originalname || "");
  const isStreamWithExt = file.mimetype === "application/octet-stream" && isImageExt;

  if (isImageMime || isImageExt || isStreamWithExt || !file.mimetype) {
    cb(null, true);
  } else {
    cb(new Error("Only image files (JPG, PNG, WEBP, etc.) are allowed!"), false);
  }
};

const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB Limit
  }
});

// Single image handling wrapper function with proper error handling
const uploadSingleImage = (fieldName) => {
  return (req, res, next) => {
    upload.single(fieldName)(req, res, (err) => {
      if (err instanceof multer.MulterError) {
        // Multer-specific errors (e.g., File too large)
        if (err.code === "LIMIT_FILE_SIZE") {
          return res.status(400).json({
            success: false,
            message: "File size cannot exceed 5MB"
          });
        }
        return res.status(400).json({
          success: false,
          message: err.message
        });
      } else if (err) {
        // Custom errors (e.g., File type not allowed)
        return res.status(400).json({
          success: false,
          message: err.message
        });
      }
      next();
    });
  };
};

module.exports = { uploadSingleImage };