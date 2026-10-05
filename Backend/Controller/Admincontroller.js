const Driver = require("../schema/Driver");
const Vehicle = require("../schema/Vehicle");

// ======================================================
// 1. GET ALL PENDING DRIVERS
// ======================================================

exports.getPendingDrivers = async (req, res) => {
    try {
        const drivers = await Driver.find({
            verificationStatus: "Pending",
        })
            .select("-Password")
            .sort({ createdAt: -1 });

        return res.status(200).json({
            success: true,
            count: drivers.length,
            drivers,
        });

    } catch (error) {
        console.error(
            "Get Pending Drivers Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch pending drivers",
            error: error.message,
        });
    }
};


// ======================================================
// 2. GET ALL DRIVERS
// ======================================================

exports.getAllDrivers = async (req, res) => {
    try {
        const drivers = await Driver.find()
            .select("-Password")
            .sort({ createdAt: -1 });

        return res.status(200).json({
            success: true,
            count: drivers.length,
            drivers,
        });

    } catch (error) {
        console.error(
            "Get All Drivers Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch drivers",
            error: error.message,
        });
    }
};


// ======================================================
// 3. GET ALL VERIFIED DRIVERS
// ======================================================

exports.getVerifiedDrivers = async (req, res) => {
    try {
        const drivers = await Driver.find({
            verificationStatus: "Verified",
        })
            .select("-Password")
            .sort({ updatedAt: -1 });

        return res.status(200).json({
            success: true,
            count: drivers.length,
            drivers,
        });

    } catch (error) {
        console.error(
            "Get Verified Drivers Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch verified drivers",
            error: error.message,
        });
    }
};


// ======================================================
// 4. GET ALL REJECTED DRIVERS
// ======================================================

exports.getRejectedDrivers = async (req, res) => {
    try {
        const drivers = await Driver.find({
            verificationStatus: "Rejected",
        })
            .select("-Password")
            .sort({ updatedAt: -1 });

        return res.status(200).json({
            success: true,
            count: drivers.length,
            drivers,
        });

    } catch (error) {
        console.error(
            "Get Rejected Drivers Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch rejected drivers",
            error: error.message,
        });
    }
};


// ======================================================
// 5. VERIFY / REJECT DRIVER
// ======================================================

exports.updateVerificationStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { verificationStatus } = req.body;

        // ------------------------------------------
        // VALIDATE STATUS
        // ------------------------------------------

        if (
            !["Verified", "Rejected"].includes(
                verificationStatus
            )
        ) {
            return res.status(400).json({
                success: false,
                message:
                    "verificationStatus must be either Verified or Rejected",
            });
        }

        // ------------------------------------------
        // FIND DRIVER
        // ------------------------------------------

        const driver = await Driver.findById(id);

        if (!driver) {
            return res.status(404).json({
                success: false,
                message: "Driver not found",
            });
        }

        // ------------------------------------------
        // ONLY PENDING DRIVER CAN BE VERIFIED/REJECTED
        // ------------------------------------------

        if (
            driver.verificationStatus !== "Pending"
        ) {
            return res.status(400).json({
                success: false,
                message:
                    `Driver is already ${driver.verificationStatus.toLowerCase()}.`,
            });
        }

        // ------------------------------------------
        // UPDATE STATUS
        // ------------------------------------------

        driver.verificationStatus =
            verificationStatus;

        await driver.save();

        // ------------------------------------------
        // RESPONSE
        // ------------------------------------------

        return res.status(200).json({
            success: true,

            message:
                verificationStatus === "Verified"
                    ? "Driver verified successfully"
                    : "Driver rejected successfully",

            driver: {
                _id: driver._id,

                driverReferenceId:
                    driver.driverReferenceId,

                Name: driver.Name,

                PhoneNumber:
                    driver.PhoneNumber,

                CountryCode:
                    driver.CountryCode,

                CountryIso:
                    driver.CountryIso,

                Email: driver.Email,

                CnicNumber:
                    driver.CnicNumber,

                License:
                    driver.License,

                verificationStatus:
                    driver.verificationStatus,

                updatedAt:
                    driver.updatedAt,
            },
        });

    } catch (error) {
        console.error(
            "Update Driver Verification Error:",
            error
        );

        // ------------------------------------------
        // INVALID MONGODB ID
        // ------------------------------------------

        if (error.name === "CastError") {
            return res.status(400).json({
                success: false,
                message: "Invalid driver ID",
            });
        }

        // ------------------------------------------
        // GENERAL ERROR
        // ------------------------------------------

        return res.status(500).json({
            success: false,
            message:
                "Failed to update driver verification status",
            error: error.message,
        });
    }
};


