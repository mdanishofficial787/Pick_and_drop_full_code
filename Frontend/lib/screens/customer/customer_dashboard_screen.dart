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
import 'package:ride_and_serve/screens/customer/payment_details_screen.dart';
import 'package:ride_and_serve/screens/customer/customer_payment_history_screen.dart';
import 'package:ride_and_serve/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final Set<String> _dismissedNotifIds = {};
  final Set<String> _paidRideIds = {};
  bool _isFirstFetch = true;

  static const Color _primaryBlue = AppColors.primaryBlue; // Color(0xFF0066FF) / AppColors.primaryBlue
  static const Color _screenBg = Color(0xFFF4F7FC);

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    await _loadDismissedNotifications();
    await _loadUserData();
    _syncPaidRides();
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  // FIXED: always prefer the latest saved user (name + photo) from storage.
  // widget.user is only a fallback, because it never changes after login.
  Future<void> _loadUserData() async {
    final saved = await AuthService.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _currentUser = saved ?? widget.user;
      _isLoading = false;
    });
    _initSocketConnection();
    _startNotificationPolling();
  }

  // FIXED: lightweight reload used after returning from Profile View.
  // Only refreshes the user; it does NOT reopen the socket or restart polling.
  Future<void> _refreshUser() async {
    final fresh = await AuthService.getCurrentUser();
    if (!mounted) return;
    setState(() => _currentUser = fresh ?? _currentUser);
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

      _socket?.on('payment-status-updated', (data) {
        if (!mounted) return;
        final Map<String, dynamic> payload = Map<String, dynamic>.from(data is Map ? data : {});
        final String rideId = (payload['rideId'] ?? '').toString();
        if (rideId.isNotEmpty) {
          setState(() {
            _dismissedNotifIds.addAll([rideId, '${rideId}_COMPLETED', '${rideId}_completed']);
            _notifications.removeWhere((n) {
              final nId = (n['rideId'] ?? n['requestId'] ?? n['id'] ?? '').toString();
              return nId == rideId || n['id'] == '${rideId}_completed' || n['notificationId'] == '${rideId}_completed';
            });
            _unreadCount = _notifications.length;
          });
        }
        final String title = payload['title'] ?? 'Payment Updated';
        final String message = payload['message'] ?? 'Your payment status has been updated.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$title\n$message'),
          backgroundColor: const Color(0xFF1959F6),
          duration: const Duration(seconds: 5),
        ));
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
        final String status = (rideObj['status'] ?? '').toString();

        if (status == 'PAID' || status == 'Paid') {
          setState(() {
            _dismissedNotifIds.addAll([payloadId, '${payloadId}_COMPLETED', '${payloadId}_completed']);
            _notifications.removeWhere((n) {
              final nId = (n['requestId'] ?? n['id'] ?? n['rideId'] ?? '').toString();
              return nId == payloadId;
            });
            _unreadCount = _notifications.length;
          });
        } else if (status == 'COMPLETED' || status == 'Completed') {
          final String statusKey = '${payloadId}_COMPLETED';
          if (!_seenRideStatusIds.contains(statusKey)) {
            _seenRideStatusIds.add(statusKey);
            final notifObj = {
              'id': payloadId,
              'title': '✅ Ride Completed!',
              'subtitle': 'Please submit your payment for this ride.',
              'time': 'Just Now',
              'status': 'COMPLETED',
              'requestId': payloadId,
              'rideId': payloadId,
              'fareFormatted': rawFare?.toString() ?? 'Rs. 4500',
              'pickup': rideObj['pickupLocation'] ?? 'Pickup Point',
              'destination': rideObj['dropoffLocation'] ?? 'Destination Point',
              'isRead': false,
            };
            setState(() {
              // Retire all prior notifications for this ride (driver accepted, price updated, etc.)
              _notifications.removeWhere((n) {
                final nId = (n['requestId'] ?? n['id'] ?? n['rideId'] ?? '').toString();
                final nStatus = (n['status'] ?? '').toString();
                return (nId == payloadId) && nStatus != 'COMPLETED' && nStatus != 'Completed';
              });
              _notifications.insert(0, notifObj);
              _unreadCount = _notifications.length;
            });
            _showRideCompletedBanner(notifObj);
          }
        } else if ((status == 'PRICE_UPDATED' || status == 'Price Updated') && rawFare != null) {
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

      if (mounted) {
        final bool isInitialLoad = _isFirstFetch;
        if (_isFirstFetch) {
          _isFirstFetch = false;
        }

        final lowerDismissed = _dismissedNotifIds.map((e) => e.toLowerCase().trim()).toSet();
        final lowerPaid = _paidRideIds.map((e) => e.toLowerCase().trim()).toSet();

        List<Map<String, dynamic>> filtered = [];
        Set<String> seenInThisBatch = {};
        int newlyArrivedCount = 0;

        for (var notif in fetchedNotifs) {
          final String rId = (notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '').toString();
          final String cleanRid = rId.toLowerCase().trim();
          final String status = (notif['status'] ?? '').toString();
          final String fareText = (notif['fareFormatted'] ?? '').toString();
          final String notifUniqueKey = (notif['notificationId'] ?? notif['id'] ?? '${rId}_${status}_$fareText').toString();
          final String cleanKey = notifUniqueKey.toLowerCase().trim();
          final String notifId = (notif['id'] ?? '').toString().toLowerCase().trim();
          final String mongoId = (notif['mongoId'] ?? '').toString().toLowerCase().trim();

          if (seenInThisBatch.contains(notifUniqueKey)) continue;
          seenInThisBatch.add(notifUniqueKey);
          notif['notifKey'] = notifUniqueKey;

          final bool isCustomerAccepted = notif['customerAccepted'] == true || status == 'CUSTOMER_ACCEPTED' || status == 'Customer Accepted';
          final bool isPaid = notif['isPaid'] == true ||
              notif['paymentStatus'] == 'Paid' ||
              status == 'PAID' ||
              status == 'Paid' ||
              lowerPaid.contains(cleanRid);

          // 1. If customer already accepted, do not show accept driver prompt
          if (isCustomerAccepted && (status == 'ACCEPTED' || status == 'Accepted' || status == 'CUSTOMER_ACCEPTED' || status == 'Customer Accepted')) {
            continue;
          }

          // 2. If ride is paid / pending verification, do not show payment prompt
          if (isPaid && (status == 'COMPLETED' || status == 'Completed' || status == 'PAID' || status == 'Paid')) {
            continue;
          }

          // 3. Check dismissed set (case-insensitive across all keys and variants)
          if (lowerDismissed.contains(cleanKey) ||
              lowerDismissed.contains(notifId) ||
              lowerDismissed.contains(mongoId) ||
              lowerDismissed.contains(cleanRid) ||
              lowerDismissed.contains('${cleanRid}_${status.toLowerCase().trim()}') ||
              lowerDismissed.contains('${cleanRid}_completed') ||
              lowerDismissed.contains('${cleanRid}_accepted') ||
              lowerDismissed.contains('${cleanRid}_driver_accepted') ||
              lowerDismissed.contains('${cleanRid}_price_updated')) {
            continue;
          }

          // Notification survived all filters! Check if newly arrived to trigger popup/dialog
          if (!_seenRideStatusIds.contains(notifUniqueKey)) {
            _seenRideStatusIds.add(notifUniqueKey);
            if (!isInitialLoad) {
              newlyArrivedCount++;
              if (status == 'ACCEPTED' || status == 'Accepted') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showDriverAcceptedDialog(notif);
                });
              }
            }
          }

          filtered.add(notif);
        }

        setState(() {
          _notifications = filtered;
          if (!isInitialLoad && newlyArrivedCount > 0) {
            _unreadCount += newlyArrivedCount;
          } else if (isInitialLoad) {
            _unreadCount = filtered.length;
          }
        });
      }
    } catch (_) {}
  }

  // Load previously dismissed notification IDs and paid rides from SharedPreferences
  Future<void> _loadDismissedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('dismissed_customer_notifs') ?? [];
      final savedPaid = prefs.getStringList('paid_customer_ride_ids') ?? [];
      if (mounted) {
        setState(() {
          _dismissedNotifIds.addAll(saved);
          _paidRideIds.addAll(savedPaid);
          _filterOutDismissedNotifications();
        });
      }
    } catch (_) {}
  }

  // Synchronously filter in-memory notifications using latest dismissed/paid sets
  void _filterOutDismissedNotifications() {
    final lowerDismissed = _dismissedNotifIds.map((e) => e.toLowerCase().trim()).toSet();
    final lowerPaid = _paidRideIds.map((e) => e.toLowerCase().trim()).toSet();

    _notifications.removeWhere((n) {
      final key = (n['notifKey'] ?? '').toString().toLowerCase().trim();
      final id = (n['id'] ?? '').toString().toLowerCase().trim();
      final mongoId = (n['mongoId'] ?? '').toString().toLowerCase().trim();
      final rId = (n['rideId'] ?? n['requestId'] ?? '').toString().toLowerCase().trim();
      final st = (n['status'] ?? '').toString();

      final isCustomerAccepted = n['customerAccepted'] == true || st == 'CUSTOMER_ACCEPTED' || st == 'Customer Accepted';
      final isPaid = n['isPaid'] == true || n['paymentStatus'] == 'Paid' || st == 'PAID' || st == 'Paid' || lowerPaid.contains(rId);

      if (isCustomerAccepted && (st == 'ACCEPTED' || st == 'Accepted' || st == 'CUSTOMER_ACCEPTED' || st == 'Customer Accepted')) {
        return true;
      }
      if (isPaid && (st == 'COMPLETED' || st == 'Completed' || st == 'PAID' || st == 'Paid')) {
        return true;
      }
      if (lowerDismissed.contains(key) ||
          lowerDismissed.contains(id) ||
          lowerDismissed.contains(mongoId) ||
          lowerDismissed.contains(rId) ||
          lowerDismissed.contains('${rId}_${st.toLowerCase().trim()}') ||
          lowerDismissed.contains('${rId}_completed') ||
          lowerDismissed.contains('${rId}_accepted') ||
          lowerDismissed.contains('${rId}_driver_accepted') ||
          lowerDismissed.contains('${rId}_price_updated')) {
        return true;
      }
      return false;
    });
    _unreadCount = _notifications.length;
  }

  // Fetch payment history to automatically identify rides that have already been paid/submitted
  Future<void> _syncPaidRides() async {
    try {
      final phone = _currentUser?.phoneNumber ?? '';
      final customerId = _currentUser?.id ?? '';
      if (phone.isEmpty && customerId.isEmpty) return;

      final url = Uri.parse('${ApiConstants.customerPaymentHistory}?customerId=$customerId&phone=$phone');
      final res = await http.get(url).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('{}', 500));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List list = data['data'] ?? [];
        final Set<String> newPaid = {};
        for (var p in list) {
          if (p is Map) {
            final rId = (p['rideId'] ?? '').toString().toLowerCase().trim();
            if (rId.isNotEmpty) {
              newPaid.add(rId);
            }
          }
        }
        if (newPaid.isNotEmpty && mounted) {
          setState(() {
            _paidRideIds.addAll(newPaid);
            for (var rId in newPaid) {
              _dismissedNotifIds.add(rId);
              _dismissedNotifIds.add('${rId}_completed');
              _dismissedNotifIds.add('${rId}_COMPLETED');
            }
            _filterOutDismissedNotifications();
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('paid_customer_ride_ids', _paidRideIds.toList());
          await prefs.setStringList('dismissed_customer_notifs', _dismissedNotifIds.toList());
        }
      }
    } catch (_) {}
  }

  // Slide to finish / dismiss a single notification
  Future<void> _dismissNotification(Map<String, dynamic> notif, int index) async {
    final notifKey = (notif['notifKey'] ?? notif['id'] ?? 'notif_$index').toString();
    final notifId = (notif['id'] ?? notif['mongoId'] ?? '').toString();
    final mongoId = (notif['mongoId'] ?? '').toString();
    final rideId = (notif['rideId'] ?? notif['requestId'] ?? '').toString();
    final status = (notif['status'] ?? '').toString();

    setState(() {
      _dismissedNotifIds.addAll([
        notifKey,
        if (notifId.isNotEmpty) notifId,
        if (mongoId.isNotEmpty) mongoId,
        if (rideId.isNotEmpty) rideId,
        if (rideId.isNotEmpty) rideId.toLowerCase(),
        if (rideId.isNotEmpty && status.isNotEmpty) '${rideId}_$status',
        if (rideId.isNotEmpty && status.isNotEmpty) '${rideId}_${status.toLowerCase()}',
        if (rideId.isNotEmpty) '${rideId}_accepted',
        if (rideId.isNotEmpty) '${rideId}_ACCEPTED',
        if (rideId.isNotEmpty) '${rideId}_completed',
        if (rideId.isNotEmpty) '${rideId}_COMPLETED',
        if (rideId.isNotEmpty) '${rideId}_price_updated',
        if (rideId.isNotEmpty) '${rideId}_PRICE_UPDATED',
        if (rideId.isNotEmpty) '${rideId}_DRIVER_ACCEPTED',
      ]);
      _notifications.removeAt(index);
      _unreadCount = _notifications.length;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_customer_notifs', _dismissedNotifIds.toList());
    } catch (_) {}

    try {
      final targetId = mongoId.isNotEmpty ? mongoId : (notifId.isNotEmpty ? notifId : rideId);
      if (targetId.isNotEmpty) {
        http.post(
          Uri.parse(ApiConstants.dismissCustomerNotification(targetId)),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'customerId': _currentUser?.id,
            'phone': _currentUser?.phoneNumber,
            'rideId': rideId,
          }),
        ).catchError((_) => http.Response('{}', 500));
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification dismissed'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Clear all notifications
  Future<void> _clearAllNotifications() async {
    for (var n in _notifications) {
      final key = (n['notifKey'] ?? n['id'] ?? '').toString();
      final id = (n['id'] ?? '').toString();
      final mongoId = (n['mongoId'] ?? '').toString();
      final rId = (n['rideId'] ?? n['requestId'] ?? '').toString();
      final st = (n['status'] ?? '').toString();

      if (key.isNotEmpty) _dismissedNotifIds.add(key);
      if (id.isNotEmpty) _dismissedNotifIds.add(id);
      if (mongoId.isNotEmpty) _dismissedNotifIds.add(mongoId);
      if (rId.isNotEmpty) {
        _dismissedNotifIds.add(rId);
        _dismissedNotifIds.add(rId.toLowerCase());
        _dismissedNotifIds.add('${rId}_accepted');
        _dismissedNotifIds.add('${rId}_ACCEPTED');
        _dismissedNotifIds.add('${rId}_completed');
        _dismissedNotifIds.add('${rId}_COMPLETED');
        _dismissedNotifIds.add('${rId}_price_updated');
        _dismissedNotifIds.add('${rId}_PRICE_UPDATED');
        _dismissedNotifIds.add('${rId}_DRIVER_ACCEPTED');
      }
      if (rId.isNotEmpty && st.isNotEmpty) {
        _dismissedNotifIds.add('${rId}_$st');
        _dismissedNotifIds.add('${rId}_${st.toLowerCase()}');
      }

      // Also call individual dismiss on backend
      final targetId = mongoId.isNotEmpty ? mongoId : (id.isNotEmpty ? id : rId);
      if (targetId.isNotEmpty) {
        http.post(
          Uri.parse(ApiConstants.dismissCustomerNotification(targetId)),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'customerId': _currentUser?.id,
            'phone': _currentUser?.phoneNumber,
            'rideId': rId,
          }),
        ).catchError((_) => http.Response('{}', 500));
      }
    }

    setState(() {
      _notifications.clear();
      _unreadCount = 0;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_customer_notifs', _dismissedNotifIds.toList());
    } catch (_) {}

    try {
      http.post(
        Uri.parse(ApiConstants.clearAllCustomerNotifications),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customerId': _currentUser?.id,
          'phone': _currentUser?.phoneNumber,
          'email': _currentUser?.email,
        }),
      ).catchError((_) => http.Response('{}', 500));
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications cleared'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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


  // Ride Completed Top Banner pop-up
  void _showRideCompletedBanner(Map<String, dynamic> notif) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 40, left: 16, right: 16),
        backgroundColor: const Color(0xFF1959F6),
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
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF1959F6), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif['title'] ?? 'Ride Completed!',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif['subtitle'] ?? 'Please submit your payment.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'PAY',
          textColor: Colors.white,
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentDetailsScreen(rideData: notif),
              ),
            );
            await _loadDismissedNotifications();
            await _syncPaidRides();
            _fetchCustomerNotifications();
          },
        ),
      ),
    );
  }

  // Send Customer Accept Ride Response to Backend & notify Driver
  Future<bool> _acceptRideAsCustomer(Map<String, dynamic> notif) async {
    try {
      final baseUrl = ApiConstants.baseUrl;
      final rideId = notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '';
      final customerName = _currentUser?.fullName ?? _currentUser?.phoneNumber ?? 'Customer';
      final customerPhone = _currentUser?.phoneNumber ?? '';

      final String rId = (notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '').toString();
      final String notifKey = (notif['notifKey'] ?? notif['notificationId'] ?? notif['id'] ?? '${rId}_ACCEPTED').toString();

      // 1. Immediately update UI state and dismiss locally so it never persists/reappears
      if (mounted) {
        setState(() {
          notif['customerAccepted'] = true;
          notif['status'] = 'CUSTOMER_ACCEPTED';
          notif['subtitle'] = 'You accepted this ride. Driver ${notif['driverName'] ?? ''} has been notified!';
          _dismissedNotifIds.addAll([
            notifKey,
            rId,
            rId.toLowerCase(),
            '${rId}_ACCEPTED',
            '${rId}_accepted',
            '${rId}_CUSTOMER_ACCEPTED',
            '${rId}_DRIVER_ACCEPTED',
            (notif['id'] ?? '').toString(),
            (notif['notificationId'] ?? '').toString(),
            (notif['mongoId'] ?? '').toString(),
          ]);
          _notifications.removeWhere((n) {
            final nId = (n['requestId'] ?? n['id'] ?? n['rideId'] ?? '').toString();
            final nKey = (n['notifKey'] ?? n['notificationId'] ?? n['id'] ?? '').toString();
            return nId == rId || nKey == notifKey || nKey == '${rId}_ACCEPTED' || nKey == '${rId}_accepted';
          });
          _unreadCount = _notifications.length;
        });
      }

      // 2. Persist to SharedPreferences immediately so restart preserves this dismissal
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('dismissed_customer_notifs', _dismissedNotifIds.toList());
      } catch (_) {}

      // 3. Mark dismissed on backend CustomerNotification (compatible with both live Vercel and local)
      try {
        final targetId = notif['mongoId'] ?? notif['id'] ?? rId;
        http.post(
          Uri.parse(ApiConstants.dismissCustomerNotification(targetId)),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'customerId': _currentUser?.id,
            'phone': _currentUser?.phoneNumber,
            'rideId': rId,
          }),
        ).catchError((_) => http.Response('{}', 500));
      } catch (_) {}

      // 4. Send customer-accept payload to backend
      try {
        await http.post(
          Uri.parse('$baseUrl/api/rides/customer-accept'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'rideId': rideId,
            'customerId': _currentUser?.id,
            'customerName': customerName,
            'customerPhone': customerPhone,
          }),
        ).timeout(const Duration(seconds: 6)).catchError((_) => http.Response('{}', 500));
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎉 Ride accepted! Notification sent to Driver ${notif['driverName'] ?? ''}.',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return true;
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to accept ride: $err'),
          ),
        );
      }
      return false;
    }
  }

  // Open Full Driver Details Dialog with ACCEPT RIDE option
  void _showDriverAcceptedDialog(Map<String, dynamic> notif) {
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isAccepted = notif['customerAccepted'] == true || notif['status'] == 'CUSTOMER_ACCEPTED';

          return Dialog(
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

                    Text(
                      isAccepted ? 'RIDE ACCEPTED & CONFIRMED!' : 'RIDE ACCEPTED BY DRIVER!',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: 0.5),
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
                              if (_currentUser?.photoUrl != null && _currentUser!.photoUrl!.isNotEmpty)
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.transparent,
                                  backgroundImage: NetworkImage(_currentUser!.photoUrl!.startsWith('http') ? _currentUser!.photoUrl! : '${ApiConstants.baseUrl}/${_currentUser!.photoUrl!.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '')}'),
                                )
                              else
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

                    if (isAccepted) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'You have ACCEPTED this ride.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.check_rounded, color: Colors.white),
                          label: const Text('OKAY, GOT IT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
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
                        // ACCEPT RIDE BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            label: const Text(
                              'ACCEPT RIDE',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white, letterSpacing: 0.5),
                            ),
                            onPressed: () async {
                              setDialogState(() {
                                isSubmitting = true;
                              });
                              final ok = await _acceptRideAsCustomer(notif);
                              if (context.mounted) {
                                if (ok) {
                                  Navigator.pop(context);
                                } else {
                                  setDialogState(() {
                                    isSubmitting = false;
                                  });
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('DISMISS / CLOSE', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            onPressed: () => Navigator.pop(context),
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

      final String rId = (notif['requestId'] ?? notif['id'] ?? notif['rideId'] ?? '').toString();
      final String notifKey = (notif['notifKey'] ?? notif['notificationId'] ?? notif['id'] ?? '${rId}_price_updated').toString();

      setState(() {
        notif['fareResponseStatus'] = statusText;
        notif['subtitle'] = isAccept
            ? 'You accepted the fare of ${notif['fareFormatted'] ?? ''}. Admin notified!'
            : 'You rejected the fare of ${notif['fareFormatted'] ?? ''}. Admin notified!';
        _dismissedNotifIds.addAll([
          notifKey,
          '${rId}_price_updated',
          '${rId}_PRICE_UPDATED',
          (notif['id'] ?? '').toString(),
          (notif['notificationId'] ?? '').toString(),
        ]);
        _notifications.removeWhere((n) {
          final nId = (n['requestId'] ?? n['id'] ?? n['rideId'] ?? '').toString();
          final nKey = (n['notifKey'] ?? n['notificationId'] ?? n['id'] ?? '').toString();
          return nKey == notifKey || nKey == '${rId}_price_updated' || (nId == rId && n['status'] == 'PRICE_UPDATED');
        });
        _unreadCount = _notifications.length;
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('dismissed_customer_notifs', _dismissedNotifIds.toList());
      } catch (_) {}

      try {
        final targetId = notif['mongoId'] ?? notif['id'] ?? rId;
        http.post(
          Uri.parse(ApiConstants.dismissCustomerNotification(targetId)),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'customerId': _currentUser?.id,
            'phone': _currentUser?.phoneNumber,
            'rideId': rId,
          }),
        ).catchError((_) => http.Response('{}', 500));
      } catch (_) {}

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
                  Row(
                    children: [
                      if (_notifications.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _clearAllNotifications();
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_notifications.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.swipe_right_rounded, size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      'Slide right to finish notification',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
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
                        final isCompleted = (notif['status'] == 'COMPLETED' || notif['status'] == 'Completed');
                        final String notifKey = (notif['notifKey'] ?? notif['id'] ?? 'notif_${notif['status']}_$index').toString();

                        String displayTitle = (notif['title'] ?? 'Ride Update').toString();
                        if (displayTitle.contains('ðŸ')) {
                          displayTitle = displayTitle
                              .replaceAll('ðŸ’°', '💰')
                              .replaceAll('ðŸš—', '🚗')
                              .replaceAll('ðŸ”¢', '🔢')
                              .replaceAll('â­ ', '⭐');
                        }

                        return Dismissible(
                          key: ValueKey(notifKey),
                          direction: DismissDirection.horizontal,
                          background: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'Dismiss',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          secondaryBackground: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.centerRight,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Dismiss',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
                              ],
                            ),
                          ),
                          onDismissed: (direction) {
                            _dismissNotification(notif, index);
                          },
                          child: Card(
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
                                        : isCompleted
                                            ? const Color(0xFFDBEAFE) // Light blue
                                            : const Color(0xFFDCFCE7),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isDriverUnavail
                                    ? Icons.priority_high_rounded
                                    : isPriceUpdate
                                        ? Icons.attach_money_rounded
                                        : isCompleted
                                            ? Icons.check_circle_rounded
                                            : Icons.directions_car_filled_rounded,
                                color: isDriverUnavail
                                    ? const Color(0xFFDC2626)
                                    : isPriceUpdate
                                        ? const Color(0xFFD97706)
                                        : isCompleted
                                            ? const Color(0xFF1959F6) // primaryBlue
                                            : const Color(0xFF16A34A),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              displayTitle,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDriverUnavail
                                    ? const Color(0xFFDC2626)
                                    : isPriceUpdate
                                        ? const Color(0xFFD97706)
                                        : isCompleted
                                            ? const Color(0xFF1959F6)
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
                                          : isCompleted
                                              ? 'Tap to submit payment'
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
                            onTap: () async {
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
                              } else if (isCompleted) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PaymentDetailsScreen(rideData: notif),
                                  ),
                                );
                                await _loadDismissedNotifications();
                                await _syncPaidRides();
                                _fetchCustomerNotifications();
                              } else {
                                _showDriverAcceptedDialog(notif);
                              }
                            },
                          ),
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
  // FIXED: after coming back, reload the latest saved user so the new
  // name and photo show in the header.
  void _showProfileDialog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileViewScreen(user: _currentUser),
      ),
    );
    await _refreshUser();
  }

  // Payment Details Navigation
  void _showPaymentDetailsDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerPaymentHistoryScreen(user: _currentUser),
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

    final String? headerPhoto = (_currentUser?.photoUrl != null && _currentUser!.photoUrl!.isNotEmpty)
        ? (_currentUser!.photoUrl!.startsWith('http')
            ? _currentUser!.photoUrl!
            : '${ApiConstants.baseUrl}/${_currentUser!.photoUrl!.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '')}')
        : null;

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
                              child: headerPhoto != null
                                  ? Image.network(
                                      headerPhoto,
                                      key: ValueKey(headerPhoto), // forces a rebuild when the photo changes
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
                                  color: _primaryBlue,
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