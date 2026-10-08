// One-time script to create the first admin account.
// Run from the Backend folder:  node init/seedAdmin.js
//
// Change the Name / Email / Password below before running,
// then delete or keep this file safely â€” it is NOT a public route.

require("dotenv").config();
const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");
const Admin = require("../schema/Admin");

const ADMIN_NAME = "Super Admin";
const ADMIN_EMAIL = "admin@example.com";
const ADMIN_PASSWORD = "ChangeThisPassword123!";

async function seed() {
  try {
    await mongoose.connect(process.env.MONGO_URL);

    const existing = await Admin.findOne({ Email: ADMIN_EMAIL.toLowerCase() });
    if (existing) {
      console.log("Admin with this email already exists:", existing.Email);
      process.exit(0);
    }

    const hashedPassword = await bcrypt.hash(ADMIN_PASSWORD, 10);

    const admin = await Admin.create({
      Name: ADMIN_NAME,
      Email: ADMIN_EMAIL.toLowerCase(),
      Password: hashedPassword,
      role: "superadmin",
    });

    console.log("Admin created successfully:");
    console.log({ Name: admin.Name, Email: admin.Email, role: admin.role });
    process.exit(0);
  } catch (error) {
    console.error("Seed Admin Error:", error);
    process.exit(1);
  }
}

seed();
