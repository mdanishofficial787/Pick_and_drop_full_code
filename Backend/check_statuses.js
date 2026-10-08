require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const rides = await db.collection("schedulerides").find({}).toArray();
  console.log("All Schedule Rides:");
  rides.forEach(r => console.log(`ID: ${r._id}, status: ${r.status}, driver: ${r.assignedDriverName || r.assignedDriverId || 'none'}`));
  
  process.exit(0);
}).catch(console.error);
