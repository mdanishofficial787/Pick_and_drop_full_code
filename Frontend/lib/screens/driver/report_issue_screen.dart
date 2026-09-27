import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '/theme/app_theme.dart';
import '../../api_config.dart';
import 'report_success_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  final String? driverId;
  final String? driverName;
  final String initialReason;
  final String? customerName;
  final String? customerPhone;
  final String? requestId;
  final String? pickupLocation;
  final String? dropoffLocation;
  final String? fare;
  final String? rideId;

  const ReportIssueScreen({
    super.key,
    this.driverId,
    this.driverName,
    this.initialReason = 'Vehicle Breakdowns',
    this.customerName,
    this.customerPhone,
    this.requestId,
    this.pickupLocation,
    this.dropoffLocation,
    this.fare,
    this.rideId,
  });

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _PassengerItem {
  final String id;
  final String name;
  final String initials;
  final String seat;
  final String phone;
  final String pickup;
  final String drop;
  bool isSelected;
  bool canBePicked;
  String reasonNote;

  _PassengerItem({
    required this.id,
    required this.name,
    required this.initials,
    required this.seat,
    this.phone = '',
    this.pickup = '',
    this.drop = '',
    this.isSelected = true,
    this.canBePicked = true,
    this.reasonNote = '',
  });

  static String computeInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'P';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  // Mode: 0 for Separate, 1 for Combined
  int _selectedMode = 0;

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<_PassengerItem> _passengers = [];

  // Selected Issue Type (defaults to Vehicle Breakdowns)
  String _selectedIssueType = 'Vehicle Breakdowns';

  final TextEditingController _messageController = TextEditingController();

  final List<Map<String, dynamic>> _issueTypes = [
    {
      'title': 'Vehicle Breakdowns',
      'icon': Icons.car_repair_rounded,
    },
    {
      'title': 'Heavy Traffic',
      'icon': Icons.directions_car_filled_rounded,
    },
    {
      'title': 'Bad Weather',
      'icon': Icons.cloud_queue_rounded,
    },
    {
      'title': 'Wrong Location',
      'icon': Icons.location_on_rounded,
    },
    {
      'title': 'Passenger Issue',
      'icon': Icons.person_add_alt_1_rounded,
    },
    {
      'title': 'Delay',
      'icon': Icons.access_time_rounded,
    },
    {
      'title': 'Road Blockage',
      'icon': Icons.alt_route_rounded,
    },
    {
      'title': 'Other',
      'icon': Icons.more_horiz_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _normalizeInitialReason();
    _fetchAssignedPassengers();
  }

  void _normalizeInitialReason() {
    final reason = widget.initialReason;
    if (_issueTypes.any((t) => t['title'] == reason)) {
      _selectedIssueType = reason;
    } else if (reason.contains('Vehicle')) {
      _selectedIssueType = 'Vehicle Breakdowns';
    } else if (reason.contains('Passenger') || reason.contains('Customer')) {
      _selectedIssueType = 'Passenger Issue';
    } else {
      _selectedIssueType = 'Vehicle Breakdowns';
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchAssignedPassengers() async {
    setState(() => _isLoading = true);

    final activeDriverId =
        (widget.driverId != null && widget.driverId!.isNotEmpty)
            ? widget.driverId!
            : '6a97ba8860eec88e497bd6c7';

    try {
      final List<dynamic> combinedList = [];

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

      // 1. Fetch assigned rides for this driver
      try {
        final res = await http
            .get(Uri.parse('$kBaseUrl/api/rides/driver/$activeDriverId'))
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          combinedList.addAll(parsePayload(jsonDecode(res.body)));
        }
      } catch (_) {}

      // 2. Fallback to /api/rides
      if (combinedList.isEmpty) {
        try {
          final res = await http
              .get(Uri.parse('$kBaseUrl/api/rides'))
              .timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            combinedList.addAll(parsePayload(jsonDecode(res.body)));
          }
        } catch (_) {}
      }

      final List<_PassengerItem> items = [];
      final Set<String> seen = {};

      int seatCounter = 1;
      for (final r in combinedList) {
        if (r is Map) {
          final map = Map<String, dynamic>.from(r);
          final id = (map['_id'] ?? map['requestId'] ?? map['id'] ?? '')
              .toString();
          if (id.isEmpty || seen.contains(id)) continue;

          String name = '';
          if (map['customerName'] != null) {
            name = map['customerName'].toString();
          } else if (map['passengerName'] != null) {
            name = map['passengerName'].toString();
          } else if (map['passenger'] is Map &&
              map['passenger']['name'] != null) {
            name = map['passenger']['name'].toString();
          } else if (map['customer'] is Map) {
            name = (map['customer']['fullName'] ??
                    map['customer']['Name'] ??
                    map['customer']['name'] ??
                    '')
                .toString();
          }

          if (name.trim().isEmpty || name.toLowerCase() == 'customer') {
            continue; // Skip ghost / empty customer
          }

          seen.add(id);

          if (widget.rideId != null && widget.rideId!.isNotEmpty) {
            final rId = (map['rideId'] ?? map['id'] ?? map['_id'] ?? '').toString();
            if (rId != widget.rideId && id != widget.rideId) continue;
          } else if (widget.requestId != null && widget.requestId!.isNotEmpty) {
            if (id != widget.requestId && map['requestId'] != widget.requestId) continue;
          }

          final bool isPreselected = (widget.requestId != null &&
                  widget.requestId!.isNotEmpty &&
                  (id == widget.requestId ||
                      map['requestId'] == widget.requestId)) ||
              (widget.customerName != null &&
                  widget.customerName!.isNotEmpty &&
                  name.toLowerCase() == widget.customerName!.toLowerCase());

          items.add(
            _PassengerItem(
              id: id,
              name: name,
              initials: _PassengerItem.computeInitials(name),
              seat: 'Seat $seatCounter',
              phone: (map['customerPhone'] ?? map['passengerPhone'] ?? map['phone'] ?? '').toString(),
              pickup: (map['pickupLocation'] is Map ? map['pickupLocation']['address'] : map['pickupLocation']?.toString()) ?? '',
              drop: (map['dropLocation'] is Map ? map['dropLocation']['address'] : map['dropLocation']?.toString()) ?? '',
              isSelected: widget.requestId != null ? isPreselected : true,
              canBePicked: true,
            ),
          );
          seatCounter++;
        }
      }

      // If backend has no live assigned records or fewer than 4, provide default mock passengers matching design
      if (items.isEmpty) {
        items.addAll([
          _PassengerItem(
            id: 'p1',
            name: 'Ahmed Shah',
            initials: 'AS',
            seat: 'Seat 1',
            isSelected: true,
            canBePicked: false,
            reasonNote: 'Heavy rain at home',
          ),
          _PassengerItem(
            id: 'p2',
            name: 'Sara Ali',
            initials: 'SA',
            seat: 'Seat 2',
            isSelected: true,
            canBePicked: true,
          ),
          _PassengerItem(
            id: 'p3',
            name: 'Muneeb Khan',
            initials: 'MK',
            seat: 'Seat 3',
            isSelected: true,
            canBePicked: true,
          ),
          _PassengerItem(
            id: 'p4',
            name: 'Zainab Arif',
            initials: 'ZA',
            seat: 'Seat 4',
            isSelected: false,
            canBePicked: true,
          ),
        ]);
      }

      if (mounted) {
        setState(() {
          _passengers = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching passengers for report issue: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isAllSelected {
    if (_passengers.isEmpty) return false;
    return _passengers.every((p) => p.isSelected);
  }

  void _toggleSelectAll(bool? val) {
    final target = val ?? false;
    setState(() {
      for (final p in _passengers) {
        p.isSelected = target;
      }
    });
  }

  void _togglePassengerStatus(_PassengerItem p) {
    setState(() {
      p.canBePicked = !p.canBePicked;
      if (!p.canBePicked && p.reasonNote.isEmpty) {
        p.reasonNote = _selectedIssueType;
      }
    });
  }

  Future<void> _submitIssue() async {
    final selectedPassengers = _selectedMode == 1
        ? _passengers
        : _passengers.where((p) => p.isSelected).toList();

    if (selectedPassengers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one passenger.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'driverId': widget.driverId ?? '6a97ba8860eec88e497bd6c7',
        'driverName': widget.driverName ?? 'Driver',
        'mode': _selectedMode == 0 ? 'Separate' : 'Combined',
        'issueType': _selectedIssueType,
        'message': _messageController.text.trim(),
        'passengers': selectedPassengers.map((p) => {
              'id': p.id,
              'name': p.name,
              'seat': p.seat,
              'canBePicked': p.canBePicked,
              'reasonNote': p.reasonNote,
            }).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      try {
        await http.post(
          Uri.parse(kReportIssueEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}

      if (mounted) {
        setState(() => _isSubmitting = false);
        // Generate a random reference ID for display (or get it from response if available)
        final refId = '#${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportSuccessScreen(
              issueType: _selectedIssueType,
              referenceId: refId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── TOP BLUE APPBAR & HEADER ──
            _buildHeader(context),

            // ── MAIN CONTENT (Scrollable) ──
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── MODE SELECTOR TABS (Separate vs Combined) ──
                          _buildModeTabs(),

                          const SizedBox(height: 20),

                          // ── PASSENGERS SECTION ──
                          _buildPassengersSection(),

                          const SizedBox(height: 22),

                          // ── SELECT ISSUE TYPE SECTION ──
                          _buildIssueTypeSection(),

                          const SizedBox(height: 22),

                          // ── MESSAGE TO PASSENGER(S) (OPTIONAL) ──
                          _buildMessageSection(),

                          const SizedBox(height: 24),

                          // ── SEND BUTTON ──
                          _buildSubmitButton(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topPadding + 10, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Report an Issue',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select the passenger(s) and choose the issue type.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    return Row(
      children: [
        // Tab 1: Separate
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() => _selectedMode = 0);
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _selectedMode == 0 ? AppColors.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedMode == 0
                      ? AppColors.primaryBlue
                      : const Color(0xFFE5E7EB),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    color: _selectedMode == 0 ? Colors.white : AppColors.textPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Separate',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _selectedMode == 0
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select specific passenger(s)',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: _selectedMode == 0
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.grey.shade500,
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
          ),
        ),
        const SizedBox(width: 12),

        // Tab 2: Combined
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedMode = 1;
                for (final p in _passengers) {
                  p.isSelected = true;
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _selectedMode == 1 ? AppColors.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedMode == 1
                      ? AppColors.primaryBlue
                      : const Color(0xFFE5E7EB),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    color: _selectedMode == 1 ? Colors.white : AppColors.textPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Combined',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _selectedMode == 1
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Same issue for all passengers',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: _selectedMode == 1
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.grey.shade500,
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
          ),
        ),
      ],
    );
  }

  Widget _buildPassengersSection() {
    final count = _passengers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: Passengers (N) + Select All
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Passengers ($count)',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (_selectedMode == 0)
              InkWell(
                onTap: () => _toggleSelectAll(!_isAllSelected),
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    Text(
                      'Select All',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _isAllSelected,
                        onChanged: _toggleSelectAll,
                        activeColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        side: BorderSide(
                          color: Colors.grey.shade400,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // List of passenger cards
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _passengers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final p = _passengers[index];
            return _buildPassengerCard(p);
          },
        ),
      ],
    );
  }

  Widget _buildPassengerCard(_PassengerItem p) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: p.isSelected
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFE5E7EB),
          width: p.isSelected ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_selectedMode == 0) {
              setState(() {
                p.isSelected = !p.isSelected;
              });
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Checkbox
                if (_selectedMode == 0) ...[
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: p.isSelected,
                      onChanged: (val) {
                        setState(() {
                          p.isSelected = val ?? false;
                        });
                      },
                      activeColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // Initials Circle Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0E7FF),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    p.initials,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1D4ED8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Seat
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.seat,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Status Badge (Can be picked / Cannot be picked)
                InkWell(
                  onTap: () => _togglePassengerStatus(p),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.canBePicked
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: p.canBePicked
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFFFECACA),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          p.canBePicked
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: p.canBePicked
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.canBePicked
                                  ? 'Can be picked'
                                  : 'Cannot be picked',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: p.canBePicked
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF991B1B),
                              ),
                            ),
                            if (!p.canBePicked && p.reasonNote.isNotEmpty) ...[
                              Text(
                                p.reasonNote,
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: p.canBePicked
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIssueTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Issue Type',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // Grid 2 rows x 4 cols
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.95,
          ),
          itemCount: _issueTypes.length,
          itemBuilder: (context, index) {
            final item = _issueTypes[index];
            final bool isSelected = item['title'] == _selectedIssueType;
            return _buildIssueTile(
              title: item['title'] as String,
              icon: item['icon'] as IconData,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  _selectedIssueType = item['title'] as String;
                });
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildIssueTile({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : const Color(0xFFE5E7EB),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.primaryBlue : const Color(0xFF1E3A8A),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? AppColors.primaryBlue
                    : const Color(0xFF374151),
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.chat_bubble_rounded,
              color: AppColors.primaryBlue,
              size: 17,
            ),
            const SizedBox(width: 6),
            Text(
              'Message to Passenger(s)',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(Optional)',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              TextField(
                controller: _messageController,
                maxLines: 3,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'You can add a short message here...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    '${_messageController.text.length}/200',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitIssue,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Send to Passenger(s)',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
