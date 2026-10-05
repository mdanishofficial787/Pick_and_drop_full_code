const nodemailer = require("nodemailer");

const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASSWORD || process.env.EMAIL_APP
    }
});



transporter.verify((error, success) => {
    if (error) {
        console.error("❌ Gmail SMTP connection failed:");
        console.error(error);
    } else {
        console.log("✅ Gmail SMTP is ready");
    }
});

const sendOTPEmail = async (email, otp) => {

    try {

        const mailOptions = {
            from: `"Ride & Serve" <${process.env.EMAIL_USER}>`,

            to: email,

            subject: "Ride & Serve - Email Verification OTP",

            html: `
                <!DOCTYPE html>

                <html>

                <head>
                    <meta charset="UTF-8">
                    <title>Ride & Serve OTP</title>
                </head>

                <body style="
                    margin: 0;
                    padding: 0;
                    background-color: #f5f6f8;
                    font-family: Arial, sans-serif;
                ">

                    <div style="
                        max-width: 600px;
                        margin: 40px auto;
                        background-color: white;
                        padding: 40px;
                        border-radius: 12px;
                    ">

                        <h2 style="
                            color: #1959F6;
                            text-align: center;
                        ">
                            Ride & Serve
                        </h2>

                        <h3 style="
                            color: #222;
                        ">
                            Verify Your Email
                        </h3>

                        <p style="
                            color: #555;
                            font-size: 16px;
                        ">
                            Thank you for registering with Ride & Serve.
                            Please use the verification code below:
                        </p>

                        <div style="
                            text-align: center;
                            margin: 30px 0;
                        ">

                            <span style="
                                display: inline-block;
                                background-color: #f0f3ff;
                                color: #1959F6;
                                font-size: 32px;
                                font-weight: bold;
                                letter-spacing: 8px;
                                padding: 15px 25px;
                                border-radius: 10px;
                            ">
                                ${otp}
                            </span>

                        </div>

                        <p style="
                            color: #777;
                            font-size: 14px;
                        ">
                            This OTP will expire in 5 minutes.
                        </p>

                        <p style="
                            color: #777;
                            font-size: 14px;
                        ">
                            If you did not create a Ride & Serve account,
                            you can safely ignore this email.
                        </p>

                    </div>

                </body>

                </html>
            `
        };

        const info = await transporter.sendMail(mailOptions);

        console.log(
            "OTP email sent successfully:",
            info.messageId
        );

        return true;

    } catch (error) {

        console.error(
            "OTP Email Error:",
            error
        );

        throw error;
    }
};

module.exports = sendOTPEmail;