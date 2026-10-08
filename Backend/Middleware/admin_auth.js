const jwt = require("jsonwebtoken");

module.exports = (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;

        if (!authHeader) {
            return res.status(401).json({
                success: false,
                message: "No token provided",
            });
        }

        const token = authHeader.split(" ")[1];

        if (!token) {
            return res.status(401).json({
                success: false,
                message: "Invalid authorization format",
            });
        }

        const decoded = jwt.verify(token, process.env.JWT_SECRET);

        // Only tokens issued by the admin login (isAdmin: true) may pass.
        // This stops a normal driver's token from being reused on admin routes.
        if (!decoded.isAdmin) {
            return res.status(403).json({
                success: false,
                message: "Admin access only",
            });
        }

        req.admin = decoded;
        next();
    } catch (err) {
        return res.status(401).json({
            success: false,
            message: "Session expired or invalid token",
        });
    }
};