// ======================================================
// 6. GET ALL PENDING VEHICLES
// ======================================================

exports.getPendingVehicles = async (req, res) => {
    try {
        const vehicles = await Vehicle.find({
            verificationStatus: "Pending",
        })
            .populate(
                "driver",
                "Name PhoneNumber CountryCode CountryIso driverReferenceId"
            )
            .sort({ createdAt: -1 });

        return res.status(200).json({
            success: true,
            count: vehicles.length,
            vehicles,
        });

    } catch (error) {
        console.error(
            "Get Pending Vehicles Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch pending vehicles",
            error: error.message,
        });
    }
};


// ======================================================
// 7. GET ALL VEHICLES
// ======================================================

exports.getAllVehicles = async (req, res) => {
    try {
        const vehicles = await Vehicle.find()
            .populate(
                "driver",
                "Name PhoneNumber CountryCode CountryIso driverReferenceId"
            )
            .sort({ createdAt: -1 });

        return res.status(200).json({
            success: true,
            count: vehicles.length,
            vehicles,
        });

    } catch (error) {
        console.error(
            "Get All Vehicles Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch vehicles",
            error: error.message,
        });
    }
};
// 8. GET ALL VERIFIED VEHICLES
exports.getVerifiedVehicles = async (req, res) => {
    try {
        const vehicles = await Vehicle.find({
            verificationStatus: "Verified",
        })
            .populate(
                "driver",
                "Name PhoneNumber CountryCode CountryIso driverReferenceId"
            )
            .sort({ updatedAt: -1 });
        return res.status(200).json({
            success: true,
            count: vehicles.length,
            vehicles,
        });

    } catch (error) {
        console.error(
            "Get Verified Vehicles Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch verified vehicles",
            error: error.message,
        });
    }
};
// 9. GET ALL REJECTED VEHICLES
exports.getRejectedVehicles = async (req, res) => {
    try {
        const vehicles = await Vehicle.find({
            verificationStatus: "Rejected",
        })
            .populate(
                "driver",
                "Name PhoneNumber CountryCode CountryIso driverReferenceId"
            )
            .sort({ updatedAt: -1 });

        return res.status(200).json({
            success: true,
            count: vehicles.length,
            vehicles,
        });

    } catch (error) {
        console.error(
            "Get Rejected Vehicles Error:",
            error
        );

        return res.status(500).json({
            success: false,
            message: "Failed to fetch rejected vehicles",
            error: error.message,
        });
    }
};
// 10. VERIFY / REJECT VEHICLE
exports.updateVehicleVerificationStatus = async (
    req,
    res
) => {
    try {
        const { id } = req.params;
        const { verificationStatus } =
            req.body;

        // VALIDATE STATUS
        if (
            !["Verified", "Rejected"].includes(
                verificationStatus
            )
        ) {
            return res.status(400).json({
                success: false,
                message:
                    "verificationStatus must be either Verified or Rejected",
            });
        }

        // FIND VEHICLE
        const vehicle =
            await Vehicle.findById(id);

        if (!vehicle) {
            return res.status(404).json({
                success: false,
                message: "Vehicle not found",
            });
        }

        // ONLY PENDING VEHICLE CAN BE VERIFIED/REJECTED
        if (
            vehicle.verificationStatus !==
            "Pending"
        ) {
            return res.status(400).json({
                success: false,
                message:
                    `Vehicle is already ${vehicle.verificationStatus.toLowerCase()}.`,
            });
        }

        // UPDATE STATUS
        vehicle.verificationStatus =
            verificationStatus;
        await vehicle.save();

        // RESPONSE
        return res.status(200).json({
            success: true,

            message:
                verificationStatus === "Verified"
                    ? "Vehicle verified successfully"
                    : "Vehicle rejected successfully",

            vehicle: {
                _id: vehicle._id,

                driver:
                    vehicle.driver,
                vehicleMake:
                    vehicle.vehicleMake,
                vehicleModel:
                    vehicle.vehicleModel,
                variant:
                    vehicle.variant,
                numberOfSeats:
                    vehicle.numberOfSeats,

                registrationNumber:
                    vehicle.registrationNumber,
                vehicleColor:
                    vehicle.vehicleColor,
                verificationStatus:
                    vehicle.verificationStatus,
                updatedAt:
                    vehicle.updatedAt,
            },
        });

    } catch (error) {
        console.error(
            "Update Vehicle Verification Error:",
            error
        );

        // INVALID MONGODB ID
        if (error.name === "CastError") {
            return res.status(400).json({
                success: false,
                message: "Invalid vehicle ID",
            });
        }
        // GENERAL ERROR
        return res.status(500).json({
            success: false,
            message:
                "Failed to update vehicle verification status",
            error: error.message,
        });
    }
};

