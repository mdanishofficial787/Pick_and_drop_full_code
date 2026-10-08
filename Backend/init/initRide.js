const mongoose = require("mongoose");
const rideData = require("./Ride.js");
const RecurringRide = require("../schema/ridereq.js");

const Mongo_Url = "mongodb://127.0.0.1:27017/Customer";
main()
  .then(() => {
    console.log("connect to DB");
  })
  .catch((err) => {
    console.log(err);
  });

async function main() {
  await mongoose.connect(Mongo_Url);
  console.log("Database connected");
}

const initRideDB = async () => {
  await RecurringRide.deleteMany({});
  await RecurringRide.insertMany(rideData.recurringRideData);

  console.log("Recurring Ride data inserted");
};
initRideDB()


