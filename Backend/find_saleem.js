require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; // mongodb+srv://.../ride_and_serve...

mongoose.connect(DBurl).then(async () => {
  const admin = mongoose.connection.db.admin();
  const dbs = await admin.listDatabases();
  console.log("Databases:", dbs.databases.map(d => d.name));
  
  for (let dbInfo of dbs.databases) {
    const dbName = dbInfo.name;
    const db = mongoose.connection.client.db(dbName);
    
    // Check drivers
    const drivers = await db.collection("drivers").find({ "personalInfo.fullName": /saleem/i }).toArray();
    if (drivers.length > 0) {
      console.log(`Found saleem in ${dbName}.drivers:`, drivers.map(d => ({id: d._id, name: d.personalInfo?.fullName})));
    }
    
    // Check drivers in users or driver collection
    const users = await db.collection("users").find({ fullName: /saleem/i }).toArray();
    if (users.length > 0) {
      console.log(`Found saleem in ${dbName}.users:`, users.map(u => ({id: u._id, name: u.fullName, role: u.role})));
    }
  }
  process.exit(0);
}).catch(console.error);
