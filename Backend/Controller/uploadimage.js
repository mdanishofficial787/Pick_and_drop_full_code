const User = require("../schema/user");
const mongoose = require("mongoose");
const {
  uploadToCloudinary,
  deleteFromCloudinary
} = require("../utils/cloudinary");

/**
 * Resolve the customer ID from either:
 *  - The authenticated JWT token (req.user) â€” supports multiple payload shapes
 *    (id, customerId, _id, userId)
 *  - The URL parameter (req.params.id)
 * Returns null if no valid ID is found.
 */
const resolveCustomerId = (req) => {
  // 1. Try URL param first if present
  if (req.params && req.params.id) {
    return req.params.id;
  }

  // 2. Try the authenticated user token payload
  if (req.user) {
    return (
      req.user.id ||
      req.user.customerId ||
      req.user.userId ||
      req.user._id ||
      null
    );
  }

  return null;
};

// 1. Upload / Update Profile Picture
module.exports.uploadProfilePicture = async (req, res) => {
  try {
    const customerId = resolveCustomerId(req);

    // Check we have a customer ID
    if (!customerId) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized. Please log in or provide a valid customer ID"
      });
    }

    // Check valid MongoDB ObjectId
    if (!mongoose.Types.ObjectId.isValid(customerId)) {
      return res.status(400).json({
        success: false,
        message: "Invalid Customer ID format"
      });
    }

    // Check file existence
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: "Please attach an image file"
      });
    }

    // Find customer
    const user = await User.findById(customerId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "Customer not found"
      });
    }

    // Delete old image from Cloudinary if exists
    if (user.CustomerPhoto && user.CustomerPhoto.public_id) {
      await deleteFromCloudinary(user.CustomerPhoto.public_id);
    }

    // Upload new image to Cloudinary
    const cloudResult = await uploadToCloudinary(
      req.file.buffer,
      "CustomerPhoto"
    );

    // Save new image info (Using secure_url for HTTPS)
    user.CustomerPhoto = {
      url: cloudResult.secure_url || cloudResult.url,
      public_id: cloudResult.public_id
    };

    await user.save();

    return res.status(200).json({
      success: true,
      message: "Profile picture updated successfully",
      data: {
        CustomerPhoto: user.CustomerPhoto
      }
    });

  } catch (error) {
    console.error("Upload Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server Error while updating profile picture",
      error: error.message
    });
  }
};

// 2. Delete Profile Picture
module.exports.deleteProfilePicture = async (req, res) => {
  try {
    const customerId = resolveCustomerId(req);

    // Check we have a customer ID
    if (!customerId) {
      return res.status(401).json({
        success: false,
        message: "Unauthorized. Please log in or provide a valid customer ID"
      });
    }

    // Check valid MongoDB ObjectId
    if (!mongoose.Types.ObjectId.isValid(customerId)) {
      return res.status(400).json({
        success: false,
        message: "Invalid Customer ID format"
      });
    }

    // Find customer
    const user = await User.findById(customerId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "Customer not found"
      });
    }

    // Check profile picture existence
    if (!user.CustomerPhoto || !user.CustomerPhoto.public_id) {
      return res.status(400).json({
        success: false,
        message: "No profile picture found to delete"
      });
    }

    // Delete image from Cloudinary
    await deleteFromCloudinary(user.CustomerPhoto.public_id);

    // Remove image field from database cleanly
    user.CustomerPhoto = undefined;

    await user.save();

    return res.status(200).json({
      success: true,
      message: "Profile picture deleted successfully"
    });

  } catch (error) {
    console.error("Delete Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server Error while deleting profile picture",
      error: error.message
    });
  }
};
