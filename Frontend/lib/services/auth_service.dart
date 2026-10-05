import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ride_and_serve/constants/api_constants.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/services/api_service.dart';

class AuthService {
  static const String _keyToken = 'auth_token';
  static const String _keyUser = 'auth_user';
  static const String _keyUserType = 'user_type';

  // 1. Customer Signup
  static Future<AuthResponse> signup({
    required String fullName,
    required String phoneNumber,
    required String countryCode,
    required String email,
    required String password,
    required String confirmPassword,
    Uint8List? photoBytes,
    String? photoFilename,
  }) async {
    final fields = <String, String>{
      'fullName': fullName.trim(),
      'PhoneNumber': phoneNumber.trim(),
      'countryCode': countryCode,
      'Email': email.trim(),
      'Password': password,
      'confirmPassword': confirmPassword,
      'termsAccepted': 'true',
      'tcVersion': '1.0',
    };

    final response = await ApiService.multipart(
      method: 'POST',
      url: ApiConstants.customerSignup,
      fields: fields,
      fileField: photoBytes != null ? 'CustomerPhoto' : null,
      fileBytes: photoBytes,
      filename: photoFilename ?? 'profile.jpg',
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      return AuthResponse.fromJson(response.data as Map<String, dynamic>);
    } else {
      return AuthResponse(
        success: false,
        message: response.message ?? 'Signup failed. Please try again.',
      );
    }
  }

  // 2. Customer Login
  static Future<AuthResponse> login({
    required String phoneNumber,
    required String countryCode,
    required String password,
  }) async {
    final response = await ApiService.post(
      ApiConstants.customerLogin,
      body: {
        'PhoneNumber': phoneNumber.trim(),
        'countryCode': countryCode,
        'Password': password,
      },
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final authResponse = AuthResponse.fromJson(response.data as Map<String, dynamic>);
      if (authResponse.token != null && authResponse.customer != null) {
        await saveSession(
          token: authResponse.token!,
          user: authResponse.customer!,
          userType: 'customer',
        );
      }
      return authResponse;
    } else {
      return AuthResponse(
        success: false,
        message: response.message ?? 'Invalid phone number or password.',
      );
    }
  }

  // 3. Verify OTP
  static Future<AuthResponse> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final response = await ApiService.post(
      ApiConstants.customerVerifyOtp,
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
      },
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final authResponse = AuthResponse.fromJson(response.data as Map<String, dynamic>);
      if (authResponse.token != null && authResponse.customer != null) {
        await saveSession(
          token: authResponse.token!,
          user: authResponse.customer!,
          userType: 'customer',
        );
      }
      return authResponse;
    } else {
      return AuthResponse(
        success: false,
        message: response.message ?? 'OTP verification failed.',
      );
    }
  }

  // 4. Resend OTP
  static Future<ApiResponse> resendOtp({required String email}) async {
    return await ApiService.post(
      ApiConstants.customerResendOtp,
      body: {'email': email.trim().toLowerCase()},
    );
  }

  // 5. Google Sign-In / Login
  static Future<AuthResponse> googleAuth({required String accessToken}) async {
    final response = await ApiService.post(
      ApiConstants.customerGoogleAuth,
      body: {'accessToken': accessToken},
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final authResponse = AuthResponse.fromJson(response.data as Map<String, dynamic>);
      if (authResponse.token != null && authResponse.customer != null) {
        await saveSession(
          token: authResponse.token!,
          user: authResponse.customer!,
          userType: 'customer',
        );
      }
      return authResponse;
    } else {
      return AuthResponse(
        success: false,
        message: response.message ?? 'Google authentication failed.',
      );
    }
  }

  // 6. Forgot Password - Send Request (Sends OTP to email)
  static Future<ApiResponse> sendForgotPasswordRequest({required String email}) async {
    return await ApiService.post(
      ApiConstants.forgotPasswordSendOtp,
      body: {'email': email.trim().toLowerCase()},
    );
  }

  // 7. Forgot Password - Verify OTP
  static Future<ApiResponse> verifyForgotPasswordOtp({
    required String email,
    required String otp,
  }) async {
    return await ApiService.post(
      ApiConstants.forgotPasswordVerifyOtp,
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
      },
    );
  }

  // 7b. Forgot Password - Check Status
  static Future<ApiResponse> checkForgotPasswordStatus({required String email}) async {
    return await ApiService.get(
      '${ApiConstants.forgotPasswordStatus}?email=${Uri.encodeComponent(email.trim().toLowerCase())}',
    );
  }

  // 8. Forgot Password - Reset Password
  static Future<ApiResponse> resetPassword({
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    return await ApiService.post(
      ApiConstants.forgotPasswordReset,
      body: {
        'resetToken': resetToken,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      },
    );
  }

  // 9. Check Active Session with Backend
  static Future<bool> checkSession() async {
    final response = await ApiService.get(
      ApiConstants.checkSession,
      requireAuth: true,
    );
    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data['customer'] != null) {
        final user = CustomerUser.fromJson(data['customer'] as Map<String, dynamic>);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyUser, user.toJsonString());
      }
      return true;
    }
    return false;
  }

  // 10. Local Session Management
  static Future<void> saveSession({
    required String token,
    required CustomerUser user,
    required String userType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUser, user.toJsonString());
    await prefs.setString(_keyUserType, userType);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<CustomerUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_keyUser);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        return CustomerUser.fromJsonString(userJson);
      } catch (e) {
        debugPrint('Error parsing stored user: $e');
      }
    }
    return null;
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<ApiResponse> updateProfile({
    required String fullName,
    required String email,
    required String phoneNumber,
    Uint8List? photoBytes,
    String? customerId,
  }) async {
    final fields = <String, String>{
      'fullName': fullName.trim(),
      'Email': email.trim(),
      'PhoneNumber': phoneNumber.trim(),
      if (customerId != null) 'customerId': customerId,
    };

    final response = await ApiService.multipart(
      method: 'PUT',
      url: ApiConstants.customerUpdateProfile,
      fields: fields,
      fileField: photoBytes != null ? 'CustomerPhoto' : null,
      fileBytes: photoBytes,
      filename: 'profile.jpg',
      requireAuth: true,
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      final updatedUserJson = data['customer'] ?? data['user'];
      if (updatedUserJson != null && updatedUserJson is Map<String, dynamic>) {
        final updatedUser = CustomerUser.fromJson(updatedUserJson);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyUser, updatedUser.toJsonString());
      }
    }
    return response;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUser);
    await prefs.remove(_keyUserType);
  }
}
