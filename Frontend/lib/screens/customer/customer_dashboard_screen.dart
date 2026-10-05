import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ride_and_serve/constants/api_constants.dart';
import 'package:ride_and_serve/constants/app_colors.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/hire_driver_screen.dart';
import 'package:ride_and_serve/screens/customer/monthly_pickup_screen.dart';
import 'package:ride_and_serve/screens/customer/driver_unavailable_screen.dart';
import 'package:ride_and_serve/screens/customer/profile_view_screen.dart';
import 'package:ride_and_serve/screens/customer/schedule_pickup_screen.dart';
import 'package:ride_and_serve/services/auth_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class CustomerDashboardScreen extends StatefulWidget {
  final CustomerUser? user;

  const CustomerDashboardScreen({super.key, this.user});

  @override
  State<CustomerDashboardScreen> createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  CustomerUser? _currentUser;
  bool _isLoading = true;
  Timer? _notificationPollTimer;
  io.Socket? _socket;

  // Real-time Notifications state
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  final Set<String> _seenRideStatusIds = {};
  bool _isFirstFetch = true;

  static const Color _primaryBlue = AppColors.primaryBlue; // Color(0xFF0066FF) / AppColors.primaryBlue
  static const Color _screenBg = Color(0xFFF4F7FC);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (widget.user != null) {
      setState(() {
        _currentUser = widget.user;
        _isLoading = false;
      });
    } else {
      final user = await AuthService.getCurrentUser();
      if (mounted) {
        setState(() {
          _currentUser = user;
          _isLoading = false;
        });
      }
    }
    _initSocketConnection();
    _startNotificationPolling();
  }

  void _initSocketConnection() {
    try {
      final baseUrl = ApiConstants.baseUrl;
      final customerId = _currentUser?.id ?? _currentUser?.phoneNumber ?? '';

      _socket = io.io(
        baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect()
            .build(),
      );

      _socket?.connect();

      _socket?.onConnect((_) {
        if (customerId.isNotEmpty) {
          _socket?.emit('join-customer', customerId);
          if (_currentUser?.phoneNumber != null) {
            _socket?.emit('join-customer', _currentUser!.phoneNumber);
          }
        }
      });

      _socket?.on('driver-unavailable', (data) {
        if (!mounted) return;
        final Map<String, dynamic> notifObj = Map<String, dynamic>.from(data is Map ? data : {});
        notifObj['isDriverUnavailable'] = true;

        final String rideId = notifObj['rideId'] ?? notifObj['requestId'] ?? '';
        final String statusKey = '${rideId}_DRIVER_UNAVAILABLE';

        if (!_seenRideStatusIds.contains(statusKey)) {
          _seenRideStatusIds.add(statusKey);
          setState(() {
            _notifications.insert(0, notifObj);
            _unreadCount++;
          });
          _showDriverUnavailableBanner(notifObj);
        }
      });

      _socket?.on('ride-updated', (data) => _handleRideUpdatedSocket(data));
      _socket?.on('ride-update', (data) => _handleRideUpdatedSocket(data));
      _socket?.on('ride_updated', (data) => _handleRideUpdatedSocket(data));

      _socket?.on('ride_accepted', (data) => _handleRideAcceptedSocket(data));
      _socket?.on('ride-accepted', (data) => _handleRideAcceptedSocket(data));
    } catch (_) {}
  }

  void _handleRideAcceptedSocket(dynamic data) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> rawPayload = Map<String, dynamic>.from(data is Map ? data : {});
      final Map<String, dynamic> rideObj = rawPayload['ride'] is Map
          ? Map<String, dynamic>.from(rawPayload['ride'])
          : rawPayload;

      final String payloadId = (rideObj['id'] ?? rideObj['_id'] ?? rideObj['requestId'] ?? rideObj['mongoId'] ?? '').toString();
      final String customerId = (rideObj['customerId'] ?? '').toString();
      final String passengerPhone = (rideObj['passengerPhone'] ?? rideObj['phone'] ?? '').toString();
      final String passengerEmail = (rideObj['passengerEmail'] ?? rideObj['email'] ?? '').toString();

      final currentUserId = _currentUser?.id ?? '';
      final currentUserPhone = _currentUser?.phoneNumber ?? '';
      final currentUserEmail = _currentUser?.email ?? '';

      bool matchesUser = false;
      if (currentUserId.isNotEmpty && customerId == currentUserId) matchesUser = true;
      if (currentUserPhone.isNotEmpty && passengerPhone == currentUserPhone) matchesUser = true;
      if (currentUserEmail.isNotEmpty && passengerEmail == currentUserEmail) matchesUser = true;

      if (!matchesUser && payloadId.isNotEmpty) {
        matchesUser = _notifications.any((n) =>
          (n['id'] == payloadId || n['requestId'] == payloadId || n['rideId'] == payloadId || n['mongoId'] == payloadId)
        );
      }

      if (matchesUser || (customerId.isEmpty && passengerPhone.isEmpty && currentUserPhone.isEmpty)) {
        final String statusKey = '${payloadId}_DRIVER_ACCEPTED';

        if (!_seenRideStatusIds.contains(statusKey)) {
          _seenRideStatusIds.add(statusKey);

          final driverDetails = rideObj['driverDetails'] ?? rideObj['driver'] ?? {};
          final driverName = driverDetails['name'] ?? 'A driver';
          final driverVehicle = driverDetails['vehicle'] ?? 'their vehicle';

          final notifObj = {
            'id': payloadId,
            'title': '🚗 Driver Assigned!',
            'subtitle': '$driverName is on their way with $driverVehicle.',
            'time': 'Just Now',
            'status': 'ACCEPTED',
            'requestId': payloadId,
            'rideId': payloadId,
            'driverDetails': driverDetails,
            'pickup': rideObj['pickupLocation'] ?? 'Pickup Point',
            'destination': rideObj['dropoffLocation'] ?? 'Destination Point',
            'isRead': false,
          };

          setState(() {
            _notifications.insert(0, notifObj);
            _unreadCount++;
          });

          _showDriverAcceptedDialog(notifObj);
        }
      }
    } catch (_) {}
  }

  void _handleRideUpdatedSocket(dynamic data) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> rawPayload = Map<String, dynamic>.from(data is Map ? data : {});
      final Map<String, dynamic> rideObj = rawPayload['ride'] is Map
          ? Map<String, dynamic>.from(rawPayload['ride'])
          : rawPayload;

      final String payloadId = (rideObj['id'] ?? rideObj['_id'] ?? rideObj['requestId'] ?? rideObj['mongoId'] ?? '').toString();
      final String customerId = (rideObj['customerId'] ?? '').toString();
      final String passengerPhone = (rideObj['passengerPhone'] ?? rideObj['phone'] ?? '').toString();
      final String passengerEmail = (rideObj['passengerEmail'] ?? rideObj['email'] ?? '').toString();

      final currentUserId = _currentUser?.id ?? '';
      final currentUserPhone = _currentUser?.phoneNumber ?? '';
      final currentUserEmail = _currentUser?.email ?? '';

      bool matchesUser = false;
      if (currentUserId.isNotEmpty && customerId == currentUserId) matchesUser = true;
      if (currentUserPhone.isNotEmpty && passengerPhone == currentUserPhone) matchesUser = true;
      if (currentUserEmail.isNotEmpty && passengerEmail == currentUserEmail) matchesUser = true;

      if (!matchesUser && payloadId.isNotEmpty) {
        matchesUser = _notifications.any((n) =>
          (n['id'] == payloadId || n['requestId'] == payloadId || n['rideId'] == payloadId || n['mongoId'] == payloadId)
        );
      }

      if (matchesUser || (customerId.isEmpty && passengerPhone.isEmpty && currentUserPhone.isEmpty)) {
        final rawFare = rideObj['fareFormatted'] ?? (rideObj['fare'] != null ? 'Rs. ${formatNumberCustom(rideObj['fare'])}' : null);

        if (rawFare != null) {
          final String fareText = rawFare.toString();
          final String statusKey = '${payloadId}_FARE_UPDATED_$fareText';

          if (!_seenRideStatusIds.contains(statusKey)) {
            _seenRideStatusIds.add(statusKey);

            final notifObj = {
              'id': payloadId,
              'title': '💰 Ride Price Updated!',
              'subtitle': 'Admin has set your ride price to $fareText.',
              'time': 'Just Now',
              'status': 'PRICE_UPDATED',
              'requestId': payloadId,
              'rideId': payloadId,
              'fareFormatted': fareText,
              'pickup': rideObj['pickupLocation'] ?? 'Pickup Point',
              'destination': rideObj['dropoffLocation'] ?? 'Destination Point',
              'isRead': false,
            };

            setState(() {
              _notifications.insert(0, notifObj);
              _unreadCount++;
            });

            _showFareUpdatedBanner(notifObj);
          }
        }
      }
    } catch (_) {}
  }

  // Poll for ride updates & driver accepted notifications
  void _startNotificationPolling() {
    _fetchCustomerNotifications();
    _notificationPollTimer?.cancel();
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchCustomerNotifications();
      }
    });
  }

  Future<void> _fetchCustomerNotifications() async {
    try {
      final baseUrl = ApiConstants.baseUrl;
      final phone = _currentUser?.phoneNumber ?? '';
      final email = _currentUser?.email ?? '';
      final customerId = _currentUser?.id ?? '';

      // 1. Fetch persistent notifications from MongoDB
      Uri notifUrl = Uri.parse('$baseUrl/api/rides/customer-notifications?phone=$phone&email=$email&customerId=$customerId');
      final notifResponse = await http.get(notifUrl).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('{}', 500));

      List<Map<String, dynamic>> fetchedNotifs = [];

      if (notifResponse.statusCode == 200) {
        final notifData = json.decode(notifResponse.body);
        final List rawNotifs = notifData['notifications'] ?? notifData['data'] ?? [];
        for (var n in rawNotifs) {
          if (n is Map) {
            fetchedNotifs.add(Map<String, dynamic>.from(n));
          }
        }
      }

      // 2. Fetch active rides for customer
      Uri rideUrl = Uri.parse('$baseUrl/api/rides/customer?phone=$phone&email=$email&customerId=$customerId');
      final rideResponse = await http.get(rideUrl).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('{}', 500));

      if (rideResponse.statusCode == 200) {
        final data = json.decode(rideResponse.body);
        final List rides = data['rides'] ?? data['data'] ?? [];

        for (var ride in rides) {
          final String rideId = ride['requestId'] ?? ride['id'] ?? ride['_id'] ?? '';
          final String status = ride['status'] ?? 'Pending Dispatch';
          final String fareText = ride['fareFormatted'] ?? (ride['fare'] != null ? 'Rs. ${formatNumberCustom(ride['fare'])}' : 'Rs. 9,500');

          if (status == 'Driver Unavailable' || status == 'DRIVER_UNAVAILABLE' || ride['driverIssue'] != null) {
            final driverIssue = ride['driverIssue'] ?? {};
            fetchedNotifs.add({
              'id': rideId,
              'title': 'Driver Unavailable',
              'subtitle': 'Your assigned driver is unavailable for this ride.',
              'time': 'Just Now',
              'status': 'Driver Unavailable',
              'requestId': rideId,
              'rideId': rideId,
              'mongoId': ride['_id'] ?? rideId,
              'affectedDate': driverIssue['affectedDate'] ?? ride['startingFrom'] ?? 'May 21, 2026',
              'affectedTime': driverIssue['affectedTime'] ?? '${ride['timeToReach'] ?? "08:00 AM"} - ${ride['timeToLeave'] ?? "10:00 AM"}',
              'reportedReason': driverIssue['reportedReason'] ?? 'Vehicle Issue',
              'additionalDetails': driverIssue['additionalDetails'] ?? 'Driver is unavailable due to a sudden mechanical issue with the vehicle.',
              'isDriverUnavailable': true,
              'pickup': ride['pickupLocation'] ?? 'Pickup Point',
              'destination': ride['dropoffLocation'] ?? 'Destination Point',
            });
          } else if (status == 'ACCEPTED') {
            final driverDetails = ride['assignedDriverDetails'] ?? ride['driverDetails'] ?? {};
            final driverName = ride['assignedDriverName'] ?? driverDetails['name'] ?? 'Driver';
            fetchedNotifs.add({
              'id': rideId,
              'title': '🔔 Ride Accepted by Driver!',
              'subtitle': 'Driver $driverName accepted ride $rideId.',
              'time': 'Just Now',
              'status': status,
              'requestId': rideId,
              'customerName': ride['passengerName'] ?? _currentUser?.fullName ?? 'Customer',
              'fareFormatted': fareText,
              'driverName': driverName,
              'driverPhone': driverDetails['phone'] ?? '',
              'driverCode': driverDetails['driverCode'] ?? 'DRV-Verified',
              'rating': driverDetails['rating']?.toString() ?? '⭐ 4.9 (Verified Driver)',
              'vehicle': driverDetails['vehicle'] ?? '🚗 Vehicle',
              'numberPlate': driverDetails['registrationNumber'] ?? driverDetails['numberPlate'] ?? '🔢 Registered',
              'pickup': ride['pickupLocation'] ?? 'Pickup Point',
              'destination': ride['dropoffLocation'] ?? 'Destination Point',
            });
          } else {
            fetchedNotifs.add({
              'id': rideId,
              'title': '💰 Ride Price Updated!',
              'subtitle': 'Admin has set your ride price to $fareText.',
              'time': 'Just Now',
              'status': 'PRICE_UPDATED',
              'fareResponseStatus': status == 'Fare Accepted' ? 'Fare Accepted' : status == 'Fare Rejected' ? 'Fare Rejected' : 'Pending',
              'requestId': rideId,
              'rideId': rideId,
              'fareFormatted': fareText,
              'pickup': ride['pickupLocation'] ?? 'Pickup Point',
              'destination': ride['dropoffLocation'] ?? 'Destination Point',
            });
          }
        }
      }

      if (fetchedNotifs.isNotEmpty && mounted) {
        final bool isInitialLoad = _isFirstFetch;
        if (_isFirstFetch) {
          _isFirstFetch = false;
        }

        List<Map<String, dynamic>> uniqueNotifs = [];
        Set<String> seenInThisBatch = {};
        int newlyArrivedCount = 0;

        for (var notif in fetchedNotifs) {
          final String rId = (notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '').toString();
          final String status = (notif['status'] ?? '').toString();
          final String fareText = (notif['fareFormatted'] ?? '').toString();
          final String statusKey = '${rId}_${status}_$fareText';

          if (!seenInThisBatch.contains(statusKey)) {
            seenInThisBatch.add(statusKey);
            notif['id'] = rId;

            if (!_seenRideStatusIds.contains(statusKey)) {
              _seenRideStatusIds.add(statusKey);
              if (!isInitialLoad) {
                newlyArrivedCount++;
              }
            }
            uniqueNotifs.add(notif);
          }
        }

        setState(() {
          _notifications = uniqueNotifs;
          if (!isInitialLoad && newlyArrivedCount > 0) {
            _unreadCount += newlyArrivedCount;
          } else if (isInitialLoad) {
            _unreadCount = uniqueNotifs.length;
          }
        });
      }
    } catch (_) {}
  }

  static String formatNumberCustom(dynamic val) {
    if (val == null) return '0';
    final n = num.tryParse(val.toString());
    if (n == null) return val.toString();
    return n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  // Driver Unavailable Top Banner pop-up
  void _showDriverUnavailableBanner(Map<String, dynamic> notif) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 40, left: 16, right: 16),
        backgroundColor: const Color(0xFFDC2626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.priority_high_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif['title'] ?? 'Driver Unavailable',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif['subtitle'] ?? 'Your assigned driver is unavailable for this ride.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DriverUnavailableScreen(data: notif),
              ),
            );
          },
        ),
      ),
    );
  }

  // Fare Updated Top Banner pop-up
  void _showFareUpdatedBanner(Map<String, dynamic> notif) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 40, left: 16, right: 16),
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 7),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.attach_money_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif['title'] ?? 'Ride Price Updated!',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif['subtitle'] ?? 'Admin has updated your ride price.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: const Color(0xFFF59E0B),
          onPressed: _showNotificationListModal,
        ),
      ),
    );
  }


  // Open Full Driver Details Dialog
  void _showDriverAcceptedDialog(Map<String, dynamic> notif) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Badge
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
                ),
                const SizedBox(height: 12),

                const Text(
                  'RIDE ACCEPTED BY DRIVER!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: 0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Request ID: ${notif['requestId']}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primaryBlue),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Driver Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: _primaryBlue.withValues(alpha: 0.1),
                            child: const Icon(Icons.person_rounded, color: _primaryBlue, size: 32),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notif['driverName'] ?? 'Assigned Driver',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  notif['driverPhone'] != null && notif['driverPhone'].toString().isNotEmpty ? notif['driverPhone'].toString() : 'Verified Driver',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    notif['rating'] ?? '⭐ 4.9 (Verified Driver)',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),

                      _DetailRow(icon: Icons.badge_outlined, label: 'Driver Code', value: notif['driverCode'] ?? 'DRV-1788328584103-ECAP0L'),
                      const SizedBox(height: 8),
                      _DetailRow(icon: Icons.directions_car_outlined, label: 'Vehicle', value: notif['vehicle'] ?? 'Honda Accord (Super White)'),
                      const SizedBox(height: 8),
                      _DetailRow(icon: Icons.numbers_rounded, label: 'Number Plate', value: notif['numberPlate'] ?? 'ISB-0009'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Trip Fare & Route Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Agreed Fare', style: TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
                          Text(
                            notif['fareFormatted'] ?? 'Rs. 9,500',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.trip_origin_rounded, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              notif['pickup'] ?? '',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              notif['destination'] ?? '',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: const Text('OKAY, GOT IT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Open Fare Approval / Decision Dialog (Accept or Reject price)
  void _showFareApprovalDialog(Map<String, dynamic> notif) {
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final String rideId = notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '';
          final String fareText = notif['fareFormatted'] ?? 'Rs. 3,000';
          final String pickup = notif['pickup'] ?? 'Pickup Point';
          final String destination = notif['destination'] ?? 'Destination Point';
          final String currentStatus = notif['fareResponseStatus'] ?? notif['status'] ?? 'PRICE_UPDATED';

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Icon Badge
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFD97706), size: 44),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'RIDE FARE UPDATED',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: 0.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Request ID: $rideId',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primaryBlue),
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Highlighted New Fare Container
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Updated Ride Price',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Set by Admin',
                                style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                              ),
                            ],
                          ),
                          Text(
                            fareText,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Route Summary
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.trip_origin_rounded, color: Colors.green, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pickup,
                                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  destination,
                                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (currentStatus == 'Fare Accepted' || currentStatus == 'Fare Rejected') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: currentStatus == 'Fare Accepted' ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          currentStatus == 'Fare Accepted'
                              ? '✅ You have ACCEPTED this fare offer.'
                              : '❌ You have REJECTED this fare offer.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: currentStatus == 'Fare Accepted' ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ] else ...[
                      if (isSubmitting)
                        const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(),
                        )
                      else ...[
                        // ACCEPT FARE BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                            label: const Text(
                              'ACCEPT FARE',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white, letterSpacing: 0.5),
                            ),
                            onPressed: () async {
                              setDialogState(() {
                                isSubmitting = true;
                              });
                              await _sendFareResponse(notif, 'ACCEPT');
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 10),

                        // REJECT FARE BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444)),
                            label: const Text(
                              'REJECT FARE',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFEF4444), letterSpacing: 0.5),
                            ),
                            onPressed: () async {
                              setDialogState(() {
                                isSubmitting = true;
                              });
                              await _sendFareResponse(notif, 'REJECT');
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendFareResponse(Map<String, dynamic> notif, String action) async {
    try {
      final baseUrl = ApiConstants.baseUrl;
      final rideId = notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '';
      final customerName = _currentUser?.fullName ?? _currentUser?.phoneNumber ?? 'Customer';

      await http.post(
        Uri.parse('$baseUrl/api/rides/respond-fare'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'rideId': rideId,
          'action': action,
          'customerName': customerName,
        }),
      );

      final isAccept = action == 'ACCEPT';
      final statusText = isAccept ? 'Fare Accepted' : 'Fare Rejected';

      setState(() {
        notif['fareResponseStatus'] = statusText;
        notif['subtitle'] = isAccept
            ? 'You accepted the fare of ${notif['fareFormatted'] ?? ''}. Admin notified!'
            : 'You rejected the fare of ${notif['fareFormatted'] ?? ''}. Admin notified!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isAccept ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            content: Text(
              isAccept
                  ? '✅ Fare Accepted! Admin will assign driver shortly.'
                  : '❌ Fare Rejected. Admin has been notified.',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to submit response: $err'),
          ),
        );
      }
    }
  }

  // Show Notification List Drawer Modal
  void _showNotificationListModal() {
    setState(() {
      _unreadCount = 0;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          children: [
            // Handle indicator
            const SizedBox(height: 12),
            Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),

            // Modal Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_rounded, color: _primaryBlue, size: 24),
                      SizedBox(width: 8),
                      Text('Ride Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),

            Expanded(
              child: _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('No new notifications yet.', style: TextStyle(fontSize: 15, color: Colors.black54, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          const Text('When a driver accepts your ride, it will appear here.', style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final notif = _notifications[index];
                        final isDriverUnavail = (notif['isDriverUnavailable'] == true || notif['status'] == 'Driver Unavailable');
                        final isPriceUpdate = (notif['status'] == 'PRICE_UPDATED');

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDriverUnavail
                                    ? const Color(0xFFFEE2E2)
                                    : isPriceUpdate
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFFDCFCE7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isDriverUnavail
                                    ? Icons.priority_high_rounded
                                    : isPriceUpdate
                                        ? Icons.attach_money_rounded
                                        : Icons.directions_car_filled_rounded,
                                color: isDriverUnavail
                                    ? const Color(0xFFDC2626)
                                    : isPriceUpdate
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF16A34A),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              notif['title'] ?? 'Ride Update',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDriverUnavail
                                    ? const Color(0xFFDC2626)
                                    : isPriceUpdate
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(notif['subtitle'] ?? '', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                                const SizedBox(height: 6),
                                Text(
                                  isDriverUnavail
                                      ? 'Tap to request replacement driver'
                                      : isPriceUpdate
                                          ? 'Updated Fare: ${notif['fareFormatted'] ?? ''}'
                                          : 'Tap to view driver details',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDriverUnavail
                                        ? const Color(0xFFDC2626)
                                        : isPriceUpdate
                                            ? const Color(0xFFD97706)
                                            : _primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                            onTap: () {
                              Navigator.pop(context);
                              if (isDriverUnavail) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DriverUnavailableScreen(data: notif),
                                  ),
                                );
                              } else if (isPriceUpdate) {
                                _showFareApprovalDialog(notif);
                              } else {
                                _showDriverAcceptedDialog(notif);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Open Profile View Screen
  void _showProfileDialog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileViewScreen(user: _currentUser),
      ),
    );
    _loadUserData();
  }

  // Payment Details Dialog
  void _showPaymentDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Color(0xFFEBF3FF), shape: BoxShape.circle),
                child: const Icon(Icons.account_balance_wallet_rounded, color: _primaryBlue, size: 36),
              ),
              const SizedBox(height: 14),
              const Text('PAYMENT DETAILS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 6),
              const Text('Cash on pickup & online wallet payments supported.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),
              _DetailRow(icon: Icons.payments_rounded, label: 'Default Method', value: 'Cash / Bank Transfer'),
              const SizedBox(height: 8),
              _DetailRow(icon: Icons.check_circle_outline, label: 'Billing Status', value: 'Up to Date'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OKAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }





  void _onItemTap(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title service selected.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawName = _currentUser?.fullName.trim();
    final displayName = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : 'Arbab';

    return Scaffold(
      backgroundColor: _screenBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryBlue))
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Top Curved Deep Blue Header Header Matching Screenshot Exactly
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 52, 20, 32),
                    decoration: const BoxDecoration(
                      color: _primaryBlue,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Large White Circle Avatar
                        GestureDetector(
                          onTap: _showProfileDialog,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: (_currentUser?.photoUrl != null && _currentUser!.photoUrl!.isNotEmpty)
                                  ? Image.network(
                                      _currentUser!.photoUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const Icon(Icons.person, color: _primaryBlue, size: 36),
                                    )
                                  : const Icon(Icons.person, color: _primaryBlue, size: 36),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Welcome Arbab! & Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, $displayName!',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Manage your rides & bookings',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Notification Bell Icon with Badge
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                              tooltip: 'Notifications',
                              onPressed: _showNotificationListModal,
                            ),
                            if (_unreadCount > 0)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  child: Text(
                                    '$_unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Menu Items List matching exact UI in screenshot
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                    child: Column(
                      children: [
                        // Card 1: Monthly Pickup
                        _DashboardCard(
                          icon: Icons.event_note_rounded,
                          title: 'Monthly Pickup',
                          subtitle: 'Regular planned pickups for a month.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MonthlyPickupScreen(user: _currentUser),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 2: Schedule Ride
                        _DashboardCard(
                          icon: Icons.access_time_filled_rounded,
                          title: 'Schedule Ride',
                          subtitle: 'Book a ride in advance for any time.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SchedulePickupScreen(user: _currentUser),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 3: Hire Driver
                        _DashboardCard(
                          icon: Icons.person_rounded,
                          title: 'Hire Driver',
                          subtitle: 'Get a professional personal driver.',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HireDriverScreen(user: _currentUser),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 5: Payment Details
                        _DashboardCard(
                          icon: Icons.credit_card_rounded,
                          title: 'Payment Details',
                          subtitle: 'View your payments and transaction history.',
                          onTap: _showPaymentDetailsDialog,
                        ),
                        const SizedBox(height: 12),

                        // Card 6: Profile View
                        _DashboardCard(
                          icon: Icons.person_outline_rounded,
                          title: 'Profile View',
                          subtitle: 'View and manage your profile details.',
                          onTap: _showProfileDialog,
                        ),
                        const SizedBox(height: 16),

                        // Bottom Need Assistance Card matching screenshot
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEBF3FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Need Assistance?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F2B5B),
                                ),
                              ),
                              InkWell(
                                onTap: () => _onItemTap('Contact Support'),
                                borderRadius: BorderRadius.circular(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        color: _primaryBlue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.phone_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Contact',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _primaryBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEBF0FF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0066FF).withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon Circle
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFEBF3FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF0066FF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron Right Icon in Primary Blue
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF0066FF),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
