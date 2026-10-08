const express = require("express");
const router = express.Router();
const multer = require("multer");

// Multer setup for memory storage (for cloudinary upload)
const storage = multer.memoryStorage();
const upload = multer({ storage: storage });

const {
  submitPayment,
  getCustomerPayments,
  getAllPayments,
  updatePaymentStatus
} = require("../Controller/PaymentController");

// Use standard auth middleware if you have one, or just route handlers
// Assuming customer is handled via req.user or req.body.customerId
router.post("/upload", upload.single("paymentProof"), submitPayment);
router.get("/history", getCustomerPayments);

// Admin routes
router.get("/admin/all", getAllPayments);
router.patch("/admin/:id", updatePaymentStatus);

module.exports = router;
