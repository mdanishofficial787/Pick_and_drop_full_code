import 'dart:convert';

class CustomerUser {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? countryCode;
  final String? signupMethod;
  final bool isVerified;
  final String? photoUrl;
  final DateTime? createdAt;

  CustomerUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.countryCode,
    this.signupMethod,
    this.isVerified = false,
    this.photoUrl,
    this.createdAt,
  });

  factory CustomerUser.fromJson(Map<String, dynamic> json) {
    // Determine photo URL from either string or nested object
    String? photo;
    if (json['CustomerPhoto'] is Map) {
      photo = json['CustomerPhoto']['url'];
    } else if (json['photo'] is String) {
      photo = json['photo'];
    } else if (json['CustomerPhoto'] is String) {
      photo = json['CustomerPhoto'];
    }

    return CustomerUser(
      id: json['id'] ?? json['_id'] ?? '',
      fullName: json['fullName'] ?? json['name'] ?? '',
      email: json['Email'] ?? json['email'] ?? '',
      phoneNumber: json['PhoneNumber'] ?? json['phoneNumber'] ?? json['phone'],
      countryCode: json['countryCode'] ?? '+92',
      signupMethod: json['SignupMethod'] ?? json['signupMethod'] ?? 'Email',
      isVerified: json['isVerified'] == true,
      photoUrl: photo,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'signupMethod': signupMethod,
      'isVerified': isVerified,
      'photo': photoUrl,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory CustomerUser.fromJsonString(String source) =>
      CustomerUser.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

class AuthResponse {
  final bool success;
  final String message;
  final String? token;
  final CustomerUser? customer;
  final String? userId;

  AuthResponse({
    required this.success,
    required this.message,
    this.token,
    this.customer,
    this.userId,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    CustomerUser? user;
    if (json['customer'] != null && json['customer'] is Map<String, dynamic>) {
      user = CustomerUser.fromJson(json['customer'] as Map<String, dynamic>);
    }

    return AuthResponse(
      success: json['success'] == true,
      message: json['message'] ?? '',
      token: json['token'],
      customer: user,
      userId: json['userId'] ?? json['id'],
    );
  }
}
