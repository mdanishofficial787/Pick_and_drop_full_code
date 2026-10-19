import 'dart:convert';
import 'package:ride_and_serve/constants/api_constants.dart';

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
    // Determine photo URL from nested object or direct string keys
    String? photo;
    if (json['CustomerPhoto'] is Map) {
      final photoMap = json['CustomerPhoto'] as Map;
      final u = photoMap['url'] ?? photoMap['secure_url'];
      if (u != null && u.toString().trim().isNotEmpty) {
        photo = u.toString().trim();
      }
    }
    if ((photo == null || photo.isEmpty) && json['photo'] != null) {
      photo = json['photo'].toString().trim();
    }
    if ((photo == null || photo.isEmpty) && json['photoUrl'] != null) {
      photo = json['photoUrl'].toString().trim();
    }
    if ((photo == null || photo.isEmpty) && json['CustomerPhoto'] is String) {
      photo = json['CustomerPhoto'].toString().trim();
    }
    if ((photo == null || photo.isEmpty) && json['profilePic'] != null) {
      photo = json['profilePic'].toString().trim();
    }

    if (photo != null && photo.isNotEmpty && !photo.startsWith('http')) {
      photo = '${ApiConstants.baseUrl}/${photo.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '')}';
    }

    return CustomerUser(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? json['name']?.toString() ?? '',
      email: json['Email']?.toString() ?? json['email']?.toString() ?? '',
      phoneNumber: json['PhoneNumber']?.toString() ?? json['phoneNumber']?.toString() ?? json['phone']?.toString(),
      countryCode: json['countryCode']?.toString() ?? '+92',
      signupMethod: json['SignupMethod']?.toString() ?? json['signupMethod']?.toString() ?? 'Email',
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
      'photoUrl': photoUrl,
      'CustomerPhoto': photoUrl != null ? {'url': photoUrl} : null,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  CustomerUser copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phoneNumber,
    String? countryCode,
    String? signupMethod,
    bool? isVerified,
    String? photoUrl,
    DateTime? createdAt,
  }) {
    return CustomerUser(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      signupMethod: signupMethod ?? this.signupMethod,
      isVerified: isVerified ?? this.isVerified,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
    );
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
