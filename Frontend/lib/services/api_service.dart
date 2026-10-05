import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiResponse {
  final int statusCode;
  final bool isSuccess;
  final dynamic data;
  final String? message;

  ApiResponse({
    required this.statusCode,
    required this.isSuccess,
    this.data,
    this.message,
  });
}

class ApiService {
  static const Duration timeoutDuration = Duration(seconds: 25);

  static Future<Map<String, String>> _getHeaders({bool requireAuth = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requireAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  // GET Request
  static Future<ApiResponse> get(String url, {bool requireAuth = false}) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(timeoutDuration);

      return _processResponse(response);
    } catch (e) {
      return _handleError(e);
    }
  }

  // POST Request
  static Future<ApiResponse> post(
    String url, {
    Map<String, dynamic>? body,
    bool requireAuth = false,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);

      return _processResponse(response);
    } catch (e) {
      return _handleError(e);
    }
  }

  // PUT Request
  static Future<ApiResponse> put(
    String url, {
    Map<String, dynamic>? body,
    bool requireAuth = false,
  }) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .put(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);

      return _processResponse(response);
    } catch (e) {
      return _handleError(e);
    }
  }

  // DELETE Request
  static Future<ApiResponse> delete(String url, {bool requireAuth = false}) async {
    try {
      final headers = await _getHeaders(requireAuth: requireAuth);
      final response = await http
          .delete(Uri.parse(url), headers: headers)
          .timeout(timeoutDuration);

      return _processResponse(response);
    } catch (e) {
      return _handleError(e);
    }
  }

  // Multipart POST / PUT Request (e.g. for image uploads)
  static Future<ApiResponse> multipart({
    required String method,
    required String url,
    required Map<String, String> fields,
    String? fileField,
    Uint8List? fileBytes,
    String? filename,
    bool requireAuth = false,
  }) async {
    try {
      final request = http.MultipartRequest(method, Uri.parse(url));

      if (requireAuth) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
      }

      request.fields.addAll(fields);

      if (fileField != null && fileBytes != null && filename != null) {
        final lower = filename.toLowerCase();
        final String subtype;
        if (lower.endsWith('.png')) {
          subtype = 'png';
        } else if (lower.endsWith('.webp')) {
          subtype = 'webp';
        } else if (lower.endsWith('.gif')) {
          subtype = 'gif';
        } else {
          subtype = 'jpeg';
        }

        request.files.add(
          http.MultipartFile.fromBytes(
            fileField,
            fileBytes,
            filename: filename,
            contentType: MediaType('image', subtype),
          ),
        );
      }

      final streamedResponse = await request.send().timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);

      return _processResponse(response);
    } catch (e) {
      return _handleError(e);
    }
  }

  static ApiResponse _processResponse(http.Response response) {
    dynamic parsedData;
    String? message;

    try {
      if (response.body.isNotEmpty) {
        parsedData = jsonDecode(response.body);
        if (parsedData is Map<String, dynamic>) {
          message = parsedData['message']?.toString();
        }
      }
    } catch (_) {
      parsedData = response.body;
      message = response.body;
    }

    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;

    return ApiResponse(
      statusCode: response.statusCode,
      isSuccess: isSuccess,
      data: parsedData,
      message: message,
    );
  }

  static ApiResponse _handleError(dynamic error) {
    debugPrint('API Error: $error');
    String msg = 'Could not connect to the server. Please check your network or server status.';
    return ApiResponse(
      statusCode: 500,
      isSuccess: false,
      message: msg,
      data: {'error': error.toString()},
    );
  }
}
