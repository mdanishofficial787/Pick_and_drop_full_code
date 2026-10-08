require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL || "mongodb://127.0.0.1:27017/ride_and_serve";

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.db;
  const rides = await db.collection("riderequests").find({ passengerName: /Bibi Sadiqa/i }).toArray();
  console.log("Rides for Bibi Sadiqa in riderequests:", rides);
  
  const drivers = await db.collection("drivers").find({ "personalInfo.fullName": /saleem/i }).toArray();
  console.log("Drivers named saleem:", drivers);

  process.exit(0);
}).catch(console.error);
