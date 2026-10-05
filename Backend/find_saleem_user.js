require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const users = await db.collection("users").find({ fullName: /saleem/i }).toArray();
  console.log("Users named Saleem:", users.map(u => ({id: u._id, name: u.fullName, role: u.role})));
  
  process.exit(0);
}).catch(console.error);
