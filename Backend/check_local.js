const mongoose = require("mongoose");
mongoose.connect("mongodb://127.0.0.1:27017/ride_and_serve").then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  const rides = await db.collection("riderequests").find({ passengerName: /Bibi/i }).toArray();
  console.log("Local Bibis:", rides);
  const drivers = await db.collection("drivers").find({ "personalInfo.fullName": /saleem/i }).toArray();
  console.log("Local Saleems:", drivers);
  process.exit(0);
}).catch(console.error);
