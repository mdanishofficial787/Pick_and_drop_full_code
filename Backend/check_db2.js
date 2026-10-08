require("dotenv").config();
console.log("Connecting to:", process.env.MONGO_URL);
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL;

mongoose.connect(DBurl).then(async () => {
  console.log("Connected!");
  const db = mongoose.connection.db;
  const rides = await db.collection("riderequests").find({ passengerName: /Bibi/i }).toArray();
  console.log("Rides:", JSON.stringify(rides, null, 2));
  
  const drivers = await db.collection("drivers").find({ "personalInfo.fullName": /saleem/i }).toArray();
  console.log("Drivers:", JSON.stringify(drivers, null, 2));

  process.exit(0);
}).catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
