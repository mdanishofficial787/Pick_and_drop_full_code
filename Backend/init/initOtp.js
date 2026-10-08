const mongoose = require("mongoose");
const OTP = require("../schema/otp");
const { otpdata } = require("./otp");


const Mongo_Url = "mongodb://127.0.0.1:27017/Customer";


async function main() {

    await mongoose.connect(Mongo_Url);

    console.log("Connected to MongoDB");


    await OTP.deleteMany({});


    await OTP.insertMany(otpdata);


    console.log("OTP Data Inserted Successfully");


    mongoose.connection.close();

}


main()
.catch((err) => {

    console.log(err);

});
