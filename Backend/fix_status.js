require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const result = await db.collection("riderequests").updateOne(
    { passengerName: /Bibi Sadiqa/i },
    { $set: { status: "ASSIGNED" } }
  );
  console.log("Update result:", result);
  
  process.exit(0);
}).catch(console.error);
