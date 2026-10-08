const transporter = require("../config/email");

const sendEmail = async ({
    to,
    subject,
    text,
    html,
}) => {
    try {
        const mailOptions = {
            from: `"Ride & Serve" <${process.env.EMAIL_USER}>`,
            to,
            subject,
            text,
            html,
        };

        console.log("Sending email to:", to);
        console.log("Email subject:", subject);

        const info = await transporter.sendMail(mailOptions);

        console.log("Email sent successfully:", info.messageId);
        return info;
    } catch (error) {
        console.error("Send Email Error:", error);
        throw error;
    }
};

module.exports = sendEmail;
