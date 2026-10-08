require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  // Get all drivers in ride_and_serve
  const allDrivers = await db.collection("drivers").find({}).toArray();
  console.log("All drivers in ride_and_serve:", allDrivers.map(d => d.personalInfo?.fullName));
  
  // Check the ride for Bibi Sadiqa
  const ride = await db.collection("riderequests").findOne({ passengerName: /Bibi Sadiqa/i });
  console.log("Ride in ride_and_serve assignedDriver:", ride?.assignedDriverName);
  
  process.exit(0);
}).catch(console.error);
