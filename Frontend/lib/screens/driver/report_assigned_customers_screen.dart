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

class ReportAssignedCustomersScreen extends StatefulWidget {
  final String? driverId;
  final String driverName;

  const ReportAssignedCustomersScreen({
    super.key,
    this.driverId,
    this.driverName = 'Driver',
  });

  @override
  State<ReportAssignedCustomersScreen> createState() =>
      _ReportAssignedCustomersScreenState();
}

class _ReportAssignedCustomersScreenState
    extends State<ReportAssignedCustomersScreen> {
  List<_AssignedCustomerRide> _assignedRides = [];
  bool _isLoading = true;
  io.Socket? _socket;
  io.Socket? _backendSocket;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchAssignedRides();
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
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _fetchAssignedRides(silent: true);
      }
    });
  }

  void _initSocket() {
    final activeDriverId =
        (widget.driverId != null && widget.driverId!.isNotEmpty)
            ? widget.driverId!
            : '6a97ba8860eec88e497bd6c7';

    try {
      _socket = io.io(kDispatchBaseUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': false,
      });

      _socket?.onConnect((_) {
        _socket?.emit('join-driver', activeDriverId);
        _socket?.emit('join', activeDriverId);
      });

      const events = [
        'ride-assigned',
        'ride_assigned',
        'ride-dispatched',
        'ride_dispatched',
        'fare_updated',
      ];

      for (final event in events) {
        _socket?.on(event, (_) {
          if (mounted) _fetchAssignedRides(silent: true);
        });
      }

      _socket?.connect();

      if (kBaseUrl != kDispatchBaseUrl) {
        _backendSocket = io.io(kBaseUrl, <String, dynamic>{
          'transports': ['websocket', 'polling'],
          'autoConnect': false,
        });
        _backendSocket?.connect();
      }
    } catch (e) {
      debugPrint("Socket init error: $e");
    }
  }

  Future<void> _fetchAssignedRides({bool silent = false}) async {
    if (!silent && _assignedRides.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final List<dynamic> combinedRawList = [];

      List<dynamic> parsePayload(dynamic body) {
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
              : '6a97ba8860eec88e497bd6c7';

      // 1. Specific Driver: GET /api/rides/driver/{driverId}
      try {
        final response = await http
            .get(Uri.parse('$kBaseUrl/api/rides/driver/$activeDriverId'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          combinedRawList.addAll(parsePayload(body));
        }
      } catch (_) {}

      // 2. All rides: GET /api/rides
      if (combinedRawList.isEmpty) {
        try {
          final response = await http
              .get(Uri.parse('$kBaseUrl/api/rides'))
              .timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            combinedRawList.addAll(parsePayload(body));
          }
        } catch (_) {}
      }

      // 3. Fallback GET /api/requests
      if (combinedRawList.isEmpty) {
        try {
          final response = await http
              .get(Uri.parse('$kBaseUrl/api/requests'))
              .timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            combinedRawList.addAll(parsePayload(body));
          }
        } catch (_) {}
      }

      final List<_AssignedCustomerRide> parsedList = [];
      final Set<String> seenIds = {};
      final Set<String> seenNames = {};

      for (final item in combinedRawList) {
        if (item is Map) {
          try {
            final ride =
                _AssignedCustomerRide.fromJson(Map<String, dynamic>.from(item));
            final isGhost = (ride.pickup.isEmpty || ride.pickup == 'N/A') &&
                (ride.drop.isEmpty || ride.drop == 'N/A') &&
                (ride.name == 'Customer' || ride.name.isEmpty) &&
                ride.phone.isEmpty;
            
            final uniqueKey = '${ride.name.toLowerCase().trim()}_${ride.phone.trim()}';

            final key = ride.requestId.isNotEmpty ? ride.requestId : ride.id;
            if (!isGhost && key.isNotEmpty && !seenIds.contains(key) && !seenNames.contains(uniqueKey)) {
              seenIds.add(key);
              seenNames.add(uniqueKey);
              if (ride.id.isNotEmpty) seenIds.add(ride.id);
              if (ride.requestId.isNotEmpty) seenIds.add(ride.requestId);
              parsedList.add(ride);
            }
          } catch (e) {
            debugPrint("Ride parse error: $e");
          }
        }
      }

      if (mounted) {
        setState(() {
          _assignedRides = parsedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching assigned customers: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openReportIssueScreen(_AssignedCustomerRide ride) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportIssueScreen(
          driverId: widget.driverId,
          initialReason: 'Cannot Take Customer / Passenger Issue',
          customerName: ride.name,
          customerPhone: ride.phone,
          requestId: ride.requestId.isNotEmpty ? ride.requestId : ride.id,
          pickupLocation: ride.pickup,
          dropoffLocation: ride.drop,
          fare: ride.fare,
          rideId: ride.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Report an Issue',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 22),
            tooltip: 'Refresh Assigned Customers',
            onPressed: () => _fetchAssignedRides(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header Subtitle Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFBFDBFE), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_pin_circle_rounded,
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assigned Customers',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E3A8A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap hamburger (☰) on any card & click "Write your issue" to report.',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Assigned Customers List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _assignedRides.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _fetchAssignedRides,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            itemCount: _assignedRides.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final ride = _assignedRides[index];
                              return _buildCustomerCard(ride);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
              ),
              child: const Icon(
                Icons.person_off_outlined,
                size: 32,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Assigned Customers',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You currently do not have any assigned customer rides to report.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(_AssignedCustomerRide ride) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER: Customer Avatar, Name, Trip ID & HAMBURGER MENU ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Request ID
                Expanded(
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
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Assigned',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── HAMBURGER MENU BUTTON (☰) ──
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
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 1.2,
                        ),
                      ),
                      child: const Icon(
                        Icons.menu_rounded,
                        color: Color(0xFF1F2937),
                        size: 20,
                      ),
                    ),
                    tooltip: 'Options',
                    onSelected: (value) {
                      if (value == 'write_your_issue') {
                        _openReportIssueScreen(ride);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'write_your_issue',
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
            ),
          ),

          Divider(height: 1, color: Colors.grey.shade100),

          // ── ROUTE / LOCATIONS ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const SizedBox(height: 2),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 24,
                      color: Colors.grey.shade300,
                    ),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFDC2626), width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PICKUP',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        ride.pickup.isNotEmpty ? ride.pickup : 'Pickup Location',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'DROP OFF',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        ride.drop.isNotEmpty ? ride.drop : 'Dropoff Location',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.grey.shade100),

          // ── BOTTOM ROW: Fare ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Fare
                Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: Color(0xFF15803D),
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ride.fare,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
                if (ride.date.isNotEmpty)
                  Text(
                    ride.date,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedCustomerRide {
  final String id;
  final String requestId;
  final String name;
  final String phone;
  final String pickup;
  final String drop;
  final String date;
  final String scheduledTime;
  final String fare;
  final String status;

  _AssignedCustomerRide({
    required this.id,
    required this.requestId,
    required this.name,
    required this.phone,
    required this.pickup,
    required this.drop,
    required this.date,
    required this.scheduledTime,
    required this.fare,
    required this.status,
  });

  factory _AssignedCustomerRide.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['rawStatus'] ?? '').toString().trim().toUpperCase();
    final status = (json['status'] ?? '').toString().trim().toUpperCase();
    String effectiveStatus = status.isNotEmpty ? status : rawStatus;

    String extractAddr(dynamic raw) {
      if (raw == null) return '';
      if (raw is String) return raw.trim();
      if (raw is Map) {
        final val = (raw['address'] ?? raw['name'] ?? raw['formattedAddress'] ?? raw['street'] ?? '').toString().trim();
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
    final drop = d1.isNotEmpty ? d1 : (d2.isNotEmpty ? d2 : (d3.isNotEmpty ? d3 : d4));

    String custName = '';
    if (json['customerName'] != null && json['customerName'].toString().trim().isNotEmpty) {
      custName = json['customerName'].toString().trim();
    } else if (json['passengerName'] != null && json['passengerName'].toString().trim().isNotEmpty) {
      custName = json['passengerName'].toString().trim();
    } else if (json['passenger'] is Map && json['passenger']['name'] != null) {
      custName = json['passenger']['name'].toString().trim();
    } else if (json['customer'] is Map) {
      custName = (json['customer']['fullName'] ?? json['customer']['Name'] ?? json['customer']['name'] ?? '').toString().trim();
    } else if (json['customer'] is String && !RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(json['customer'])) {
      custName = json['customer'].toString().trim();
    }
    if (custName.isEmpty || custName.toLowerCase() == 'unknown') {
      custName = 'Customer';
    }

    final custPhone = json['customerPhone'] ??
        json['passengerPhone'] ??
        json['phone'] ??
        json['PhoneNumber'] ??
        (json['passenger'] is Map
            ? (json['passenger']['phone'] ?? json['passenger']['phoneNumber'])
            : null) ??
        (json['customer'] is Map
            ? (json['customer']['PhoneNumber'] ?? json['customer']['phone'])
            : null) ??
        '';

    final date = json['startingFrom'] ??
        json['date'] ??
        (json['customSchedule'] is Map
            ? json['customSchedule']['startDate']
            : null) ??
        'Today';

    final scheduledTime = json['scheduledTime'] ??
        json['timeToLeave'] ??
        json['scheduleTime'] ??
        (json['customSchedule'] is Map
            ? json['customSchedule']['fromTime']
            : null) ??
        'ASAP';

    // Fare formatting
    dynamic rawFare = json['fare'] ??
        json['fareEstimate'] ??
        json['estimatedFare'] ??
        json['totalFare'] ??
        json['price'] ??
        json['amount'] ??
        json['fareAmount'] ??
        json['cost'];

    String fareStr = 'Rs. 9,500';
    if (rawFare != null) {
      String s = rawFare.toString().trim();
      if (s.isNotEmpty && s != '0' && s != 'Rs. 0') {
        final numStr = s.replaceAll(RegExp(r'[^0-9.]'), '');
        final number = double.tryParse(numStr);
        if (number != null && number > 0) {
          final formatter = NumberFormat('#,##0', 'en_US');
          fareStr = 'Rs. ${formatter.format(number.toInt())}';
        } else if (s.isNotEmpty) {
          fareStr = s.startsWith('Rs.') ? s : 'Rs. $s';
        }
      }
    }

    return _AssignedCustomerRide(
      id: json['_id']?.toString() ??
          json['rideId']?.toString() ??
          json['id']?.toString() ??
          '',
      requestId: json['requestId']?.toString() ??
          json['id']?.toString() ??
          'REQ-${(json['_id']?.toString() ?? '').length >= 6 ? (json['_id']?.toString() ?? '').substring((json['_id']?.toString() ?? '').length - 6) : 'NEW'}',
      name: custName.toString(),
      phone: custPhone.toString(),
      pickup: pickup,
      drop: drop,
      date: date.toString(),
      scheduledTime: scheduledTime.toString(),
      fare: fareStr,
      status: effectiveStatus.isNotEmpty ? effectiveStatus : 'ASSIGNED',
    );
  }
}
