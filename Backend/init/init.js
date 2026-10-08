require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const mongoose = require("mongoose");
const { userdata } = require("./data.js");
const Customer = require("../schema/user");

const Mongo_Url =process.env.MONGO_URL;
async function main() {
  await mongoose.connect(Mongo_Url);
}

main()
  .then(() => {
    console.log("connect to DB");
    intDB();
  })
  .catch((err) => {
    console.log(err);
  });
const intDB = async () => {
  await Customer.deleteMany({});
  await Customer.insertMany(userdata);
  console.log("Customer signup data inserted");

};
