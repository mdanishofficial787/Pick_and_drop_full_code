const express = require("express");
const router = express.Router();

// 1. Destructured import karein (jo export ho raha hai wahi import karein)
const { uploadSingleImage } = require("../Multer/imageupload");
const authMiddleware = require("../Middleware/Authr");

// Controller Import
const { 
  uploadProfilePicture, 
  deleteProfilePicture 
} = require("../Controller/uploadimage");

// 1. Upload/Update (Token-based)
router.put(
  "/profile-picture",
  authMiddleware,
  uploadSingleImage("CustomerPhoto"),
  uploadProfilePicture
);

// 2. Upload/Update (URL Params-based)
router.put(
  "/profile-picture/:id",
  authMiddleware,
  uploadSingleImage("CustomerPhoto"),
  uploadProfilePicture
);

// 3. Delete (Token-based)
router.delete(
  "/profile-picture",
  authMiddleware,
  deleteProfilePicture
);

// 4. Delete (URL Params-based)
router.delete(
  "/profile-picture/:id",
  authMiddleware,
  deleteProfilePicture
);

module.exports = router;
