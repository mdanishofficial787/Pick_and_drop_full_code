const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
   title: String,
   message: String,
   type: String,
   status: String,
   paymentId: String,
   customerId: String,
   driverId: String,
   rideId: String,
   isRead: { type: Boolean, default: false },
   createdAt: { type: Date, default: Date.now }
}, { collection: 'notifications' });

module.exports = mongoose.model('Notification', notificationSchema);
