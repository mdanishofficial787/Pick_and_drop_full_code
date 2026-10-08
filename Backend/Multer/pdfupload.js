const multer = require("multer");

const storage = multer.memoryStorage();

const pdfUpload = multer({
    storage: storage,
    fileFilter: (req, file, cb) => {

        if (file.mimetype === "application/pdf") {
            cb(null, true);
        } else {
            cb(new Error("Only PDF files are allowed"), false);
        }

    }
});

module.exports = pdfUpload;
