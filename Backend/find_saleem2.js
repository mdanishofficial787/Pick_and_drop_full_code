require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  for (let dbName of ['ride_and_serve', 'test']) {
    const db = mongoose.connection.client.db(dbName);
    const drivers = await db.collection("drivers").find({ "personalInfo.fullName": /saleem/i }).toArray();
    console.log(`Saleems in ${dbName}.drivers:`, drivers.map(d => ({id: d._id, name: d.personalInfo?.fullName})));
    
    const rides = await db.collection("riderequests").find({ passengerName: /Bibi/i }).toArray();
    console.log(`Bibis in ${dbName}.riderequests:`, rides.map(r => ({id: r._id, name: r.passengerName, driver: r.assignedDriverName})));
  }
  process.exit(0);
}).catch(console.error);
