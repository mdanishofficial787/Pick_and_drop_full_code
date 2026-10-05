require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  
  const saleem = await db.collection("drivers").findOne({ Name: /saleem/i });
  console.log("Saleem Driver:", saleem);
  
  if (saleem) {
    const bibiRide = await db.collection("riderequests").findOne({ passengerName: /Bibi Sadiqa/i });
    console.log("Bibi Ride:", bibiRide);
    
    if (bibiRide) {
      await db.collection("riderequests").updateOne(
        { _id: bibiRide._id },
        {
          $set: {
            assignedDriverId: saleem._id.toString(),
            assignedDriverName: saleem.Name,
            status: "Driver Assigned" // or keep it Pending Dispatch? Usually it changes status
          }
        }
      );
      console.log("Assigned Saleem to Bibi Sadiqa's ride!");
    } else {
      console.log("Could not find Bibi Sadiqa ride");
    }
  } else {
    console.log("Could not find driver named Saleem");
  }
  
  process.exit(0);
}).catch(console.error);
