require("dotenv").config();
const dns = require("dns");
try {
  dns.setServers(["8.8.8.8", "1.1.1.1", "8.8.4.4"]);
} catch (_) {}

const express = require("express");
const http = require("http");
const cors = require("cors");
const mongoose = require("mongoose");
const { Server } = require("socket.io");

const customerRoutes = require("./Route/signup");
const welcomeRoute = require("./Route/welcome");
//const referralRoutes = require("./Route/ReferralRoute");
const termConditionRoute = require("./Route/termCondition");
const OtpRoute = require("./Route/OtpRoute");
const imageRoute = require("./Route/uploadpick");
const loginRoute = require("./Route/LoginRoute");
const forgotPasswordRoute = require("./Route/forgotpasswordroute");

// Driver Routes
const driverRoutes = require("./Route/driverRoute");
const vehicleRoutes = require("./Route/vehicle_Route");
const driverPasswordRoutes = require("./Route/driver_password_Route");
const driverAdminRoutes = require("./Route/driver_Admin_Route");
const adminAuthRoutes = require("./Route/adminAuthRoute");

const app = express();

// Create HTTP server and attach Socket.IO
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST", "PATCH", "PUT", "DELETE"],
    credentials: true
  }
});

// Make io available globally so controllers can emit events
app.set("io", io);

// Socket.IO connection handler
io.on("connection", (socket) => {
  console.log("🔌 Socket connected via WebSocket:", socket.id);

  socket.on("join-customer", (customerId) => {
    if (customerId) {
      const roomStr = String(customerId);
      socket.join(`customer_${roomStr}`);
      socket.join(roomStr);
      console.log(`👤 Customer joined socket room: customer_${roomStr}`);
    }
  });

  socket.on("join-ride", (rideId) => {
    if (rideId) {
      const rideStr = String(rideId);
      socket.join(`ride_${rideStr}`);
      socket.join(rideStr);
      console.log(`🚗 Joined ride socket room: ride_${rideStr}`);
    }
  });

  socket.on("disconnect", () => {
    console.log("❌ Socket disconnected:", socket.id);
  });
});

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// 2. Connect to MongoDB (Atlas with fallback to Local MongoDB)
const DBurl = process.env.MONGO_URL || "mongodb://127.0.0.1:27017/ride_and_serve";
const LocalDBurl = process.env.LOCAL_MONGO_URL || "mongodb://127.0.0.1:27017/ride_and_serve";

async function connectDB() {
  try {
    await mongoose.connect(DBurl);
    console.log("✅ MongoDB Atlas connected successfully!");
  } catch (err) {
    console.warn("⚠️ MongoDB Atlas connection error. Falling back to Local MongoDB:", err.message);
    try {
      await mongoose.connect(LocalDBurl);
      console.log("✅ Local MongoDB connected successfully!");
    } catch (localErr) {
      console.error("❌ Fatal MongoDB connection error:", localErr.message);
    }
  }
}

// Auto-fix: Drop stale unique index on notificationId if it exists (causes E11000 duplicate key with null values)
async function fixStaleIndexes() {
  try {
    await mongoose.connection.asPromise(); // wait for connection
    const db = mongoose.connection.db;
    if (!db) return;
    const collection = db.collection("customernotifications");
    const indexes = await collection.indexes().catch(() => []);
    const badIndex = indexes.find(idx => idx.name === "notificationId_1");
    if (badIndex) {
      await collection.dropIndex("notificationId_1");
      console.log("🔧 Fixed: Dropped stale index 'notificationId_1' from customernotifications");
    }
  } catch (err) {
    // Non-fatal - log but don't crash
    console.warn("⚠️ Index fix notice:", err.message);
  }
}

connectDB().then(() => fixStaleIndexes());


const rideRoutes = require("./Route/rideRoute");
const driverHireRoutes = require("./Route/driverHireRoute");
const scheduleRideRoutes = require("./Route/scheduleRideRoute");
const travelTourismRoutes = require("./Route/travelTourismRoute");

// 3. Register Routes (Customer & Common)
app.use("/", welcomeRoute);
app.use("/api/auth", customerRoutes);
app.use("/api/auth", imageRoute);
app.use("/api/auth", OtpRoute);
app.use("/api/legal", termConditionRoute);
app.use("/api/auth", loginRoute);
app.use("/api/auth", forgotPasswordRoute);

// Monthly Ride (existing - unchanged)
app.use("/api/rides", rideRoutes);
app.use("/rides", rideRoutes);
app.use("/api/ride", rideRoutes);
app.use("/api/requests", rideRoutes);
app.use("/requests", rideRoutes);

// Schedule Ride (new dedicated routes - scheduledrides collection)
app.use("/api/schedule-rides", scheduleRideRoutes);
app.use("/api/scheduled-rides", scheduleRideRoutes);
app.use("/api/scheduledrides", scheduleRideRoutes);
app.use("/api/schedulerides", scheduleRideRoutes);
app.use("/schedule-rides", scheduleRideRoutes);
app.use("/scheduled-rides", scheduleRideRoutes);
app.use("/admin/schedule-rides", scheduleRideRoutes);
app.use("/admin/scheduled-rides", scheduleRideRoutes);

// Travel & Tourism (new dedicated routes - traveltourismrequests collection)
app.use("/api/travel-requests", travelTourismRoutes);
app.use("/api/travel-tourism", travelTourismRoutes);
app.use("/api/traveltourism", travelTourismRoutes);
app.use("/travel-requests", travelTourismRoutes);
app.use("/travel-tourism", travelTourismRoutes);
app.use("/admin/travel-requests", travelTourismRoutes);
app.use("/admin/travel-tourism", travelTourismRoutes);

// Hire Driver (existing - driverhirerequests collection)
app.use("/api/driver-hire", driverHireRoutes);
app.use("/driver-hire", driverHireRoutes);
app.use("/admin/driver-hire", driverHireRoutes);
app.use("/recurringRide", rideRoutes);
app.use("/driver-selection", rideRoutes);
app.use("/api/driver-selection", rideRoutes);



// 4. Register Routes (Driver & Vehicle)
app.use("/driver", driverRoutes);
app.use("/vehicle", vehicleRoutes);
app.use("/password", driverPasswordRoutes);
app.use("/admin/auth", adminAuthRoutes);
app.use("/admin/rides", rideRoutes);
app.use("/admin/driver-hire", driverHireRoutes);
app.use("/admin/driver-selection", rideRoutes);
app.use("/admin", driverAdminRoutes);

//app.use("/api/referral", referralRoutes);

const PORT = process.env.PORT || 3000;
server.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 Backend Server running on http://0.0.0.0:${PORT} (REST + WebSocket)`);
  console.log(`🔌 Socket.IO ready for real-time Admin Portal updates`);
});