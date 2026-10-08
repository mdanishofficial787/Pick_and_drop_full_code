const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const Admin = require("../schema/Admin");

// ======================================================
// ADMIN LOGIN
// ======================================================
exports.loginAdmin = async (req, res) => {
    try {
        const { Email, Password } = req.body;

        if (!Email || !Password) {
            return res.status(400).json({
                success: false,
                message: "Email and password are required",
            });
        }

        const admin = await Admin.findOne({
            Email: Email.toLowerCase().trim(),
        });

        if (!admin) {
            return res.status(401).json({
                success: false,
                message: "Invalid email or password",
            });
        }

        const isPasswordValid = await bcrypt.compare(
            Password,
            admin.Password
        );

        if (!isPasswordValid) {
            return res.status(401).json({
                success: false,
                message: "Invalid email or password",
            });
        }

        const token = jwt.sign(
            {
                id: admin._id.toString(),
                role: admin.role,
                isAdmin: true,
            },
            process.env.JWT_SECRET,
            {
                expiresIn: "7d",
            }
        );

        return res.status(200).json({
            success: true,
            message: "Login successful",
            token,
            admin: {
                _id: admin._id,
                Name: admin.Name,
                Email: admin.Email,
                role: admin.role,
            },
        });
    } catch (error) {
        console.error("Admin Login Error:", error);
        return res.status(500).json({
            success: false,
            message: "Server error",
        });
    }
};

// ======================================================
// GET LOGGED-IN ADMIN PROFILE (used by React panel on refresh)
// ======================================================
exports.getAdminProfile = async (req, res) => {
    try {
        const admin = await Admin.findById(req.admin.id).select("-Password");

        if (!admin) {
            return res.status(404).json({
                success: false,
                message: "Admin not found",
            });
        }

        return res.status(200).json({
            success: true,
            admin,
        });
    } catch (error) {
        console.error("Get Admin Profile Error:", error);
        return res.status(500).json({
            success: false,
            message: "Server error",
        });
    }
};
