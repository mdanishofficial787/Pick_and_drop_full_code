import 'package:ride_and_serve/constants/api_constants.dart';
import 'package:ride_and_serve/services/api_service.dart';

class MonthlyRideResponse {
  final bool success;
  final String message;
  final String? requestId;
  final dynamic data;

  MonthlyRideResponse({
    required this.success,
    required this.message,
    this.requestId,
    this.data,
  });

  factory MonthlyRideResponse.fromJson(Map<String, dynamic> json) {
    final rideData = json['ride'] ?? json['data'];
    final reqId = rideData != null ? rideData['requestId']?.toString() : null;
    return MonthlyRideResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      requestId: reqId,
      data: rideData,
    );
  }
}

class RideService {
  static Future<MonthlyRideResponse> bookMonthlyRide({
    required String passengerName,
    required String passengerPhone,
    String? passengerEmail,
    required String pickupLocation,
    required String dropoffLocation,
    required String startingFrom,
    required String timeToReach,
    required String timeToLeave,
    required String scheduleType,
    String? scheduleTime,
    Map<String, dynamic>? customSchedule,
    required String vehicleTypeSelection,
    required String seatingArrangement,
    required String vehicleType,
    required String acPreference,
    int passengersCount = 1,
    int fare = 9500,
    String? customerId,
    String? notes,
    String? tripType,
    String? genderPreference,
  }) async {
    final body = {
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'passengerEmail': passengerEmail,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'startingFrom': startingFrom,
      'timeToReach': timeToReach,
      'timeToLeave': timeToLeave,
      'scheduleType': scheduleType,
      'scheduleTime': scheduleTime,
      'customSchedule': customSchedule,
      'vehicleTypeSelection': vehicleTypeSelection,
      'seatingArrangement': seatingArrangement,
      'vehicleType': vehicleType,
      'acPreference': acPreference,
      'passengersCount': passengersCount,
      'fare': fare,
      'customerId': customerId,
      'notes': notes ?? '',
      'tripType': tripType ?? 'One Way',
      'genderPreference': genderPreference ?? 'Both',
    };

    final response = await ApiService.post(
      ApiConstants.createMonthlyRide,
      body: body,
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      return MonthlyRideResponse.fromJson(response.data as Map<String, dynamic>);
    } else {
      return MonthlyRideResponse(
        success: false,
        message: response.message ?? 'Failed to submit monthly booking request.',
      );
    }
  }

  static Future<MonthlyRideResponse> submitDriverHireRequest({
    required String customerName,
    required String customerPhone,
    String? customerEmail,
    required String cnic,
    required String bookingDate,
    required String pickupLocation,
    required String dropoffLocation,
    required String timeToReach,
    required String offTime,
    int fare = 3500,
    String? customerId,
    String? notes,
  }) async {
    final body = {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'cnic': cnic,
      'bookingDate': bookingDate,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'timeToReach': timeToReach,
      'offTime': offTime,
      'fare': fare,
      'customerId': customerId,
      'notes': notes ?? '',
    };

    final response = await ApiService.post(
      ApiConstants.createDriverHire,
      body: body,
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final json = response.data as Map<String, dynamic>;
      final reqId = json['requestId'] ?? json['request']?['requestId'];
      return MonthlyRideResponse(
        success: json['success'] == true,
        message: json['message']?.toString() ?? 'Driver hiring request submitted',
        requestId: reqId?.toString(),
        data: json['request'],
      );
    } else {
      return MonthlyRideResponse(
        success: false,
        message: response.message ?? 'Failed to submit driver hiring request.',
      );
    }
  }

  // ─── Schedule Ride (dedicated collection: scheduledrides) ───────────────────
  static Future<MonthlyRideResponse> bookScheduleRide({
    required String passengerName,
    required String passengerPhone,
    String? passengerEmail,
    required String pickupLocation,
    required String dropoffLocation,
    required String startingFrom,
    required String timeToReach,
    required String timeToLeave,
    String rideType = 'One Way',
    String vehicleType = 'Sedan Executive',
    String acPreference = 'AC',
    String genderPreference = 'Both',
    int fare = 7500,
    String? customerId,
    String? notes,
    Map<String, dynamic>? customSchedule,
  }) async {
    final body = {
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'passengerEmail': passengerEmail,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'startingFrom': startingFrom,
      'timeToReach': timeToReach,
      'timeToLeave': timeToLeave,
      'rideType': rideType,
      'vehicleType': vehicleType,
      'acPreference': acPreference,
      'genderPreference': genderPreference,
      'fare': fare,
      'customerId': customerId,
      'notes': notes ?? '',
      'customSchedule': customSchedule ?? {},
    };

    final response = await ApiService.post(
      ApiConstants.createScheduleRide,
      body: body,
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final json = response.data as Map<String, dynamic>;
      final rideData = json['ride'] ?? json['data'];
      final reqId = rideData != null ? rideData['requestId']?.toString() : json['requestId']?.toString();
      return MonthlyRideResponse(
        success: json['success'] == true,
        message: json['message']?.toString() ?? 'Schedule ride submitted',
        requestId: reqId,
        data: rideData,
      );
    } else {
      return MonthlyRideResponse(
        success: false,
        message: response.message ?? 'Failed to submit schedule ride request.',
      );
    }
  }

  // ─── Travel & Tourism (dedicated collection: traveltourismrequests) ──────────
  static Future<MonthlyRideResponse> submitTravelRequest({
    required String passengerName,
    required String passengerPhone,
    String? passengerEmail,
    required String cnic,
    required String pickupLocation,
    required String dropoffLocation,
    required String travelDate,
    required String travelTime,
    String returnDate = '',
    String returnTime = '',
    String returnPickupLocation = '',
    String returnDropoffLocation = '',
    String vehicleType = 'SUV',
    String acPreference = 'AC',
    int passengersCount = 4,
    int fare = 15000,
    String? customerId,
    String? notes,
    Map<String, dynamic>? customSchedule,
  }) async {
    final body = {
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'passengerEmail': passengerEmail,
      'cnic': cnic,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'travelDate': travelDate,
      'travelTime': travelTime,
      'returnDate': returnDate,
      'returnTime': returnTime,
      'returnPickupLocation': returnPickupLocation,
      'returnDropoffLocation': returnDropoffLocation,
      'vehicleType': vehicleType,
      'acPreference': acPreference,
      'passengersCount': passengersCount,
      'fare': fare,
      'customerId': customerId,
      'notes': notes ?? '',
      'customSchedule': customSchedule ?? {},
    };

    final response = await ApiService.post(
      ApiConstants.createTravelRequest,
      body: body,
    );

    if (response.isSuccess && response.data is Map<String, dynamic>) {
      final json = response.data as Map<String, dynamic>;
      final reqData = json['ride'] ?? json['request'] ?? json['data'];
      final reqId = reqData != null ? reqData['requestId']?.toString() : json['requestId']?.toString();
      return MonthlyRideResponse(
        success: json['success'] == true,
        message: json['message']?.toString() ?? 'Travel request submitted',
        requestId: reqId,
        data: reqData,
      );
    } else {
      return MonthlyRideResponse(
        success: false,
        message: response.message ?? 'Failed to submit travel request.',
      );
    }
  }
}
