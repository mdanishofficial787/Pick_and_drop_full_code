require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const rides = await db.collection("scheduledrides").find({}).sort({createdAt: -1}).limit(5).toArray();
  console.log(JSON.stringify(rides, null, 2));
  
  process.exit(0);
}).catch(console.error);
