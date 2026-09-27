import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:intl/intl.dart';
import '/theme/app_theme.dart';
import '/api_config.dart';
import 'report_issue_screen.dart';
import 'ride_details_screen.dart';

class RideManagementScreen extends StatefulWidget {
  final String? driverId;
  final String driverName;
  final int initialTabIndex;
  final String? filterPrefix;
  final String? moduleName;

  const RideManagementScreen({
    super.key,
    this.driverId,
    this.driverName = 'ARBAB',
    this.initialTabIndex = 1,
    this.filterPrefix,
    this.moduleName,
  });

  @override
  State<RideManagementScreen> createState() => _RideManagementScreenState();
}

class _RideManagementScreenState extends State<RideManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<RideInfo> _assignedRides = [];
  List<RideInfo> _newRequests = [];
  // Persistent in-memory cache of all rides so they never vanish and never require manual refresh
  final Map<String, RideInfo> _allRidesCache = {};
  bool _isLoading = true;
  io.Socket? _socket;
  io.Socket? _backendSocket;
  Timer? _pollingTimer;

  // Track rides received directly via real-time Socket.IO so they are never purged
  final Set<String> _socketReceivedRideIds = {};
  // Track which rides are currently being acted on to show loading
  final Set<String> _processingRides = {};
  // Track rides rejected locally to prevent stale re-fetching from redisplaying them
  final Set<String> _locallyRejectedRideIds = {};
  // Track rides accepted/started locally so they immediately and permanently appear in Assigned tab
  final Map<String, RideInfo> _locallyAcceptedRides = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: (widget.initialTabIndex >= 0 && widget.initialTabIndex < 2)
          ? widget.initialTabIndex
          : 1,
    );
    _fetchRides();
    _initSocket();
    _startPolling();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _backendSocket?.disconnect();
    _backendSocket?.dispose();
    _pollingTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _initSocket() {
    final activeDriverId =
        (widget.driverId != null && widget.driverId!.isNotEmpty)
        ? widget.driverId!
        : '';

    // 1. Connect to Dispatcher Socket.IO instance
    _socket = io.io(kDispatchBaseUrl, <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
    });
    _bindSocketListeners(
      _socket,
      'Dispatch Server ($kDispatchBaseUrl)',
      activeDriverId,
    );
    _socket?.connect();

    // 2. Connect to local Backend Socket.IO instance if distinct
    if (kBaseUrl != kDispatchBaseUrl) {
      _backendSocket = io.io(kBaseUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': false,
      });
      _bindSocketListeners(
        _backendSocket,
        'Backend Server ($kBaseUrl)',
        activeDriverId,
      );
      _backendSocket?.connect();
    }
  }

  void _bindSocketListeners(io.Socket? socket, String label, String driverId) {
    if (socket == null) return;

    socket.onConnect((_) {
      debugPrint('Connected to Socket.IO: $label');
      final idsToJoin = {
        driverId,
        if (widget.driverName.isNotEmpty) widget.driverName,
        if (widget.driverId != null && widget.driverId!.isNotEmpty)
          widget.driverId!,
      };

      for (final id in idsToJoin) {
        socket.emit('join-driver', id);
        socket.emit('join', id);
        socket.emit('join_driver', id);
        socket.emit('join-room', id);
        socket.emit('join-room', 'driver_$id');
      }
    });

    // Real-time fare update events from Admin Portal / Backend
    const fareEvents = [
      'fare_updated',
      'fare-updated',
      'fareUpdate',
      'fare:updated',
      'fare:update',
      'fare_change',
      'fare-change',
      'ride_fare_updated',
      'ride_fare_update',
      'ride_updated',
      'ride:updated',
      'ride-updated',
      'ride_status_updated',
      'update_fare',
      'update-fare',
      'ride:fare:updated',
    ];

    for (final event in fareEvents) {
      socket.on(event, (data) {
        debugPrint('[$label] Live Fare Event [$event] received: $data');
        _handleFareUpdate(data);
      });
    }

    const assignEvents = [
      'ride-dispatched',
      'ride_dispatched',
      'ride:dispatched',
      'new-assignment',
      'new_assignment',
      'ride-assigned',
      'ride_assigned',
      'ride:assigned',
      'driver-assigned',
      'driver_assigned',
      'new_ride_request',
      'new-ride-request',
      'new-request',
      'new_request',
    ];

    for (final event in assignEvents) {
      socket.on(event, (data) {
        debugPrint('[$label] Assignment event [$event]: $data');

        Map<String, dynamic> payload = (data is Map)
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{};
        if (payload['data'] is Map) {
          payload = Map<String, dynamic>.from(payload['data']);
        }
        if (payload['ride'] is Map) {
          payload = Map<String, dynamic>.from(payload['ride']);
        }
        if (payload['payload'] is Map) {
          payload = Map<String, dynamic>.from(payload['payload']);
        }

        final payloadDriverId =
            (payload['driverId'] ??
                    payload['driver'] ??
                    payload['assignedDriverId'] ??
                    '')
                .toString();
        final payloadDriverCode =
            (payload['driverCode'] ?? payload['driverReferenceId'] ?? '')
                .toString();
        final payloadDriverName =
            (payload['assignedDriver'] ??
                    payload['assignedDriverName'] ??
                    payload['driverName'] ??
                    '')
                .toString();

        final currentDriverId = driverId;
        final currentDriverName = widget.driverName;

        bool isForMe = false;
        if (payloadDriverId.isNotEmpty && payloadDriverId == currentDriverId) {
          isForMe = true;
        }
        if (payloadDriverName.isNotEmpty &&
            payloadDriverName == currentDriverName) {
          isForMe = true;
        }
        // Fallback for general unassigned broadcasts
        if (payloadDriverId.isEmpty &&
            payloadDriverName.isEmpty &&
            payloadDriverCode.isEmpty) {
          isForMe = true;
        }

        final status = (payload['status'] ?? payload['rawStatus'] ?? '')
            .toString()
            .toUpperCase();
        final isAlreadyProcessed = [
          'ACCEPTED',
          'STARTED',
          'COMPLETED',
          'CANCELLED',
          'REJECTED',
        ].contains(status);

        if (isForMe && mounted) {
          if (!isAlreadyProcessed) {
            _showIncomingRideModal(data);
          }
          _fetchRides(silent: true);
        }
      });
    }

    socket.onDisconnect(
      (_) => debugPrint('Disconnected from Socket.IO: $label'),
    );
  }

  /// Displays real-time incoming ride notification / modal pop-up on the driver's screen
  void _showIncomingRideModal(dynamic rawData) {
    if (rawData == null) {
      _fetchRides();
      return;
    }

    Map<String, dynamic> data = (rawData is Map)
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    if (data['data'] is Map) data = Map<String, dynamic>.from(data['data']);
    if (data['ride'] is Map) data = Map<String, dynamic>.from(data['ride']);
    if (data['payload'] is Map) {
      data = Map<String, dynamic>.from(data['payload']);
    }

    final reqId =
        (data['requestId'] ??
                data['rideId'] ??
                data['ride']?['requestId'] ??
                data['_id'] ??
                data['id'] ??
                'REQ-NEW')
            .toString();

    final passName =
        (data['passengerName'] ??
                data['customerName'] ??
                data['ride']?['passengerName'] ??
                data['passenger']?['name'] ??
                data['customer']?['fullName'] ??
                'Customer')
            .toString();

    final passPhone =
        (data['passengerPhone'] ??
                data['customerPhone'] ??
                data['phone'] ??
                data['PhoneNumber'] ??
                data['userPhone'] ??
                data['ride']?['passengerPhone'] ??
                '')
            .toString();

    final pickup =
        (data['pickupLocation'] is Map
            ? data['pickupLocation']['address']?.toString()
            : (data['pickupLocation']?.toString() ??
                  data['ride']?['pickupLocation']?.toString() ??
                  'Pickup Location')) ??
        '';

    final dropoff =
        (data['dropoffLocation'] is Map
            ? data['dropoffLocation']['address']?.toString()
            : (data['dropoffLocation']?.toString() ??
                  data['dropLocation']?.toString() ??
                  data['ride']?['dropoffLocation']?.toString() ??
                  'Drop-off Location')) ??
        '';

    final rawFare = RideInfo.extractRawFare(data);
    final fareStr = RideInfo.formatFare(rawFare, pickup: pickup, drop: dropoff);

    String moduleType = 'Unknown Module';
    Color moduleColor = const Color(0xFF1959F6);
    IconData moduleIcon = Icons.directions_car;

    if (reqId.startsWith('REQ-')) {
      moduleType = 'Monthly Pickup';
      moduleColor = const Color(0xFF1959F6); // Blue
      moduleIcon = Icons.calendar_month;
    } else if (reqId.startsWith('SCH-')) {
      moduleType = 'Schedule Ride';
      moduleColor = const Color(0xFF9333EA); // Purple
      moduleIcon = Icons.access_time_filled;
    } else if (reqId.startsWith('TT-')) {
      moduleType = 'Travel & Tourism';
      moduleColor = const Color(0xFFEAB308); // Yellow
      moduleIcon = Icons.luggage;
    } else if (reqId.startsWith('HDR-')) {
      moduleType = 'Hire Driver Duty';
      moduleColor = const Color(0xFF15803D); // Green
      moduleIcon = Icons.person_add_alt_1;
    }

    final incomingRide = RideInfo(
      id: reqId,
      requestId: reqId,
      name: passName,
      phone: passPhone,
      pickup: pickup,
      drop: dropoff,
      date:
          (data['date'] ??
                  data['startingFrom'] ??
                  data['startDate'] ??
                  data['travelDate'] ??
                  'Today')
              .toString(),
      scheduledTime: (data['scheduledTime'] ?? data['timeToLeave'] ?? 'ASAP')
          .toString(),
      fare: fareStr,
      status: (data['status'] ?? data['rawStatus'] ?? 'ASSIGNED')
          .toString()
          .toUpperCase(),
      assignedDriver: (data['assignedDriver'] ?? widget.driverName).toString(),
      assignedDriverId: (data['assignedDriverId'] ?? widget.driverId ?? '')
          .toString(),
    );

    _socketReceivedRideIds.add(reqId);
    _allRidesCache[reqId] = incomingRide;
    _fetchRides(silent: true);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: moduleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(moduleIcon, color: moduleColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    moduleType,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: moduleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Incoming Assignment',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7280),
                    ),
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
            // Passenger Info
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: moduleColor.withValues(alpha: 0.1),
                  child: Icon(Icons.person, size: 18, color: moduleColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        passName,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      if (passPhone.isNotEmpty)
                        Text(
                          passPhone,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Conditional Dynamic Fields
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pick and Drop always shown for most, but modify if TT/HDR
                  if (reqId.startsWith('REQ-') || reqId.startsWith('SCH-')) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle, size: 10, color: moduleColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pickup.isNotEmpty ? pickup : 'Pickup Address',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Container(
                        width: 2,
                        height: 16,
                        color: Colors.grey.shade300,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 12,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dropoff.isNotEmpty ? dropoff : 'Drop-off Address',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (reqId.startsWith('SCH-')) ...[
                    const Divider(),
                    Text(
                      'Type: ${data["rideType"] ?? "One Way"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    Text(
                      'Start: ${data["startingFrom"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    Text(
                      'Time: ${data["timeToReach"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                  if (reqId.startsWith('TT-')) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle, size: 10, color: moduleColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pickup.isNotEmpty ? pickup : 'Pickup Address',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      'Travel Date: ${data["travelDate"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    Text(
                      'Return Date: ${data["returnDate"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    Text(
                      'Passengers: ${data["passengersCount"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                  if (reqId.startsWith('HDR-')) ...[
                    Text(
                      'Start Date: ${data["startDate"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    Text(
                      'End Date: ${data["endDate"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    Text(
                      'Duration: ${data["duration"] ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Fare Banner
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
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                  Text(
                    fareStr,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF15803D),
                    ),
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
                    Navigator.of(ctx).pop();
                    _confirmAndReject(incomingRide);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _updateRideStatus(
                      incomingRide.id,
                      'ACCEPTED',
                      ride: incomingRide,
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Accept Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: moduleColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Handles real-time fare & ride updates without requiring app reload
  void _handleFareUpdate(dynamic data) {
    if (data == null) return;

    String? targetRideId;
    dynamic rawFare;

    if (data is Map) {
      targetRideId =
          (data['rideId'] ??
                  data['_id'] ??
                  data['id'] ??
                  data['requestId'] ??
                  data['ride']?['_id'] ??
                  data['ride']?['id'] ??
                  data['ride']?['rideId'] ??
                  data['data']?['rideId'] ??
                  data['data']?['_id'])
              ?.toString();

      rawFare = RideInfo.extractRawFare(data);
    }

    // If no explicit fare found in payload, re-fetch silently
    if (rawFare == null) {
      _fetchRides(silent: true);
      return;
    }

    final formattedFare = RideInfo.formatFare(rawFare);
    bool didUpdate = false;

    if (mounted) {
      setState(() {
        // Update in requests list
        for (int i = 0; i < _newRequests.length; i++) {
          final r = _newRequests[i];
          if (targetRideId == null ||
              r.id == targetRideId ||
              r.requestId == targetRideId) {
            _newRequests[i] = r.copyWith(fare: formattedFare);
            didUpdate = true;
          }
        }

        // Update in assigned list
        for (int i = 0; i < _assignedRides.length; i++) {
          final r = _assignedRides[i];
          if (targetRideId == null ||
              r.id == targetRideId ||
              r.requestId == targetRideId) {
            _assignedRides[i] = r.copyWith(fare: formattedFare);
            didUpdate = true;
          }
        }
      });

      if (didUpdate) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.price_change_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fare has been updated by Admin: $formattedFare',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF15803D),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        // If the ride wasn't in memory yet, re-fetch list
        _fetchRides(silent: true);
      }
    }
  }

  /// Re-fetch fallback: queries GET /api/rides/:id to ensure latest fare
  Future<void> fetchRideById(String rideId) async {
    try {
      // 1. Try local/admin backend first
      http.Response response = await http.get(
        Uri.parse('$kBaseUrl/api/rides/$rideId'),
      );

      // 2. Fallback to dispatcher URL if 404
      if (response.statusCode == 404 && kDispatchBaseUrl != kBaseUrl) {
        response = await http.get(
          Uri.parse('$kDispatchBaseUrl/api/rides/$rideId'),
        );
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final rideData = body['data'] ?? body['ride'] ?? body;
        if (rideData != null && rideData is Map) {
          final rawFare = RideInfo.extractRawFare(rideData);
          final formattedFare = RideInfo.formatFare(rawFare);
          if (mounted) {
            setState(() {
              for (int i = 0; i < _newRequests.length; i++) {
                if (_newRequests[i].id == rideId ||
                    _newRequests[i].requestId == rideId) {
                  _newRequests[i] = _newRequests[i].copyWith(
                    fare: formattedFare,
                  );
                }
              }
              for (int i = 0; i < _assignedRides.length; i++) {
                if (_assignedRides[i].id == rideId ||
                    _assignedRides[i].requestId == rideId) {
                  _assignedRides[i] = _assignedRides[i].copyWith(
                    fare: formattedFare,
                  );
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error in fetchRideById ($rideId): $e");
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _fetchRides(silent: true);
      }
    });
  }

  Future<void> _fetchRides({bool silent = false}) async {
    if (widget.driverId == null) return;
    if (!silent && _allRidesCache.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final List<dynamic> combinedRawList = [];

      List<dynamic> parseRidesPayload(dynamic body) {
        if (body == null) return [];
        if (body is List) return body;
        if (body is Map) {
          if (body['rides'] is List) return body['rides'] as List;
          if (body['data'] is List) return body['data'] as List;
          if (body['data'] is Map && body['data']['rides'] is List) {
            return body['data']['rides'] as List;
          }
        }
        return [];
      }

      final activeDriverId =
          (widget.driverId != null && widget.driverId!.isNotEmpty)
          ? widget.driverId!
          : '';

      // 1. Primary: GET /api/rides?status=assigned
      try {
        final uri = Uri.parse('$kBaseUrl/api/rides?status=assigned');
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          combinedRawList.addAll(parseRidesPayload(body));
        }
      } catch (e) {
        debugPrint("Fetch primary assigned rides error: $e");
      }

      // 2. Specific Driver GET /api/rides/driver/{driverId}
      if (combinedRawList.isEmpty) {
        try {
          final response = await http
              .get(Uri.parse('$kBaseUrl/api/rides/driver/$activeDriverId'))
              .timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            combinedRawList.addAll(parseRidesPayload(body));
          }
        } catch (_) {}
      }

      // 3. Fallback: GET /api/rides
      if (combinedRawList.isEmpty) {
        try {
          final response = await http
              .get(Uri.parse('$kBaseUrl/api/rides'))
              .timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            combinedRawList.addAll(parseRidesPayload(body));
          }
        } catch (e) {
          debugPrint("Fetch /api/rides error: $e");
        }
      }

      // 4. Fallback: GET /api/requests if everything returned empty
      if (combinedRawList.isEmpty) {
        try {
          final response = await http
              .get(Uri.parse('$kBaseUrl/api/requests'))
              .timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            combinedRawList.addAll(parseRidesPayload(body));
          }
        } catch (e) {
          debugPrint("Fetch /api/requests fallback error: $e");
        }
      }

      // 5. Fallback to dispatcher server if distinct from kBaseUrl and list is still empty
      if (combinedRawList.isEmpty && kDispatchBaseUrl != kBaseUrl) {
        try {
          final response = await http
              .get(Uri.parse('$kDispatchBaseUrl/api/rides?status=assigned'))
              .timeout(const Duration(seconds: 12));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            combinedRawList.addAll(parseRidesPayload(body));
          }
        } catch (e) {
          debugPrint("Fetch kDispatchBaseUrl error: $e");
        }
      }

      // Filter array to only display trips belonging to this logged-in driver
      final knownDriverNames = {
        if (widget.driverName.isNotEmpty)
          widget.driverName.trim().toLowerCase(),
      };

      final knownDriverIds = {
        if (widget.driverId != null && widget.driverId!.isNotEmpty)
          widget.driverId!.trim().toLowerCase(),
      };

      final filteredRawList = combinedRawList.where((raw) {
        if (raw is! Map) return false;
        final ride = Map<String, dynamic>.from(raw);

        final reqId = (ride['requestId'] ?? ride['id'] ?? ride['_id'] ?? '')
            .toString();

        if (widget.filterPrefix != null && widget.filterPrefix!.isNotEmpty) {
          if (!reqId.startsWith(widget.filterPrefix!)) return false;
        }

        if (reqId.isNotEmpty && _socketReceivedRideIds.contains(reqId)) {
          return true;
        }

        final asgDriver =
            (ride['assignedDriver'] ?? ride['assignedDriverName'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        final asgDriverName = (ride['assignedDriverName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final asgDriverId =
            (ride['assignedDriverId'] ??
                    ride['driverId'] ??
                    ride['driver'] ??
                    '')
                .toString()
                .trim()
                .toLowerCase();
        final rideDriverId = (ride['driverId'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final rideDriver = (ride['driver'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        final driverNameMatch = knownDriverNames.any(
          (k) =>
              (asgDriver.isNotEmpty &&
                  (asgDriver == k ||
                      asgDriver.contains(k) ||
                      k.contains(asgDriver))) ||
              (asgDriverName.isNotEmpty &&
                  (asgDriverName == k ||
                      asgDriverName.contains(k) ||
                      k.contains(asgDriverName))),
        );

        final driverIdMatch = knownDriverIds.any(
          (k) =>
              (asgDriverId.isNotEmpty &&
                  (asgDriverId == k ||
                      asgDriverId.contains(k) ||
                      k.contains(asgDriverId))) ||
              (rideDriverId.isNotEmpty &&
                  (rideDriverId == k ||
                      rideDriverId.contains(k) ||
                      k.contains(rideDriverId))) ||
              (rideDriver.isNotEmpty &&
                  (rideDriver == k ||
                      rideDriver.contains(k) ||
                      k.contains(rideDriver))),
        );

        return driverNameMatch || driverIdMatch;
      }).toList();

      // Merge all newly fetched rides into the persistent cache and remove stale ones
      final Map<String, RideInfo> nextCache = {};

      for (final r in filteredRawList) {
        if (r is Map) {
          try {
            final map = Map<String, dynamic>.from(r);
            final ride = RideInfo.fromJson(map);
            final key = ride.requestId.isNotEmpty ? ride.requestId : ride.id;
            if (key.isNotEmpty) {
              final existing = _allRidesCache[key];
              if (existing != null &&
                  (ride.name == 'Customer' ||
                      ride.pickup == 'Pickup Location')) {
                nextCache[key] = ride.copyWith(
                  name: existing.name != 'Customer' ? existing.name : ride.name,
                  phone: existing.phone.isNotEmpty
                      ? existing.phone
                      : ride.phone,
                  pickup: existing.pickup != 'Pickup Location'
                      ? existing.pickup
                      : ride.pickup,
                  drop: existing.drop != 'Drop-off Location'
                      ? existing.drop
                      : ride.drop,
                  fare:
                      (existing.fare.isNotEmpty && existing.fare != 'Rs. 9,500')
                      ? existing.fare
                      : ride.fare,
                );
              } else {
                nextCache[key] = ride;
              }
              if (ride.id.isNotEmpty) nextCache[ride.id] = nextCache[key]!;
              if (ride.requestId.isNotEmpty) {
                nextCache[ride.requestId] = nextCache[key]!;
              }
            }
          } catch (pe) {
            debugPrint("Error parsing individual ride: $pe");
          }
        }
      }
      _allRidesCache.clear();
      _allRidesCache.addAll(nextCache);

      // Deduplicate unique rides from cache
      final uniqueRides = <RideInfo>[];
      final seenIds = <String>{};
      for (final ride in _allRidesCache.values) {
        final key = ride.requestId.isNotEmpty ? ride.requestId : ride.id;
        if (key.isNotEmpty && !seenIds.contains(key)) {
          seenIds.add(key);
          if (ride.id.isNotEmpty) seenIds.add(ride.id);
          if (ride.requestId.isNotEmpty) seenIds.add(ride.requestId);
          uniqueRides.add(ride);
        }
      }

      if (mounted) {
        setState(() {
          // Filter out any ride that was locally rejected, completed/cancelled, or is an empty ghost record
          final activeRides = uniqueRides.where((r) {
            final isLocallyRejected =
                _locallyRejectedRideIds.contains(r.id) ||
                _locallyRejectedRideIds.contains(r.requestId);
            final isTerminal =
                r.status == 'REJECTED' ||
                r.status == 'CANCELLED' ||
                r.status == 'COMPLETED';
            final isGhost =
                (r.pickup.isEmpty || r.pickup == 'N/A') &&
                (r.drop.isEmpty || r.drop == 'N/A') &&
                (r.name == 'Customer' || r.name.isEmpty) &&
                r.phone.isEmpty;
            return !isLocallyRejected && !isTerminal && !isGhost;
          }).toList();

          // Apply local accepted / started status overrides
          final List<RideInfo> processedRides = activeRides.map((r) {
            if (_locallyAcceptedRides.containsKey(r.id)) {
              return r.copyWith(status: _locallyAcceptedRides[r.id]!.status);
            }
            if (r.requestId.isNotEmpty &&
                _locallyAcceptedRides.containsKey(r.requestId)) {
              return r.copyWith(
                status: _locallyAcceptedRides[r.requestId]!.status,
              );
            }
            return r;
          }).toList();

          // Ensure any locally accepted rides are included in the list
          for (final localRide in _locallyAcceptedRides.values) {
            if (widget.filterPrefix != null &&
                widget.filterPrefix!.isNotEmpty) {
              final rId = localRide.requestId.isNotEmpty
                  ? localRide.requestId
                  : localRide.id;
              if (!rId.startsWith(widget.filterPrefix!)) continue;
            }

            final exists = processedRides.any(
              (r) =>
                  r.id == localRide.id ||
                  (r.requestId.isNotEmpty &&
                      r.requestId == localRide.requestId),
            );
            if (!exists &&
                !_locallyRejectedRideIds.contains(localRide.id) &&
                !_locallyRejectedRideIds.contains(localRide.requestId) &&
                localRide.status != 'COMPLETED' &&
                localRide.status != 'CANCELLED') {
              processedRides.insert(0, localRide);
            }
          }

          // Requests tab: incoming rides waiting for driver acceptance
          _newRequests = processedRides.where((r) {
            final s = r.status.toUpperCase();
            return s == 'PENDING DISPATCH' ||
                s == 'PENDING' ||
                s == 'ASSIGNED' ||
                s == 'AWAITING DRIVER ACCEPTANCE' ||
                s == 'DISPATCHED' ||
                s == 'WAITING FOR DRIVER';
          }).toList();

          // Assigned tab: rides that driver has ACCEPTED or STARTED
          _assignedRides = processedRides
              .where((r) => r.status == 'ACCEPTED' || r.status == 'STARTED')
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching rides: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateRideStatus(
    String rideId,
    String newStatus, {
    RideInfo? ride,
  }) async {
    RideInfo? targetRide = ride;
    if (targetRide == null) {
      for (final r in _newRequests) {
        if (r.id == rideId || r.requestId == rideId) {
          targetRide = r;
          break;
        }
      }
      if (targetRide == null) {
        for (final r in _assignedRides) {
          if (r.id == rideId || r.requestId == rideId) {
            targetRide = r;
            break;
          }
        }
      }
    }

    setState(() {
      _processingRides.add(rideId);
      if (newStatus == 'REJECTED') {
        _locallyRejectedRideIds.add(rideId);
        if (targetRide != null && targetRide.requestId.isNotEmpty) {
          _locallyRejectedRideIds.add(targetRide.requestId);
        }
        _locallyAcceptedRides.remove(rideId);
        if (targetRide != null && targetRide.requestId.isNotEmpty) {
          _locallyAcceptedRides.remove(targetRide.requestId);
        }
        _allRidesCache.remove(rideId);
        if (targetRide != null && targetRide.requestId.isNotEmpty) {
          _allRidesCache.remove(targetRide.requestId);
        }
        _newRequests.removeWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
        _assignedRides.removeWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
      } else if (newStatus == 'ACCEPTED') {
        final existingFare =
            (targetRide != null &&
                targetRide.fare.isNotEmpty &&
                targetRide.fare != 'Rs. 0')
            ? targetRide.fare
            : 'Rs. 9,500';

        final acceptedRide =
            (targetRide ??
                    RideInfo(
                      id: rideId,
                      requestId: rideId,
                      name: 'Customer',
                      phone: '',
                      pickup: '',
                      drop: '',
                      date: '',
                      scheduledTime: '',
                      fare: existingFare,
                      status: 'ACCEPTED',
                    ))
                .copyWith(status: 'ACCEPTED', fare: existingFare);

        _locallyAcceptedRides[rideId] = acceptedRide;
        if (acceptedRide.id.isNotEmpty) {
          _locallyAcceptedRides[acceptedRide.id] = acceptedRide;
        }
        if (acceptedRide.requestId.isNotEmpty) {
          _locallyAcceptedRides[acceptedRide.requestId] = acceptedRide;
        }

        _allRidesCache[rideId] = acceptedRide;
        if (acceptedRide.id.isNotEmpty) {
          _allRidesCache[acceptedRide.id] = acceptedRide;
        }
        if (acceptedRide.requestId.isNotEmpty) {
          _allRidesCache[acceptedRide.requestId] = acceptedRide;
        }

        // 1. Remove immediately from incoming requests
        _newRequests.removeWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
        // 2. Remove duplicate from assigned if any
        _assignedRides.removeWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
        // 3. Add to the top of assigned rides
        bool shouldAdd = true;
        if (widget.filterPrefix != null && widget.filterPrefix!.isNotEmpty) {
          final rId = acceptedRide.requestId.isNotEmpty
              ? acceptedRide.requestId
              : acceptedRide.id;
          if (!rId.startsWith(widget.filterPrefix!)) shouldAdd = false;
        }
        if (shouldAdd) {
          _assignedRides.insert(0, acceptedRide);
        }
        // 4. Immediately switch tab to Assigned (Tab 0)
        _tabController.animateTo(0);
      } else if (newStatus == 'STARTED') {
        final existingFare =
            (targetRide != null &&
                targetRide.fare.isNotEmpty &&
                targetRide.fare != 'Rs. 0')
            ? targetRide.fare
            : 'Rs. 9,500';

        final startedRide =
            (targetRide ??
                    RideInfo(
                      id: rideId,
                      requestId: rideId,
                      name: 'Customer',
                      phone: '',
                      pickup: '',
                      drop: '',
                      date: '',
                      scheduledTime: '',
                      fare: existingFare,
                      status: 'STARTED',
                    ))
                .copyWith(status: 'STARTED', fare: existingFare);

        _locallyAcceptedRides[rideId] = startedRide;
        if (startedRide.id.isNotEmpty) {
          _locallyAcceptedRides[startedRide.id] = startedRide;
        }
        if (startedRide.requestId.isNotEmpty) {
          _locallyAcceptedRides[startedRide.requestId] = startedRide;
        }

        _allRidesCache[rideId] = startedRide;
        if (startedRide.id.isNotEmpty) {
          _allRidesCache[startedRide.id] = startedRide;
        }
        if (startedRide.requestId.isNotEmpty) {
          _allRidesCache[startedRide.requestId] = startedRide;
        }

        final idx = _assignedRides.indexWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
        if (idx != -1) {
          _assignedRides[idx] = startedRide;
        } else {
          bool shouldAdd = true;
          if (widget.filterPrefix != null && widget.filterPrefix!.isNotEmpty) {
            final rId = startedRide.requestId.isNotEmpty
                ? startedRide.requestId
                : startedRide.id;
            if (!rId.startsWith(widget.filterPrefix!)) shouldAdd = false;
          }
          if (shouldAdd) {
            _assignedRides.insert(0, startedRide);
          }
        }
      } else if (newStatus == 'COMPLETED') {
        _locallyAcceptedRides.remove(rideId);
        if (targetRide != null && targetRide.requestId.isNotEmpty) {
          _locallyAcceptedRides.remove(targetRide.requestId);
        }
        _allRidesCache.remove(rideId);
        if (targetRide != null && targetRide.requestId.isNotEmpty) {
          _allRidesCache.remove(targetRide.requestId);
        }
        _assignedRides.removeWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
        _newRequests.removeWhere(
          (r) => r.id == rideId || r.requestId == rideId,
        );
      }
    });

    try {
      final currentDriverId =
          (widget.driverId != null && widget.driverId!.isNotEmpty)
          ? widget.driverId!
          : "6a97ba8860eec88e497bd6c7";

      final headers = {'Content-Type': 'application/json'};
      final bodyData = jsonEncode({
        'status': newStatus,
        'rawStatus': newStatus,
        'driverId': currentDriverId,
      });

      // 1. Primary endpoint on dispatch server: PUT /api/requests/:id
      http.Response response = await http.put(
        Uri.parse('$kDispatchBaseUrl/api/requests/$rideId'),
        headers: headers,
        body: bodyData,
      );

      // 2. If 404, try dispatch PUT /api/rides/status/:id
      if (response.statusCode == 404) {
        response = await http.put(
          Uri.parse('$kDispatchBaseUrl/api/rides/status/$rideId'),
          headers: headers,
          body: bodyData,
        );
      }

      // 3. Also notify local backend if kDispatchBaseUrl != kBaseUrl
      if (kDispatchBaseUrl != kBaseUrl) {
        try {
          final headers = {'Content-Type': 'application/json'};

          final bodyData = jsonEncode({
            'action': newStatus,
            'driverId': widget.driverId,
            'driverCode': widget.driverName,
          });

          // Determine correct endpoint based on prefix
          String endpoint = '/api/rides/$rideId/driver-response';
          String rId = targetRide?.requestId ?? rideId;

          if (rId.startsWith('REQ-')) {
            endpoint = '/api/rides/$rideId/driver-response';
          } else if (rId.startsWith('SCH-')) {
            endpoint = '/api/schedule-rides/$rideId/driver-response';
          } else if (rId.startsWith('TT-')) {
            endpoint = '/api/travel-requests/$rideId/driver-response';
          } else if (rId.startsWith('HDR-')) {
            endpoint = '/api/driver-hire/$rideId/driver-response';
          } else {
            // Fallback legacy endpoint if no prefix
            endpoint = '/api/rides/$rideId/driver-response';
          }

          http.Response response = await http.patch(
            Uri.parse('$kBaseUrl$endpoint'),
            headers: headers,
            body: bodyData,
          );

          if (response.statusCode != 200 &&
              response.statusCode != 201 &&
              kDispatchBaseUrl != kBaseUrl) {
            response = await http.patch(
              Uri.parse('$kDispatchBaseUrl$endpoint'),
              headers: headers,
              body: bodyData,
            );
          }

          if (response.statusCode != 200 && response.statusCode != 201) {
            final errorMsg =
                jsonDecode(response.body)['message'] ??
                'Failed to update status';
            throw Exception(errorMsg);
          }
        } catch (e) {
          // ignore
        }
      }
      debugPrint(
        "UPDATE RIDE STATUS [$newStatus]: ${response.statusCode} - ${response.body}",
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchRides(silent: true);
        if (mounted) {
          if (newStatus == 'ACCEPTED') {
            _tabController.animateTo(0);
          }
          final isAccepted = newStatus == 'ACCEPTED';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    isAccepted
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAccepted
                          ? 'Ride Accepted! Your profile picture, phone & vehicle details have been shared with the customer.'
                          : 'Ride ${_statusLabel(newStatus)} successfully',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: _statusSnackColor(newStatus),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: Duration(seconds: isAccepted ? 4 : 2),
            ),
          );
        }
      } else {
        String errorMsg = 'Failed to update ride';
        try {
          final resJson = jsonDecode(response.body);
          errorMsg = resJson['message'] ?? resJson['error'] ?? errorMsg;
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint("Error updating ride: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processingRides.remove(rideId));
    }
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return 'accepted';
      case 'REJECTED':
        return 'rejected';
      case 'STARTED':
        return 'started';
      case 'COMPLETED':
        return 'completed';
      default:
        return status.toLowerCase();
    }
  }

  Color _statusSnackColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return const Color(0xFF1959F6);
      case 'REJECTED':
        return const Color(0xFFDC2626);
      case 'STARTED':
        return const Color(0xFF15803D);
      case 'COMPLETED':
        return const Color(0xFF15803D);
      default:
        return Colors.grey;
    }
  }

  /// Shows a confirmation dialog before rejecting the customer's ride
  Future<void> _confirmAndReject(
    RideInfo ride, {
    BuildContext? sheetContext,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cancel_outlined,
                color: Color(0xFFDC2626),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Reject Ride?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to reject the ride request from:',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ride.name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ride.requestId,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  if (ride.pickup.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '📍 ${ride.pickup}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(
              'Yes, Reject',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _locallyRejectedRideIds.add(ride.id);
      if (ride.requestId.isNotEmpty) {
        _locallyRejectedRideIds.add(ride.requestId);
      }
      if (sheetContext != null &&
          sheetContext.mounted &&
          Navigator.of(sheetContext).canPop()) {
        Navigator.of(sheetContext).pop();
      }
      await _updateRideStatus(ride.id, 'REJECTED', ride: ride);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            size: 24,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.moduleName ?? 'Ride Management',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
            tooltip: 'Refresh',
            onPressed: _fetchRides,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF4B5563),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Assigned'),
                          if (_assignedRides.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_assignedRides.length}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Requests'),
                          if (_newRequests.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_newRequests.length}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tab Bar Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Assigned Rides (Accepted/Started)
                        _buildRidesList(_assignedRides, tabType: 'assigned'),
                        // Tab 2: New Requests (Assigned, awaiting driver response)
                        _buildRidesList(_newRequests, tabType: 'requests'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRidesList(List<RideInfo> rides, {required String tabType}) {
    if (rides.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tabType == 'requests'
                  ? Icons.inbox_outlined
                  : Icons.directions_car_outlined,
              size: 52,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              tabType == 'requests'
                  ? 'No new ride requests'
                  : 'No assigned rides',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tabType == 'requests'
                  ? 'New customer requests will appear here'
                  : 'Accepted rides will appear here',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchRides,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: rides.length,
        separatorBuilder: (_, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          return _buildRideCard(rides[index], tabType);
        },
      ),
    );
  }

  Widget _buildRideCard(RideInfo ride, String tabType) {
    // Determine status badge color
    Color statusColor;
    String statusLabel;
    switch (ride.status.toUpperCase()) {
      case 'ASSIGNED':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'New Request';
        break;
      case 'ACCEPTED':
        statusColor = const Color(0xFF1959F6);
        statusLabel = 'Accepted';
        break;
      case 'STARTED':
        statusColor = const Color(0xFF15803D);
        statusLabel = 'On Trip';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = ride.status;
    }

    final bool isProcessing = _processingRides.contains(ride.id);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RideDetailsScreen(
                ride: ride,
                tabType: tabType,
                driverId: widget.driverId ?? '',
              ),
            ),
          );
          if (result == true) {
            _fetchRides();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: tabType == 'requests'
                  ? const Color(0xFFD97706).withValues(alpha: 0.3)
                  : const Color(0xFFE5E7EB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER: Avatar + Name/Request + Status badge ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0E7FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF1959F6),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name
                    Expanded(
                      child: Text(
                        ride.name,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    // ── HAMBURGER MENU BUTTON (Only in Assigned Tab) ──
                    if (tabType == 'assigned') ...[
                      const SizedBox(width: 8),
                      Theme(
                        data: Theme.of(context).copyWith(
                          popupMenuTheme: PopupMenuThemeData(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            color: Colors.white,
                            elevation: 8,
                          ),
                        ),
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.menu_rounded,
                              color: Color(0xFF374151),
                              size: 18,
                            ),
                          ),
                          tooltip: 'Options',
                          onSelected: (value) {
                            if (value == 'write_issue') {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReportIssueScreen(
                                    driverId: widget.driverId,
                                    initialReason:
                                        'Cannot Take Customer / Passenger Issue',
                                    customerName: ride.name,
                                    customerPhone: ride.phone,
                                    requestId: ride.requestId.isNotEmpty
                                        ? ride.requestId
                                        : ride.id,
                                    pickupLocation: ride.pickup,
                                    dropoffLocation: ride.drop,
                                    fare: ride.fare,
                                    rideId: ride.id,
                                  ),
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'write_issue',
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.rate_review_outlined,
                                      color: Color(0xFFDC2626),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Write your issue',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Divider(height: 1, color: Colors.grey.shade100),

              // ── LOCATION SECTION ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 2),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1959F6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 28,
                          color: Colors.grey.shade300,
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFDC2626),
                              width: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PICKUP',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ride.pickup.isNotEmpty ? ride.pickup : 'N/A',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'DROP OFF',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ride.drop.isNotEmpty ? ride.drop : 'N/A',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: Colors.grey.shade100),

              // ── ACTION BUTTONS ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: isProcessing
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _buildActionButtons(ride, tabType),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Displays detailed ride view in a modal bottom sheet with dynamic fare
  Widget _buildActionButtons(
    RideInfo ride,
    String tabType, {
    BuildContext? sheetContext,
  }) {
    // ── REQUESTS TAB: New ride assigned / dispatched to driver ──
    // Driver can ACCEPT (move to assigned) or REJECT (decline the customer)
    if (tabType == 'requests') {
      return Row(
        children: [
          // REJECT button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () =>
                  _confirmAndReject(ride, sheetContext: sheetContext),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(
                'Reject',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ACCEPT button
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () {
                if (sheetContext != null &&
                    Navigator.of(sheetContext).canPop()) {
                  Navigator.of(sheetContext).pop();
                }
                _updateRideStatus(ride.id, 'ACCEPTED', ride: ride);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                'Accept Ride',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1959F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ── ASSIGNED TAB: Ride accepted / active trip ──
    if (tabType == 'assigned' &&
        (ride.status == 'ACCEPTED' || ride.status == 'STARTED')) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (sheetContext != null &&
                        Navigator.of(sheetContext).canPop()) {
                      Navigator.of(sheetContext).pop();
                    }
                    _updateRideStatus(ride.id, 'CANCELLED', ride: ride);
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: Text(
                    'Cancel Ride',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Opening Navigation...')),
                    );
                  },
                  icon: const Icon(Icons.navigation_outlined, size: 16),
                  label: Text(
                    'Navigate',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1959F6),
                    side: const BorderSide(color: Color(0xFF1959F6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (sheetContext != null &&
                    Navigator.of(sheetContext).canPop()) {
                  Navigator.of(sheetContext).pop();
                }
                _updateRideStatus(ride.id, 'COMPLETED', ride: ride);
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                'Complete Trip',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // No buttons for other statuses
    return const SizedBox.shrink();
  }
}

class RideInfo {
  final String id;
  final String requestId;
  final String name;
  final String phone;
  final String pickup;
  final String drop;
  final String date;
  final String scheduledTime;
  final String scheduleType;
  final String pickupTime;
  final String dropoffTime;
  final String selectedDays;
  final String fare;
  final String vehicleType;
  final String acPreference;
  final String notes;
  final String status;
  final String assignedDriver;
  final String assignedDriverId;

  const RideInfo({
    required this.id,
    required this.requestId,
    required this.name,
    required this.phone,
    required this.pickup,
    required this.drop,
    required this.date,
    required this.scheduledTime,
    this.scheduleType = 'Monthly Pick & Drop',
    this.pickupTime = '',
    this.dropoffTime = '',
    this.selectedDays = '',
    required this.fare,
    this.vehicleType = 'Sedan',
    this.acPreference = 'AC Required',
    this.notes = '',
    required this.status,
    this.assignedDriver = '',
    this.assignedDriverId = '',
  });

  /// Extracts raw fare from map using all standard and nested keys
  static dynamic extractRawFare(dynamic data) {
    if (data == null) return null;
    if (data is! Map) return data;

    final direct =
        data['fare'] ??
        data['fareFormatted'] ??
        data['rawFare'] ??
        data['newFare'] ??
        data['price'] ??
        data['estimatedFare'] ??
        data['totalFare'] ??
        data['amount'] ??
        data['totalAmount'] ??
        data['cost'] ??
        data['totalCost'] ??
        data['tripFare'] ??
        data['tripPrice'] ??
        data['baseFare'];

    if (direct != null &&
        direct != '' &&
        direct != 0 &&
        direct != '0' &&
        direct != 'Rs. 0') {
      return direct;
    }

    final nestedObjects = [
      data['ride'],
      data['data'],
      data['request'],
      data['pricing'],
      data['route'],
      data['details'],
      data['customSchedule'],
    ];

    for (final obj in nestedObjects) {
      if (obj is Map) {
        final nested =
            obj['fare'] ??
            obj['fareFormatted'] ??
            obj['rawFare'] ??
            obj['newFare'] ??
            obj['price'] ??
            obj['estimatedFare'] ??
            obj['totalFare'] ??
            obj['amount'] ??
            obj['totalAmount'] ??
            obj['cost'] ??
            obj['totalCost'] ??
            obj['tripFare'] ??
            obj['tripPrice'] ??
            obj['baseFare'];
        if (nested != null &&
            nested != '' &&
            nested != 0 &&
            nested != '0' &&
            nested != 'Rs. 0') {
          return nested;
        }
      }
    }

    return direct;
  }

  /// Dynamically formats fare (e.g., "Rs. 9,500") without synthetic random hashing,
  /// preserving exact DB value if present, or returning clean default "Rs. 9,500".
  static String formatFare(dynamic rawFare, {String? pickup, String? drop}) {
    if (rawFare != null) {
      String s = rawFare.toString().trim();
      if (s.isNotEmpty && s != '0' && s != 'Rs. 0') {
        final numStr = s.replaceAll(RegExp(r'[^0-9.]'), '');
        final number = double.tryParse(numStr);
        if (number != null && number > 0) {
          final formatter = NumberFormat('#,##0', 'en_US');
          final formattedNum = formatter.format(number.toInt());
          return 'Rs. $formattedNum';
        } else if (number == null && s.isNotEmpty) {
          return s.startsWith('Rs.') ? s : 'Rs. $s';
        }
      }
    }

    // Default fallback is Rs. 9,500
    return 'Rs. 9,500';
  }

  /// Returns standard baseline fare Rs. 9,500
  static String calculateEstimatedFare(String pickup, String drop) {
    return 'Rs. 9,500';
  }

  RideInfo copyWith({
    String? id,
    String? requestId,
    String? name,
    String? phone,
    String? pickup,
    String? drop,
    String? date,
    String? scheduledTime,
    String? scheduleType,
    String? pickupTime,
    String? dropoffTime,
    String? selectedDays,
    String? fare,
    String? vehicleType,
    String? acPreference,
    String? notes,
    String? status,
    String? assignedDriver,
    String? assignedDriverId,
  }) {
    return RideInfo(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      pickup: pickup ?? this.pickup,
      drop: drop ?? this.drop,
      date: date ?? this.date,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      scheduleType: scheduleType ?? this.scheduleType,
      pickupTime: pickupTime ?? this.pickupTime,
      dropoffTime: dropoffTime ?? this.dropoffTime,
      selectedDays: selectedDays ?? this.selectedDays,
      fare: fare ?? this.fare,
      vehicleType: vehicleType ?? this.vehicleType,
      acPreference: acPreference ?? this.acPreference,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      assignedDriver: assignedDriver ?? this.assignedDriver,
      assignedDriverId: assignedDriverId ?? this.assignedDriverId,
    );
  }

  factory RideInfo.fromJson(Map<String, dynamic> json) {
    final rawFare = extractRawFare(json);

    final rawStatus = (json['rawStatus'] ?? '').toString().trim().toUpperCase();
    final status = (json['status'] ?? '').toString().trim().toUpperCase();

    // Determine effective status: prioritize status, and only normalize assignment statuses
    String effectiveStatus = status;
    if (effectiveStatus.isEmpty) effectiveStatus = rawStatus;

    if (effectiveStatus == 'ASSIGNED' ||
        effectiveStatus == 'AWAITING DRIVER ACCEPTANCE' ||
        effectiveStatus == 'DISPATCHED') {
      effectiveStatus = 'ASSIGNED';
    } else if (effectiveStatus == 'ACCEPTED') {
      effectiveStatus = 'ACCEPTED';
    } else if (effectiveStatus == 'STARTED') {
      effectiveStatus = 'STARTED';
    } else if (effectiveStatus == 'PENDING DISPATCH' ||
        effectiveStatus == 'PENDING' ||
        effectiveStatus == 'VISIBLE') {
      effectiveStatus = 'PENDING DISPATCH';
    }

    String extractAddr(dynamic raw) {
      if (raw == null) return '';
      if (raw is String) return raw.trim();
      if (raw is Map) {
        final val =
            (raw['address'] ??
                    raw['name'] ??
                    raw['formattedAddress'] ??
                    raw['street'] ??
                    '')
                .toString()
                .trim();
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    final p1 = extractAddr(json['pickupLocation']);
    final p2 = extractAddr(json['pickup']);
    final p3 = extractAddr(json['from']);
    final pickup = p1.isNotEmpty ? p1 : (p2.isNotEmpty ? p2 : p3);

    final d1 = extractAddr(json['dropLocation']);
    final d2 = extractAddr(json['dropoffLocation']);
    final d3 = extractAddr(json['drop']);
    final d4 = extractAddr(json['to']);
    final drop = d1.isNotEmpty
        ? d1
        : (d2.isNotEmpty ? d2 : (d3.isNotEmpty ? d3 : d4));

    String custName = '';
    if (json['passengerName'] != null &&
        json['passengerName'].toString().trim().isNotEmpty) {
      custName = json['passengerName'].toString().trim();
    } else if (json['customerName'] != null &&
        json['customerName'].toString().trim().isNotEmpty) {
      custName = json['customerName'].toString().trim();
    } else if (json['passenger'] is Map && json['passenger']['name'] != null) {
      custName = json['passenger']['name'].toString().trim();
    } else if (json['customer'] is Map) {
      custName =
          (json['customer']['fullName'] ??
                  json['customer']['Name'] ??
                  json['customer']['name'] ??
                  '')
              .toString()
              .trim();
    } else if (json['customer'] is String &&
        !RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(json['customer'])) {
      custName = json['customer'].toString().trim();
    }
    if (custName.isEmpty || custName.toLowerCase() == 'unknown') {
      custName = 'Customer';
    }

    final custPhone =
        json['passengerPhone'] ??
        json['customerPhone'] ??
        json['phone'] ??
        json['PhoneNumber'] ??
        (json['passenger'] is Map
            ? (json['passenger']['phone'] ?? json['passenger']['phoneNumber'])
            : null) ??
        (json['customer'] is Map
            ? (json['customer']['PhoneNumber'] ?? json['customer']['phone'])
            : null) ??
        '';

    final date =
        json['startingFrom'] ??
        json['date'] ??
        (json['customSchedule'] is Map
            ? json['customSchedule']['startDate']
            : null) ??
        '';

    final schedType =
        (json['scheduleType'] ??
                (json['customSchedule'] != null
                    ? 'Custom Schedule'
                    : (json['rideType'] ?? 'Monthly Pick & Drop')))
            .toString();

    final pTime =
        (json['pickupTime'] ??
                json['timeToReach'] ??
                json['scheduleTime'] ??
                json['scheduledTime'] ??
                (json['customSchedule'] is Map
                    ? json['customSchedule']['fromTime']
                    : null) ??
                json['timeToLeave'] ??
                '')
            .toString();

    final dTime =
        (json['dropoffTime'] ??
                json['timeToLeave'] ??
                (json['customSchedule'] is Map
                    ? json['customSchedule']['toTime']
                    : null) ??
                '')
            .toString();

    String daysStr = '';
    if (json['customSchedule'] is Map &&
        json['customSchedule']['selectedDays'] != null) {
      final d = json['customSchedule']['selectedDays'];
      if (d is List) {
        daysStr = d.join(', ');
      } else {
        daysStr = d.toString();
      }
    } else if (json['selectedDays'] != null) {
      final d = json['selectedDays'];
      if (d is List) {
        daysStr = d.join(', ');
      } else {
        daysStr = d.toString();
      }
    }

    final vType =
        (json['vehicleType'] ??
                json['vehiclePreference'] ??
                json['vehicle'] ??
                'Sedan')
            .toString();
    final acPref =
        (json['acPreference'] ??
                (json['acRequired'] == false ? 'Non-AC' : 'AC Required'))
            .toString();
    final notes =
        (json['notes'] ??
                json['passengerNotes'] ??
                json['specialInstructions'] ??
                json['remarks'] ??
                '')
            .toString();

    final asgDriver =
        (json['assignedDriver'] ?? json['assignedDriverName'] ?? '').toString();
    final asgDriverId =
        (json['assignedDriverId'] ?? json['driverId'] ?? json['driver'] ?? '')
            .toString();

    return RideInfo(
      id:
          json['_id']?.toString() ??
          json['rideId']?.toString() ??
          json['id']?.toString() ??
          '',
      requestId: json['requestId']?.toString() ?? json['id']?.toString() ?? '',
      name: custName,
      phone: custPhone.toString(),
      pickup: pickup,
      drop: drop,
      date: date.toString(),
      scheduledTime: pTime.isNotEmpty
          ? pTime
          : (dTime.isNotEmpty ? dTime : 'ASAP'),
      scheduleType: schedType,
      pickupTime: pTime,
      dropoffTime: dTime,
      selectedDays: daysStr,
      fare: formatFare(rawFare, pickup: pickup, drop: drop),
      vehicleType: vType,
      acPreference: acPref,
      notes: notes,
      status: effectiveStatus.toUpperCase(),
      assignedDriver: asgDriver,
      assignedDriverId: asgDriverId,
    );
  }
}