// ======================================================
// 10A. ADMIN PASSWORD RESET APPROVALS
// ======================================================
const PasswordResetRequest = require("../schema/PasswordResetRequest");
const jwt = require("jsonwebtoken");
const Customer = require("../schema/user");

exports.getPendingPasswordResets = async (req, res) => {
    try {
        const requests = await PasswordResetRequest.find({
            status: "Pending"
        }).sort({ createdAt: -1 });

        return res.status(200).json({
            success: true,
            count: requests.length,
            requests
        });
    } catch (error) {
        console.error("Get Pending Password Resets Error:", error);
        return res.status(500).json({
            success: false,
            message: "Failed to fetch pending password resets",
            error: error.message
        });
    }
};

exports.updatePasswordResetStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;

        if (!["Approved", "Rejected"].includes(status)) {
            return res.status(400).json({
                success: false,
                message: "Status must be either Approved or Rejected"
            });
        }

        const request = await PasswordResetRequest.findById(id);

        if (!request) {
            return res.status(404).json({
                success: false,
                message: "Password reset request not found"
            });
        }

        if (request.status !== "Pending") {
            return res.status(400).json({
                success: false,
                message: `Request is already ${request.status.toLowerCase()}`
            });
        }

        request.status = status;

        if (status === "Approved") {
            // Find the user to get their ID for the token
            let userId = null;
            if (request.userType === "Customer") {
                const customer = await Customer.findOne({
                    $or: [
                        { Email: request.email },
                        { PhoneNumber: request.email }
                    ]
                });
                if (customer) userId = customer._id;
            } else if (request.userType === "Driver") {
                const driver = await Driver.findOne({
                    $or: [
                        { Email: request.email },
                        { PhoneNumber: request.email }
                    ]
                });
                if (driver) userId = driver._id;
            }

            if (!userId) {
                return res.status(404).json({
                    success: false,
                    message: "User account not found for this request"
                });
            }

            // Generate resetToken valid for 1 hour
            const resetToken = jwt.sign(
                { id: userId, email: request.email, purpose: "password_reset" },
                process.env.JWT_SECRET,
                { expiresIn: "1h" }
            );

            request.resetToken = resetToken;
        }

        await request.save();

        return res.status(200).json({
            success: true,
            message: `Password reset request ${status.toLowerCase()}`,
            request
        });

    } catch (error) {
        console.error("Update Password Reset Status Error:", error);
        return res.status(500).json({
            success: false,
            message: "Failed to update password reset status",
            error: error.message
        });
    }
};

const { Parser } = require("json2csv");

// ======================================================
// 11. EXPORT DRIVERS TO CSV
// ======================================================
exports.exportDriversCSV = async (req, res) => {
    try {
        const drivers = await Driver.find().select("-Password").lean();
        const fields = ["driverReferenceId", "Name", "PhoneNumber", "Email", "CnicNumber", "License", "verificationStatus", "createdAt"];
        const json2csvParser = new Parser({ fields });
        const csv = json2csvParser.parse(drivers);

        res.header("Content-Type", "text/csv");
        res.attachment("drivers_export.csv");
        return res.send(csv);
    } catch (error) {
        console.error("Export Drivers CSV Error:", error);
        return res.status(500).json({
            success: false,
            message: "Failed to export drivers",
            error: error.message,
        });
    }
};

// ======================================================
// 12. EXPORT VEHICLES TO CSV
// ======================================================
exports.exportVehiclesCSV = async (req, res) => {
    try {
        const vehicles = await Vehicle.find().populate("driver", "Name PhoneNumber").lean();
        const fields = [
            { label: 'Driver Name', value: 'driver.Name' },
            { label: 'Driver Phone', value: 'driver.PhoneNumber' },
            'vehicleMake', 
            'vehicleModel', 
            'variant', 
            'registrationNumber', 
            'verificationStatus', 
            'createdAt'
        ];
        const json2csvParser = new Parser({ fields });
        const csv = json2csvParser.parse(vehicles);

        res.header("Content-Type", "text/csv");
        res.attachment("vehicles_export.csv");
        return res.send(csv);
    } catch (error) {
        console.error("Export Vehicles CSV Error:", error);
        return res.status(500).json({
            success: false,
            message: "Failed to export vehicles",
            error: error.message,
        });
    }
};