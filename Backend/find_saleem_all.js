require("dotenv").config();
const mongoose = require("mongoose");
const DBurl = process.env.MONGO_URL; 

mongoose.connect(DBurl).then(async () => {
  const db = mongoose.connection.client.db('ride_and_serve');
  const testDb = mongoose.connection.client.db('test');
  
  for (const database of [db, testDb]) {
    console.log(`\n--- DB: ${database.databaseName} ---`);
    const collections = await database.listCollections().toArray();
    for (let c of collections) {
      const col = database.collection(c.name);
      
      const countSaleem = await col.countDocuments({
        $or: [
          { fullName: /saleem/i },
          { name: /saleem/i },
          { "personalInfo.fullName": /saleem/i },
          { "personalInfo.firstName": /saleem/i }
        ]
      });
      if (countSaleem > 0) {
        console.log(`Found Saleem in ${c.name}`);
        const docs = await col.find({
          $or: [
            { fullName: /saleem/i },
            { name: /saleem/i },
            { "personalInfo.fullName": /saleem/i },
            { "personalInfo.firstName": /saleem/i }
          ]
        }).toArray();
        console.log(JSON.stringify(docs, null, 2));
      }
    }
  }
  process.exit(0);
}).catch(console.error);
