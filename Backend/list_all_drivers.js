require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const drivers = await db.collection("users").find({ role: 'driver' }).toArray();
  console.log("All drivers in users collection:", drivers.map(u => u.fullName));
  
  process.exit(0);
}).catch(console.error);
