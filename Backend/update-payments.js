const mongoose = require('mongoose');
const Payment = require('./schema/Payment');
const Customer = require('./schema/user'); // Ensure correct casing! Wait, let's check exact casing.
require('dotenv').config();

async function run() {
  await mongoose.connect(process.env.MONGO_URL);
  
  const payments = await Payment.find();
  for (let payment of payments) {
    if (payment.customerName === "Unknown" || !payment.customerName) {
      const customer = await Customer.findById(payment.customerId);
      if (customer) {
        payment.customerName = customer.fullName || "Unknown";
        payment.customerPhone = customer.PhoneNumber || "Unknown";
        await payment.save();
        console.log(`Updated payment ${payment._id} with ${payment.customerName}`);
      }
    }
  }
  
  console.log("Done updating existing payments.");
  process.exit(0);
}
run();
