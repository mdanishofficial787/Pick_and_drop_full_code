import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'driver_ride_history_screen.dart';

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
  final Set<String> _shownAssignmentPopupIds = {};
  bool _isDialogShowing = false;
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
        final idsToJoin = <String>{
          if (activeDriverId.isNotEmpty) activeDriverId,
          if (activeDriverId.isNotEmpty) 'driver-$activeDriverId',
          if (activeDriverId.isNotEmpty) 'driver_$activeDriverId',
          if (currentDriverName.isNotEmpty) currentDriverName,
          if (currentDriverName.isNotEmpty) 'driver-$currentDriverName',
          if (currentDriverName.isNotEmpty) 'driver_$currentDriverName',
        };

        for (final room in idsToJoin) {
          _socket?.emit('join', room);
          _socket?.emit('join-driver', room);
          _socket?.emit('join-room', room);
        }
      });

      final assignEvents = [
        'new-assignment',
        'ride-assigned',
        'ride-dispatched',
        'new-notification',
        'driver-notification',
        'new_assignment',
        'ride_assigned',
        'ride_dispatched',
        'new_notification',
        'schedule-ride-dispatched',
        'schedule-ride-update',
        'driver-hire-dispatched',
        'driver-hire-update',
        'travel-request-dispatched',
        'travel-request-update',
      ];

      for (final ev in assignEvents) {
        _socket?.on(ev, (data) {
          debugPrint('Live Assignment event [$ev] received: $data');
          _handleIncomingAssignment(data);
        });
      }
      _socket?.on('customer-accepted-ride', (data) => _handleIncomingNotification(data));
      _socket?.on('ride-updated', (data) => _handleIncomingAssignment(data));
    } catch (e) {
      debugPrint('Driver socket error: $e');
    }
  }

  void _handleIncomingAssignment(dynamic data) {
    if (!mounted || data == null) return;
    try {
      Map<String, dynamic> rawObj = (data is Map) ? Map<String, dynamic>.from(data) : {};
      if (rawObj['data'] is Map) rawObj = Map<String, dynamic>.from(rawObj['data']);
      if (rawObj['ride'] is Map) rawObj = Map<String, dynamic>.from(rawObj['ride']);
      if (rawObj['payload'] is Map) rawObj = Map<String, dynamic>.from(rawObj['payload']);
      if (rawObj['request'] is Map) rawObj = Map<String, dynamic>.from(rawObj['request']);
      if (rawObj['notification'] is Map) {
        final notif = Map<String, dynamic>.from(rawObj['notification']);
        rawObj = {...notif, ...rawObj};
      }

      final String notifId = (rawObj['notificationId'] ?? rawObj['id'] ?? rawObj['rideId'] ?? rawObj['requestId'] ?? '').toString();
      final String targetDriver = (rawObj['driverId'] ?? rawObj['assignedDriverId'] ?? '').toString();
      final String targetDriverName = (rawObj['driverName'] ?? rawObj['assignedDriverName'] ?? '').toString();
      final String targetDriverCode = (rawObj['driverCode'] ?? rawObj['driverReferenceId'] ?? '').toString().trim().toLowerCase();

      final myId = widget.driverId ?? '';
      final myName = currentDriverName.trim().toLowerCase();
      bool isForMe = false;
      if (myId.isNotEmpty && targetDriver.isNotEmpty && targetDriver == myId) isForMe = true;
      if (myId.isNotEmpty && targetDriverCode.isNotEmpty && (targetDriverCode == myId.toLowerCase() || targetDriverCode == myName)) isForMe = true;
      if (myName.isNotEmpty && targetDriverName.isNotEmpty && (targetDriverName.toLowerCase() == myName || targetDriverName.toLowerCase().contains(myName))) isForMe = true;

      // Customer requests with no assigned driver go ONLY to Admin console, NEVER directly to driver
      if (targetDriver.isEmpty && targetDriverName.isEmpty && targetDriverCode.isEmpty) {
        return;
      }

      if (!isForMe) return;

      final String status = (rawObj['status'] ?? rawObj['rawStatus'] ?? '').toString().toUpperCase();
      if (status == 'COMPLETED' || status == 'PAID' || status == 'CANCELLED' || status == 'REJECTED' || status == 'PENDING DISPATCH' || status == 'PENDING') {
        return;
      }

      final String reqId = (rawObj['requestId'] ?? rawObj['rideId'] ?? notifId).toString();
      final String notifKey = reqId.isNotEmpty ? reqId : 'driver_notif_${DateTime.now().millisecondsSinceEpoch}';
      if (_dismissedNotifIds.contains(notifKey)) return;

      if (!_seenNotificationKeys.contains(notifKey)) {
        _seenNotificationKeys.add(notifKey);
        rawObj['notifKey'] = notifKey;
        setState(() {
          _notifications.insert(0, rawObj);
          _unreadCount++;
        });
      }

      final isAssignment = status == 'ASSIGNED' ||
          status == 'AWAITING DRIVER ACCEPTANCE' ||
          status == 'DISPATCHED' ||
          (rawObj['type'] ?? '') == 'NEW_ASSIGNMENT' ||
          (rawObj['type'] ?? '') == 'RIDE_ASSIGNED';

      if (isAssignment && !_shownAssignmentPopupIds.contains(reqId) && !_isDialogShowing) {
        _shownAssignmentPopupIds.add(reqId);
        _playAlertAndVibrate();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRideAssignmentDialog(rawObj);
        });
      }
    } catch (e) {
      debugPrint('Error handling incoming assignment: $e');
    }
  }

  void _playAlertAndVibrate() {
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  void _handleIncomingNotification(dynamic data) {
    if (!mounted || data == null) return;
    try {
      final Map<String, dynamic> rawObj = Map<String, dynamic>.from(data is Map ? data : {});
      final String notifId = (rawObj['notificationId'] ?? rawObj['id'] ?? rawObj['rideId'] ?? '').toString();
      final String targetDriver = (rawObj['driverId'] ?? rawObj['assignedDriverId'] ?? '').toString();
      final String targetDriverName = (rawObj['driverName'] ?? rawObj['assignedDriverName'] ?? '').toString();

      final myId = widget.driverId ?? '';
      final myName = currentDriverName.trim().toLowerCase();
      bool isForMe = false;
      if (myId.isNotEmpty && targetDriver.isNotEmpty && targetDriver == myId) isForMe = true;
      final targetDriverCode = (rawObj['driverCode'] ?? rawObj['driverReferenceId'] ?? '').toString().trim().toLowerCase();
      if (myId.isNotEmpty && targetDriverCode.isNotEmpty && (targetDriverCode == myId.toLowerCase() || targetDriverCode == myName)) isForMe = true;
      if (myName.isNotEmpty && targetDriverName.isNotEmpty && (targetDriverName.toLowerCase() == myName || targetDriverName.toLowerCase().contains(myName))) isForMe = true;

      if (!isForMe) return;

      final String status = (rawObj['status'] ?? '').toString().toUpperCase();
      if (status == 'COMPLETED' || status == 'PAID' || status == 'CANCELLED' || status == 'REJECTED') {
        return;
      }

      // Check if 1 day has passed for ride assigned notifications
      final createdAtRaw = rawObj['createdAt'] ?? rawObj['time'] ?? rawObj['timestamp'];
      if (createdAtRaw != null) {
        final dt = DateTime.tryParse(createdAtRaw.toString());
        if (dt != null && DateTime.now().difference(dt).inHours >= 24) {
          return;
        }
      } else {
        rawObj['createdAt'] = DateTime.now().toIso8601String();
      }

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
                final String status = (notif['status'] ?? '').toString().toUpperCase();
                final String type = (notif['type'] ?? '').toString().toUpperCase();
                final String title = (notif['title'] ?? '').toString();

                if (title.contains('Customer Accepted') || type == 'CUSTOMER_ACCEPTED') {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showCustomerAcceptedBanner(notif);
                  });
                } else if ((status == 'ASSIGNED' || type == 'NEW_ASSIGNMENT' || type == 'RIDE_ASSIGNED') &&
                    !_shownAssignmentPopupIds.contains(nKey) &&
                    !_isDialogShowing) {
                  _shownAssignmentPopupIds.add(nKey);
                  _playAlertAndVibrate();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showRideAssignmentDialog(notif);
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

            // Exclude completed, paid, cancelled or rejected rides
            final status = (n['status'] ?? '').toString().toUpperCase();
            if (status == 'COMPLETED' || status == 'PAID' || status == 'CANCELLED' || status == 'REJECTED') {
              return false;
            }

            // Exclude route matching notifications (Route Matching feature removed)
            if (type.contains('ROUTE') || title.contains('route match') || title.contains('route setup')) {
              return false;
            }

            // Automatically remove ride assigned notification when 1 day has passed (24 hours)
            final bool isRideAssigned = type == 'RIDE_ASSIGNED' ||
                status == 'ASSIGNED' ||
                key.toUpperCase().endsWith('_ASSIGNED') ||
                title.contains('ride assigned') ||
                title.contains('ride dispatched');

            final createdAtRaw = n['createdAt'] ?? n['time'] ?? n['timestamp'];
            if (createdAtRaw != null) {
              try {
                final parsedDate = DateTime.tryParse(createdAtRaw.toString());
                if (parsedDate != null) {
                  final diff = DateTime.now().difference(parsedDate);
                  if (isRideAssigned && diff.inHours >= 24) {
                    return false;
                  }
                }
              } catch (_) {}
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
          body: json.encode({
            'driverId': widget.driverId,
            'driverName': currentDriverName,
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
        body: json.encode({
          'driverId': widget.driverId,
          'driverName': currentDriverName,
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
      // Filter out any ride assigned notification where 1 day has passed (24 hours)
      _notifications.removeWhere((n) {
        final type = (n['type'] ?? '').toString().toUpperCase();
        final status = (n['status'] ?? '').toString().toUpperCase();
        final title = (n['title'] ?? '').toString().toLowerCase();
        final key = (n['notifKey'] ?? n['notificationId'] ?? n['id'] ?? '').toString().toUpperCase();
        final bool isRideAssigned = type == 'RIDE_ASSIGNED' ||
            status == 'ASSIGNED' ||
            key.endsWith('_ASSIGNED') ||
            title.contains('ride assigned') ||
            title.contains('ride dispatched');
        if (!isRideAssigned) return false;

        final createdAtRaw = n['createdAt'] ?? n['time'] ?? n['timestamp'];
        if (createdAtRaw != null) {
          final dt = DateTime.tryParse(createdAtRaw.toString());
          if (dt != null && DateTime.now().difference(dt).inHours >= 24) {
            return true;
          }
        }
        return false;
      });
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
                                final type = (notif['type'] ?? '').toString().toUpperCase();
                                final status = (notif['status'] ?? '').toString().toUpperCase();
                                if (type == 'NEW_ASSIGNMENT' || type == 'RIDE_ASSIGNED' || status == 'ASSIGNED') {
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
                                } else {
                                  _showRideAcceptedDetailsDialog(notif);
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

  void _copyCustomerPhone(String phone) {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    Clipboard.setData(ClipboardData(text: clean));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Copied $clean to clipboard',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _respondToRideAssignment(String rideId, String status) async {
    try {
      final currentDriverId = (widget.driverId != null && widget.driverId!.isNotEmpty)
          ? widget.driverId!
          : "6a97ba8860eec88e497bd6c7";

      final headers = {'Content-Type': 'application/json'};
      final bodyData = jsonEncode({
        'status': status,
        'rawStatus': status,
        'driverId': currentDriverId,
        'driverName': currentDriverName,
      });

      http.Response response = await http.put(
        Uri.parse('$kBaseUrl/api/requests/$rideId'),
        headers: headers,
        body: bodyData,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        response = await http.put(
          Uri.parse('$kBaseUrl/api/rides/status/$rideId'),
          headers: headers,
          body: bodyData,
        ).timeout(const Duration(seconds: 8));
      }

      debugPrint('Ride $rideId response status: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error responding to ride: $e');
    }
  }

  void _showRideAssignmentDialog(Map<String, dynamic> notif) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    final String reqId = (notif['requestId'] ?? notif['rideId'] ?? notif['id'] ?? 'REQ-NEW').toString();
    final String passName = (notif['passengerName'] ?? notif['customerName'] ?? notif['name'] ?? 'Passenger').toString();
    final String passPhone = (notif['passengerPhone'] ?? notif['customerPhone'] ?? notif['phone'] ?? '').toString();

    String pickup = (notif['pickupLocation'] is Map
        ? notif['pickupLocation']['address']?.toString()
        : (notif['pickupLocation']?.toString() ?? notif['pickup']?.toString() ?? 'Pickup Location')) ?? '';
    if (pickup.isEmpty) pickup = 'Pickup Location';

    String dropoff = (notif['dropoffLocation'] is Map
        ? notif['dropoffLocation']['address']?.toString()
        : (notif['dropoffLocation']?.toString() ?? notif['drop']?.toString() ?? notif['destination']?.toString() ?? 'Drop-off Location')) ?? '';
    if (dropoff.isEmpty) dropoff = 'Drop-off Location';

    final String fare = (notif['fareFormatted'] ?? (notif['fare'] != null ? 'Rs. ${NumberFormat("#,##0").format(num.tryParse(notif['fare'].toString()) ?? 0)}' : 'Rs. 9,500')).toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.all(22),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1959F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_car_rounded, color: Color(0xFF1959F6), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🚗 New Ride Assignment!',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1959F6)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Request ID: $reqId',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF1959F6).withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded, size: 22, color: Color(0xFF1959F6)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passName,
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1F2937)),
                        ),
                        if (passPhone.isNotEmpty)
                          Text(
                            passPhone,
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                  if (passPhone.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981), size: 22),
                      tooltip: 'Call Passenger',
                      onPressed: () async {
                        final uri = Uri.parse('tel:$passPhone');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, size: 10, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pickup,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF374151)),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(width: 2, height: 16, color: Colors.grey.shade300),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dropoff,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF374151)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trip Fare',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF15803D)),
                  ),
                  Text(
                    fare,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF15803D)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _isDialogShowing = false;
                    Navigator.of(ctx).pop();
                    _respondToRideAssignment(reqId, 'REJECTED');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ride $reqId declined')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _isDialogShowing = false;
                    Navigator.of(ctx).pop();
                    _respondToRideAssignment(reqId, 'ACCEPTED');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('🎉 Ride $reqId accepted!'),
                        backgroundColor: const Color(0xFF15803D),
                      ),
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RideManagementScreen(
                          driverId: widget.driverId,
                          driverName: currentDriverName,
                          initialTabIndex: 0,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Accept Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1959F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                _isDialogShowing = false;
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RideManagementScreen(
                      driverId: widget.driverId,
                      driverName: currentDriverName,
                      initialTabIndex: 1,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.inbox_rounded, size: 18, color: AppColors.primaryBlue),
              label: const Text(
                'View in Ride Management (Requests)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
    });
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
                                InkWell(
                                  onTap: custPhone.isNotEmpty ? () => _copyCustomerPhone(custPhone) : null,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          custPhone.isNotEmpty ? custPhone : 'Verified Passenger',
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      if (custPhone.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.copy_rounded, size: 13, color: AppColors.primaryBlue),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (custPhone.isNotEmpty) ...[
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue, size: 20),
                              tooltip: 'Copy Number',
                              onPressed: () => _copyCustomerPhone(custPhone),
                            ),
                            IconButton(
                              icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981), size: 24),
                              tooltip: 'Call Passenger',
                              onPressed: () async {
                                final uri = Uri.parse('tel:$custPhone');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                            ),
                          ],
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
            final fetchedRefId = (d['driverReferenceId'] ?? d['driverCode'] ?? '').toString();
            if (fetchedRefId.trim().isNotEmpty) {
              await prefs.setString('saved_driver_reference_id$keySuffix', fetchedRefId.trim());
              await prefs.setString('driver_reference_id', fetchedRefId.trim());
              await prefs.setString('driver_code', fetchedRefId.trim());
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
                                          Icons.all_inbox_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'All Rides & Requests',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'View all incoming requests and active rides',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
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
                                                    filterPrefix: null,
                                                    moduleName:
                                                        'All Rides & Requests',
                                                    initialTabIndex: 1,
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      const Divider(height: 1),
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
                                                    initialTabIndex: 1,
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


                        // Card 5: Ride History
                        _buildMenuCard(
                          context: context,
                          icon: Icons.history_rounded,
                          title: 'Ride History',
                          subtitle: 'View your past trips, earnings, and status.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DriverRideHistoryScreen(
                                  driverId: widget.driverId ?? '',
                                  driverName: currentDriverName,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // Card 6: Profile View
                        _buildMenuCard(
                          context: context,
                          icon: Icons.person_rounded,
                          title: 'Profile View',
                          subtitle: 'View and update your driver profile settings.',
                          onTap: _openProfileSettings,
                        ),
                        const SizedBox(height: 12),

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
