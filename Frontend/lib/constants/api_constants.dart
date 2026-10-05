import 'package:flutter/foundation.dart';

class ApiConstants {
  // Your PC's Local Network IP (allows physical mobile connected via USB / Wi-Fi to reach Backend)
  static const String serverIp = '192.168.88.90';
  static const String serverPort = '3000';

  // Optional manual override if needed
  static String? customBaseUrl;

  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) {
      return customBaseUrl!;
    }
    if (kIsWeb) {
      return 'http://localhost:$serverPort';
    } else {
      // Physical Android phone / Emulator / iOS:
      return 'http://$serverIp:$serverPort';
    }
  }

  // Customer Auth Endpoints
  static String get customerSignup => '$baseUrl/api/auth/signup';
  static String get customerLogin => '$baseUrl/api/auth/login';
  static String get customerGoogleAuth => '$baseUrl/api/auth/google';
  static String get customerVerifyOtp => '$baseUrl/api/auth/verify-otp';
  static String get customerResendOtp => '$baseUrl/api/auth/resend-otp';
  static String get checkPhone => '$baseUrl/api/auth/check-phone';
  static String get checkSession => '$baseUrl/api/auth/check-session';
  static String get profilePicture => '$baseUrl/api/auth/profile-picture';
  static String get customerUpdateProfile => '$baseUrl/api/auth/update-profile';

  // Forgot Password Endpoints
  static String get forgotPasswordSendOtp => '$baseUrl/api/auth/forgot-password/send-otp';
  static String get forgotPasswordVerifyOtp => '$baseUrl/api/auth/forgot-password/verify-otp';
  static String get forgotPasswordStatus => '$baseUrl/api/auth/forgot-password/status';
  static String get forgotPasswordReset => '$baseUrl/api/auth/forgot-password/reset-password';

  // Legal & Terms
  static String get termsConditions => '$baseUrl/api/legal/terms-conditions';

  // Driver Endpoints
  static String get driverRegister => '$baseUrl/driver/register';
  static String get driverLogin => '$baseUrl/driver/login';
  static String get vehicleRegister => '$baseUrl/driver/register-vehicle';
  static String get driverPreferredRoutes => '$baseUrl/driver/preferred-routes';
  static String get driverAvailability => '$baseUrl/driver/availability';

  // Ride & Monthly Booking Endpoints
  static String get createMonthlyRide => '$baseUrl/api/rides/monthly';
  static String get createDriverHire => '$baseUrl/api/driver-hire';
  static String get getCustomerRides => '$baseUrl/api/rides/customer';
  static String get getAllRides => '$baseUrl/api/rides';
  static String driverUnavailable(String id) => '$baseUrl/api/rides/$id/driver-unavailable';
  static String requestReplacement(String id) => '$baseUrl/api/rides/$id/request-replacement';
  static String get customerNotifications => '$baseUrl/api/rides/customer-notifications';

  // Schedule Ride Endpoints (dedicated collection: scheduledrides)
  static String get createScheduleRide => '$baseUrl/api/schedule-rides';
  static String get getAllScheduleRides => '$baseUrl/api/schedule-rides';
  static String get getCustomerScheduleRides => '$baseUrl/api/schedule-rides/customer';

  // Travel & Tourism Endpoints (dedicated collection: traveltourismrequests)
  static String get createTravelRequest => '$baseUrl/api/travel-requests';
  static String get getAllTravelRequests => '$baseUrl/api/travel-requests';
  static String get getCustomerTravelRequests => '$baseUrl/api/travel-requests/customer';
}
