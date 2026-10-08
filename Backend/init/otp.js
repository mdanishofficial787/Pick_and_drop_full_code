const otpdata = [

  {
    customerId: "66a123456789abcdef123456",

    otp: "123456",

    otpExpiresAt: new Date(
      Date.now() + 5 * 60 * 1000
    ),

    otpAttempts: 0,

    verified: false
  },


  {
    customerId: "66a123456789abcdef123457",

    otp: "654321",

    otpExpiresAt: new Date(
      Date.now() + 5 * 60 * 1000
    ),

    otpAttempts: 1,

    verified: false
  },


  {
    customerId: "66a123456789abcdef123458",

    otp: "987654",

    otpExpiresAt: new Date(
      Date.now() + 5 * 60 * 1000
    ),

    otpAttempts: 0,

    verified: true
  }

];


module.exports = { otpdata };
