import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import '/theme/app_theme.dart';
import 'preferred_routes_screen.dart';
import 'route_match_setup_screen.dart';
import 'manage_availability_screen.dart';
import 'ride_management_screen.dart';
import 'report_issue_screen.dart';
import 'profile_settings_screen.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../api_config.dart';
import 'package:ride_and_serve/constants/api_constants.dart';

class DriverDashboardScreen extends StatefulWidget {
  final String driverName;
  final String? driverId;
  final String? profilePic;
  final String? token;

  const DriverDashboardScreen({
    super.key,
    required this.driverName,
    this.driverId,
    this.profilePic,
    this.token,
  });

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  String? currentProfilePic;
  String currentDriverName = "";

  // Real-time Driver Notifications state
  io.Socket? _socket;
  Timer? _notificationPollTimer;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  final Set<String> _seenNotificationKeys = {};
  final Set<String> _dismissedNotifIds = {};
  bool _isFirstFetch = true;

  @override
  void initState() {
    super.initState();
    currentProfilePic = widget.profilePic;
    currentDriverName = widget.driverName;
    _loadSavedDriverDetails();
    _fetchProfile();
    _loadDismissedNotifications();
    _initSocketConnection();
    _startNotificationPolling();
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  void _initSocketConnection() {
    try {
      final baseUrl = ApiConstants.baseUrl;
      final activeDriverId = widget.driverId ?? '';

      _socket = io.io(
        baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect()
            .build(),
      );

      _socket?.connect();

      _socket?.onConnect((_) {
        debugPrint('Driver Socket connected to $baseUrl');
        if (activeDriverId.isNotEmpty) {
          _socket?.emit('join-driver', activeDriverId);
          _socket?.emit('join', activeDriverId);
          _socket?.emit('join-room', activeDriverId);
          _socket?.emit('join-room', 'driver_$activeDriverId');
        }
        if (currentDriverName.isNotEmpty) {
          _socket?.emit('join-driver', currentDriverName);
          _socket?.emit('join-room', 'driver_$currentDriverName');
        }
      });

      _socket?.on('customer-accepted-ride', (data) => _handleIncomingNotification(data));
      _socket?.on('driver-notification', (data) => _handleIncomingNotification(data));
      _socket?.on('ride-accepted', (data) => _handleIncomingNotification(data));
      _socket?.on('ride_accepted', (data) => _handleIncomingNotification(data));
      _socket?.on('ride-updated', (data) {
        if (data is Map && data['type'] == 'CUSTOMER_ACCEPTED') {
          _handleIncomingNotification(data['notification'] ?? data['ride'] ?? data);
        }
      });
    } catch (_) {}
  }

  void _handleIncomingNotification(dynamic data) {
    if (!mounted || data == null) return;
    try {
      final Map<String, dynamic> rawObj = Map<String, dynamic>.from(data is Map ? data : {});
      final String notifId = (rawObj['notificationId'] ?? rawObj['id'] ?? rawObj['rideId'] ?? '').toString();
      final String targetDriver = (rawObj['driverId'] ?? '').toString();
      final String targetDriverName = (rawObj['driverName'] ?? '').toString();

      final myId = widget.driverId ?? '';
      final myName = currentDriverName.trim().toLowerCase();
      bool isForMe = false;
      if (myId.isNotEmpty && targetDriver.isNotEmpty && targetDriver == myId) isForMe = true;
      final targetDriverCode = (rawObj['driverCode'] ?? rawObj['driverReferenceId'] ?? '').toString().trim().toLowerCase();
      if (myId.isNotEmpty && targetDriverCode.isNotEmpty && (targetDriverCode == myId.toLowerCase() || targetDriverCode == myName)) isForMe = true;
      if (myId.isNotEmpty && targetDriver == myId) isForMe = true;
      if (targetDriverName.isNotEmpty && (targetDriverName.toLowerCase() == myName || targetDriverName.toLowerCase().contains(myName))) isForMe = true;

      if (!isForMe) return;

      final String notifKey = notifId.isNotEmpty ? notifId : 'driver_notif_${DateTime.now().millisecondsSinceEpoch}';
      if (_dismissedNotifIds.contains(notifKey)) return;

      if (!_seenNotificationKeys.contains(notifKey)) {
        _seenNotificationKeys.add(notifKey);
        rawObj['notifKey'] = notifKey;

        setState(() {
          _notifications.insert(0, rawObj);
          _unreadCount++;
        });

        _showCustomerAcceptedBanner(rawObj);
      }
    } catch (_) {}
  }

  void _startNotificationPolling() {
    _fetchDriverNotifications();
    _notificationPollTimer?.cancel();
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchDriverNotifications();
      }
    });
  }

  Future<void> _fetchDriverNotifications() async {
    try {
      final baseUrl = ApiConstants.baseUrl;
      final driverId = widget.driverId ?? '';
      final driverName = Uri.encodeComponent(currentDriverName);

      final url = Uri.parse('$baseUrl/api/rides/driver-notifications?driverId=$driverId&driverName=$driverName');
      final res = await http.get(url).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('{}', 500));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List rawList = data['notifications'] ?? data['data'] ?? [];
        List<Map<String, dynamic>> fetched = [];
        for (var item in rawList) {
          if (item is Map) {
            fetched.add(Map<String, dynamic>.from(item));
          }
        }

        if (mounted) {
          final bool isInitialLoad = _isFirstFetch;
          if (_isFirstFetch) _isFirstFetch = false;

          List<Map<String, dynamic>> uniqueNotifs = [];
          Set<String> seenInBatch = {};
          int newlyArrived = 0;

          for (var notif in fetched) {
            final String nKey = (notif['notificationId'] ?? notif['id'] ?? notif['rideId'] ?? '').toString();
            if (nKey.isEmpty || seenInBatch.contains(nKey)) continue;
            seenInBatch.add(nKey);
            notif['notifKey'] = nKey;

            if (!_seenNotificationKeys.contains(nKey)) {
              _seenNotificationKeys.add(nKey);
              if (!isInitialLoad) {
                newlyArrived++;
                if ((notif['title'] ?? '').toString().contains('Customer Accepted') || (notif['type'] ?? '') == 'CUSTOMER_ACCEPTED') {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showCustomerAcceptedBanner(notif);
                  });
                }
              }
            }
            uniqueNotifs.add(notif);
          }

          final filtered = uniqueNotifs.where((n) {
            final key = (n['notifKey'] ?? '').toString();
            final id = (n['id'] ?? '').toString();
            final rId = (n['rideId'] ?? '').toString();
            final type = (n['type'] ?? '').toString().toUpperCase();
            final title = (n['title'] ?? '').toString().toLowerCase();

            // Exclude route matching notifications (Route Matching feature removed)
            if (type.contains('ROUTE') || title.contains('route match') || title.contains('route setup')) {
              return false;
            }

            return !_dismissedNotifIds.contains(key) &&
                   !_dismissedNotifIds.contains(id) &&
                   !_dismissedNotifIds.contains(rId);
          }).toList();

          setState(() {
            _notifications = filtered;
            if (!isInitialLoad && newlyArrived > 0) {
              _unreadCount += newlyArrived;
            } else if (isInitialLoad) {
              _unreadCount = filtered.length;
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadDismissedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('dismissed_driver_notifs') ?? [];
      if (mounted) {
        setState(() {
          _dismissedNotifIds.addAll(saved);
        });
      }
    } catch (_) {}
  }

  Future<void> _dismissNotification(Map<String, dynamic> notif, int index) async {
    final notifKey = (notif['notifKey'] ?? notif['notificationId'] ?? notif['id'] ?? 'notif_$index').toString();
    final notifId = (notif['id'] ?? notif['_id'] ?? '').toString();
    final rideId = (notif['rideId'] ?? notif['requestId'] ?? '').toString();

    setState(() {
      _dismissedNotifIds.add(notifKey);
      if (notifId.isNotEmpty) _dismissedNotifIds.add(notifId);
      if (rideId.isNotEmpty) _dismissedNotifIds.add(rideId);
      _notifications.removeAt(index);
      if (_unreadCount > 0) _unreadCount--;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_driver_notifs', _dismissedNotifIds.toList());
    } catch (_) {}

    try {
      final targetId = notif['id'] ?? notif['notificationId'] ?? notif['rideId'] ?? '';
      if (targetId.isNotEmpty) {
        http.post(
          Uri.parse(ApiConstants.dismissDriverNotification(targetId)),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'driverId': widget.driverId}),
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

  Future<void> _clearAllNotifications() async {
    for (var n in _notifications) {
      final key = (n['notifKey'] ?? n['notificationId'] ?? n['id'] ?? '').toString();
      final id = (n['id'] ?? '').toString();
      final rId = (n['rideId'] ?? '').toString();
      if (key.isNotEmpty) _dismissedNotifIds.add(key);
      if (id.isNotEmpty) _dismissedNotifIds.add(id);
      if (rId.isNotEmpty) _dismissedNotifIds.add(rId);
    }

    setState(() {
      _notifications.clear();
      _unreadCount = 0;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_driver_notifs', _dismissedNotifIds.toList());
    } catch (_) {}

    try {
      http.post(
        Uri.parse(ApiConstants.clearAllDriverNotifications),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'driverId': widget.driverId}),
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

  void _showCustomerAcceptedBanner(Map<String, dynamic> notif) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 40, left: 16, right: 16),
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif['title'] ?? '🎉 Customer Accepted Ride!',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notif['subtitle'] ?? 'Customer has accepted your ride request.',
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
          textColor: const Color(0xFF38BDF8),
          onPressed: () {
            _showRideAcceptedDetailsDialog(notif);
          },
        ),
      ),
    );
  }

  // Show Driver Ride Notifications Bottom Sheet Modal (Matching Screenshot Exactly)
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
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),

            // Modal Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_rounded, color: AppColors.primaryBlue, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Ride Notifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
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

            // Notification List
            Expanded(
              child: _notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No new notifications yet.',
                            style: TextStyle(fontSize: 15, color: Colors.black54, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'When customers accept your rides, updates will appear here.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final notif = _notifications[index];
                        final String notifKey = (notif['notifKey'] ?? notif['notificationId'] ?? notif['id'] ?? 'd_notif_$index').toString();
                        final String title = notif['title'] ?? 'Ride Update';
                        final bool isCustAccepted = title.contains('Customer Accepted') || (notif['type'] ?? '') == 'CUSTOMER_ACCEPTED';
                        final bool isRouteMatch = (notif['type'] ?? '').toString().contains('ROUTE');

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
                          onDismissed: (_) => _dismissNotification(notif, index),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isCustAccepted
                                      ? const Color(0xFF10B981).withValues(alpha: 0.14)
                                      : isRouteMatch
                                          ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                                          : AppColors.primaryBlue.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isCustAccepted
                                      ? Icons.directions_car_rounded
                                      : isRouteMatch
                                          ? Icons.alt_route_rounded
                                          : Icons.check_circle_rounded,
                                  color: isCustAccepted
                                      ? const Color(0xFF10B981)
                                      : isRouteMatch
                                          ? const Color(0xFFF59E0B)
                                          : AppColors.primaryBlue,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    notif['subtitle'] ?? '',
                                    style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isRouteMatch ? 'Tap to view suggested route' : 'Tap to view ride details',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                              onTap: () {
                                Navigator.pop(context);
                                _showRideAcceptedDetailsDialog(notif);
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

  // Open Detailed Dialog for Driver when tapping a notification
  void _showRideAcceptedDetailsDialog(Map<String, dynamic> notif) {
    final String rId = (notif['requestId'] ?? notif['rideId'] ?? notif['id'] ?? 'REQ-RIDE').toString();
    final String custName = (notif['customerName'] ?? notif['passengerName'] ?? 'Customer').toString();
    final String custPhone = (notif['customerPhone'] ?? notif['passengerPhone'] ?? '').toString();
    final String pickup = (notif['pickup'] ?? notif['pickupLocation'] ?? 'Pickup Point').toString();
    final String destination = (notif['destination'] ?? notif['dropoffLocation'] ?? 'Drop Point').toString();
    final String fare = (notif['fareFormatted'] ?? 'Rs. 9,500').toString();

    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
                ),
                const SizedBox(height: 12),

                const Text(
                  'CUSTOMER ACCEPTED RIDE!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: 0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Request ID: $rId',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryBlue),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Passenger Info Card
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
                            radius: 26,
                            backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                            child: const Icon(Icons.person_rounded, color: AppColors.primaryBlue, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  custName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  custPhone.isNotEmpty ? custPhone : 'Verified Passenger',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          if (custPhone.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981), size: 26),
                              onPressed: () async {
                                final uri = Uri.parse('tel:$custPhone');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Agreed Fare:', style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                          Text(
                            fare,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Route Points Card
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

                // Button: Open in Ride Management
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'VIEW IN RIDE MANAGEMENT',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white, letterSpacing: 0.4),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RideManagementScreen(
                            driverId: widget.driverId,
                            driverName: currentDriverName,
                            initialTabIndex: 1,
                          ),
                        ),
                      );
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
                    child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  String? _extractPhotoUrl(dynamic d) {
    if (d == null) return null;
    final p = d['driverPhoto'] ?? d['profilePic'] ?? d['profilePicture'];
    if (p is Map) return p['url']?.toString();
    final s = p?.toString();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  Future<void> _loadSavedDriverDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keySuffix = widget.driverId != null ? '_${widget.driverId}' : '';
      final savedName = prefs.getString('saved_driver_name$keySuffix') ?? prefs.getString('driver_name');
      final savedPic = prefs.getString('saved_driver_photo$keySuffix') ?? prefs.getString('driver_photo');
      if (mounted) {
        setState(() {
          if (savedName != null && savedName.trim().isNotEmpty) {
            currentDriverName = savedName.trim();
          }
          if (savedPic != null && savedPic.trim().isNotEmpty) {
            currentProfilePic = savedPic.trim();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchProfile() async {
    if (widget.driverId == null) return;
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/driver/${widget.driverId}'),
        headers: widget.token != null ? {'Authorization': 'Bearer ${widget.token}'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final d = data['driver'] ?? data['data'] ?? data;
        if (d != null) {
          final fetchedName = d['Name']?.toString() ??
              d['fullName']?.toString() ??
              d['name']?.toString() ??
              '';
          final fetchedPic = _extractPhotoUrl(d);

          if (mounted) {
            setState(() {
              if (fetchedName.trim().isNotEmpty) {
                currentDriverName = fetchedName.trim();
              }
              if (fetchedPic != null && fetchedPic.trim().isNotEmpty) {
                currentProfilePic = fetchedPic.trim();
              }
            });
          }

          try {
            final prefs = await SharedPreferences.getInstance();
            final keySuffix = widget.driverId != null ? '_${widget.driverId}' : '';
            if (fetchedName.trim().isNotEmpty) {
              await prefs.setString('saved_driver_name$keySuffix', fetchedName.trim());
              await prefs.setString('driver_name', fetchedName.trim());
            }
            if (fetchedPic != null && fetchedPic.trim().isNotEmpty) {
              await prefs.setString('saved_driver_photo$keySuffix', fetchedPic.trim());
              await prefs.setString('driver_photo', fetchedPic.trim());
            }
            final fetchedEmail = d['Email']?.toString() ?? d['email']?.toString();
            if (fetchedEmail != null && fetchedEmail.trim().isNotEmpty) {
              await prefs.setString('saved_driver_email$keySuffix', fetchedEmail.trim());
              await prefs.setString('driver_email', fetchedEmail.trim());
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _openProfileSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileSettingsScreen(
          driverName: currentDriverName,
          profilePic: currentProfilePic,
          driverId: widget.driverId,
          token: widget.token,
        ),
      ),
    );
    // Reload the latest name and photo after coming back
    await _fetchProfile();
  }

  void _showActionFeedback(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title module opened.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Top Curved Blue Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 48,
                bottom: 26,
                left: 18,
                right: 18,
              ),
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x331A56DB),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Center Header Content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _openProfileSettings,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 12, top: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                key: ValueKey(currentProfilePic),
                                radius: 36,
                                backgroundColor: Colors.white24,
                                backgroundImage: (currentProfilePic != null && currentProfilePic!.isNotEmpty)
                                    ? NetworkImage(currentProfilePic!)
                                    : null,
                                child: (currentProfilePic == null || currentProfilePic!.isEmpty)
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 40,
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 14,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1959F6),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'WELCOME, ${currentDriverName.toUpperCase()}!',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your rides & bookings',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),

                  // Top Left: Back Button
                  Positioned(
                    top: 0,
                    left: 0,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  // Top Right: Notification Bell Icon with Badge
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          tooltip: 'Ride Notifications',
                          onPressed: _showNotificationListModal,
                        ),
                        if (_unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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
                  ),
                ],
              ),
            ),

            // Dashboard Options List
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      children: [
                        _buildMenuCard(
                          context: context,
                          icon: Icons.calendar_month_outlined,
                          title: 'Preferred Routes',
                          subtitle: 'Set your preferred routes and location.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PreferredRoutesScreen(driverId: widget.driverId),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        
                        // Card 1.5: Route Match Setup
                        _buildMenuCard(
                          context: context,
                          icon: Icons.alt_route_rounded,
                          title: 'Route Match Setup',
                          subtitle: 'View and select suggested routes.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RouteMatchSetupScreen(
                                  driverId: widget.driverId,
                                  driverName: currentDriverName,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 2: Availability Management
                        _buildMenuCard(
                          context: context,
                          icon: Icons.access_time_rounded,
                          title: 'Availability Management',
                          subtitle: 'Set your available time slots.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ManageAvailabilityScreen(
                                  driverId: widget.driverId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 3: Ride Management
                        _buildMenuCard(
                          context: context,
                          icon: Icons.groups_rounded,
                          title: 'Ride management',
                          subtitle:
                              'Manage your assigned and incoming ride requests.',
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                              ),
                              builder: (ctx) => SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(
                                          bottom: 20,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Select Ride Type',
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.calendar_month_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Monthly pick and drop',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: widget.driverId,
                                                    driverName: currentDriverName,
                                                    filterPrefix: 'REQ-',
                                                    moduleName:
                                                        'Monthly Pick & Drop',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.schedule_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Scheduled rides',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: widget.driverId,
                                                    driverName: currentDriverName,
                                                    filterPrefix: 'SCH-',
                                                    moduleName:
                                                        'Scheduled Rides',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.person_outline_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Hire driver',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: widget.driverId,
                                                    driverName: currentDriverName,
                                                    filterPrefix: 'HDR-',
                                                    moduleName: 'Hire Driver',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.luggage_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Travel & Tourism',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: widget.driverId,
                                                    driverName: currentDriverName,
                                                    filterPrefix: 'TT-',
                                                    moduleName:
                                                        'Travel & Tourism',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 4: Report an Issue
                        _buildMenuCard(
                          context: context,
                          icon: Icons.warning_rounded,
                          title: 'Report an Issue',
                          subtitle: 'Select passenger(s) and report an issue.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReportIssueScreen(
                                  driverId: widget.driverId,
                                  driverName: currentDriverName,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),


                        // Profile View
                        _buildMenuCard(
                          context: context,
                          icon: Icons.history_rounded,
                          title: 'Profile View',
                          subtitle: 'View your past rides and invoices.',
                          onTap: _openProfileSettings,
                        ),
                        const SizedBox(height: 14),

                        // Need Assistance Card
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.borderLight,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Need Assistance?',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _showActionFeedback(
                                      context,
                                      'Support Hotline: Calling 24/7 Helpline...',
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.primaryBlueLight,
                                              width: 1,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.phone_rounded,
                                            color: AppColors.primaryBlue,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Contact',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryBlueLight, width: 1),
              ),
              child: Icon(icon, color: AppColors.primaryBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
