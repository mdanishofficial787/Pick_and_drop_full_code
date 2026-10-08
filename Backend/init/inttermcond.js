require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

const mongoose = require("mongoose");
const TermCondition = require("../schema/termCondition");

const Mongo_Url = process.env.MONGO_URL;

main()
    .then(() => {
        console.log("connect to DB");
        initDB();
    })
    .catch((err) => {
        console.log(err);
    });

async function main() {
    await mongoose.connect(Mongo_Url);
}

const initDB = async () => {

    await TermCondition.deleteMany({});

    const defaultTerms = new TermCondition({
        version: "1.0",

        pdfUrl:
            "https://res.cloudinary.com/xmiyee5r/image/upload/v1785564134/pdf-sample_0_iift7l.pdf",

        isActive: true
    });

    await defaultTerms.save();

    console.log("Terms & Conditions initialized");
};
