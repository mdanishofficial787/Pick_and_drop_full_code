require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const rides = await db.collection("scheduledrides").find({}).toArray();
  
  // Find rides assigned to saleem
  const saleemRides = rides.filter(r => 
    (r.assignedDriverName && r.assignedDriverName.toLowerCase().includes('saleem')) ||
    (r.assignedDriver && r.assignedDriver.toLowerCase().includes('saleem')) ||
    (r.assignedDriverId === '6aace1500a489ee2fc8da2d5')
  );
  
  console.log("Scheduled rides assigned to Saleem:", JSON.stringify(saleemRides, null, 2));
  
  process.exit(0);
}).catch(console.error);
