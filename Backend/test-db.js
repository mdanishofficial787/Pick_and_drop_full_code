const mongoose = require('mongoose');
const Payment = require('./schema/Payment');
require('dotenv').config();

async function run() {
  await mongoose.connect(process.env.MONGO_URL);
  const payments = await Payment.find().sort({createdAt: -1}).limit(2);
  console.log(JSON.stringify(payments, null, 2));
  process.exit(0);
}
run();
