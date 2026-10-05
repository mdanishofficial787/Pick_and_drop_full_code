import 'package:ride_and_serve/constants/api_constants.dart';

// Central place for backend base URL and endpoints
String get kBaseUrl => ApiConstants.baseUrl;

String get kCustomerSignupEndpoint => ApiConstants.customerSignup;
String get kCustomerLoginEndpoint => ApiConstants.customerLogin;
String get kCustomerGoogleEndpoint => ApiConstants.customerGoogleAuth;
String get kVerifyCustomerOtpEndpoint => ApiConstants.customerVerifyOtp;
String get kResendCustomerOtpEndpoint => ApiConstants.customerResendOtp;

// Forgot Password
String get kSendOtpEndpoint => ApiConstants.forgotPasswordSendOtp;
String get kVerifyOtpEndpoint => ApiConstants.forgotPasswordReset;
String get kResetPasswordEndpoint => ApiConstants.forgotPasswordReset;

// Driver Endpoints
String get kDriverRegisterEndpoint => ApiConstants.driverRegister;
String get kDriverLoginEndpoint => ApiConstants.driverLogin;
String get kVehicleRegisterEndpoint => ApiConstants.vehicleRegister;
String get kSavePreferredRoutesEndpoint => ApiConstants.driverPreferredRoutes;
String get kSaveAvailabilityEndpoint => ApiConstants.driverAvailability;
String get kDispatchBaseUrl => kBaseUrl;
String get kReportIssueEndpoint => '$kBaseUrl/driver/report-issue';
