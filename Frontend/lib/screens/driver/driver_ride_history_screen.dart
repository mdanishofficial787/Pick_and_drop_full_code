import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:ride_and_serve/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'report_issue_screen.dart';

class DriverRideHistoryScreen extends StatefulWidget {
  final String driverId;
  final String? driverName;

  const DriverRideHistoryScreen({
    super.key,
    required this.driverId,
    this.driverName,
  });

  @override
  State<DriverRideHistoryScreen> createState() => _DriverRideHistoryScreenState();
}

class _DriverRideHistoryScreenState extends State<DriverRideHistoryScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedTimeframe = 'all'; // 'today', 'week', 'month', 'all'
  String _selectedStatus = 'all'; // 'all', 'completed', 'cancelled'
  String _searchQuery = '';

  List<Map<String, dynamic>> _rides = [];
  Map<String, dynamic> _summary = {
    'totalEarnings': 0,
    'earningsFormatted': 'Rs. 0',
    'completedCount': 0,
    'cancelledCount': 0,
    'totalRides': 0,
  };

  static const Color _primaryBlue = Color(0xFF1959F6);
  static const Color _screenBg = Color(0xFFF8FAFC);
  static const Color _textDark = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String resolvedDriverId = widget.driverId.trim();
      if (resolvedDriverId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        resolvedDriverId = prefs.getString('driverId') ??
            prefs.getString('driver_id') ??
            prefs.getString('id') ??
            '';
      }

      final url = Uri.parse(
        ApiConstants.getDriverRideHistory(
          resolvedDriverId,
          timeframe: _selectedTimeframe,
          status: _selectedStatus,
        ),
      );

      final response = await http.get(url).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final List<dynamic> rawRides = body['rides'] ?? body['data'] ?? [];
          final summaryData = body['summary'] as Map<String, dynamic>?;

          setState(() {
            _rides = rawRides.map((e) => Map<String, dynamic>.from(e)).toList();
            if (summaryData != null) {
              _summary = summaryData;
            } else {
              _recalculateLocalSummary();
            }
            _isLoading = false;
          });
          return;
        }
      }

      // Fallback: If dedicated history endpoint had issue, fetch from standard driver rides endpoint
      final fallbackUrl = Uri.parse(
        '${ApiConstants.getAllRides}?driverId=$resolvedDriverId',
      );
      final fallbackRes = await http.get(fallbackUrl).timeout(const Duration(seconds: 10));

      if (fallbackRes.statusCode == 200) {
        final fallbackBody = jsonDecode(fallbackRes.body);
        List<dynamic> list = [];
        if (fallbackBody is Map && fallbackBody['rides'] is List) {
          list = fallbackBody['rides'] as List;
        } else if (fallbackBody is List) {
          list = fallbackBody;
        }

        setState(() {
          _rides = list.map((e) => Map<String, dynamic>.from(e)).toList();
          _recalculateLocalSummary();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to load ride history. Please check your connection.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading history: ${e.toString()}';
        });
      }
    }
  }

  void _recalculateLocalSummary() {
    int total = 0;
    int completed = 0;
    int cancelled = 0;

    for (var r in _rides) {
      final st = (r['status'] ?? '').toString().toUpperCase();
      final fareVal = num.tryParse(r['fare']?.toString() ?? '0') ?? 0;
      if (st == 'COMPLETED' || st == 'PAID' || st == 'FINISHED') {
        total += fareVal.toInt();
        completed++;
      } else if (st.contains('CANCEL') || st == 'REJECTED') {
        cancelled++;
      }
    }

    _summary = {
      'totalEarnings': total,
      'earningsFormatted': 'Rs. ${total.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
      'completedCount': completed,
      'cancelledCount': cancelled,
      'totalRides': _rides.length,
    };
  }

  List<Map<String, dynamic>> get _filteredRides {
    return _rides.where((ride) {
      final st = (ride['status'] ?? '').toString().toUpperCase();
      if (_selectedStatus == 'completed') {
        if (st != 'COMPLETED' && st != 'PAID') return false;
      } else if (_selectedStatus == 'cancelled') {
        if (!st.contains('CANCEL') && st != 'REJECTED') return false;
      }

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = (ride['passengerName'] ?? '').toString().toLowerCase();
        final reqId = (ride['requestId'] ?? ride['id'] ?? '').toString().toLowerCase();
        final pickup = (ride['pickupLocation'] ?? ride['pickup'] ?? '').toString().toLowerCase();
        final drop = (ride['dropoffLocation'] ?? ride['drop'] ?? '').toString().toLowerCase();

        return name.contains(q) || reqId.contains(q) || pickup.contains(q) || drop.contains(q);
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRides;

    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Ride History',
          style: GoogleFonts.inter(
            color: _textDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _primaryBlue),
            tooltip: 'Refresh',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _primaryBlue,
        onRefresh: _fetchHistory,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Timeframe Filter Pills
            SliverToBoxAdapter(
              child: _buildTimeframeFilters(),
            ),

            // 2. Earnings & Performance Summary Card
            SliverToBoxAdapter(
              child: _buildEarningsSummaryCard(),
            ),

            // 3. Status Filters (All, Completed, Cancelled) & Search
            SliverToBoxAdapter(
              child: _buildStatusAndSearchControls(),
            ),

            // 4. Trips Header & Count
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Trip Records (${filtered.length})',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                    if (_selectedStatus != 'all' || _selectedTimeframe != 'all')
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedStatus = 'all';
                            _selectedTimeframe = 'all';
                            _searchQuery = '';
                            _searchController.clear();
                          });
                          _fetchHistory();
                        },
                        child: Text(
                          'Reset Filters',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _primaryBlue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 5. Ride List or Empty State
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _primaryBlue,
                  ),
                ),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: _buildErrorState(),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _buildRideHistoryCard(filtered[index]);
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Timeframe selector (Today, This Week, This Month, All Time)
  Widget _buildTimeframeFilters() {
    final timeframes = [
      {'label': 'All Time', 'key': 'all'},
      {'label': 'Today', 'key': 'today'},
      {'label': 'This Week', 'key': 'week'},
      {'label': 'This Month', 'key': 'month'},
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: timeframes.map((tf) {
            final isSelected = _selectedTimeframe == tf['key'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(tf['label']!),
                labelStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : _textMuted,
                ),
                selected: isSelected,
                selectedColor: _primaryBlue,
                backgroundColor: const Color(0xFFF1F5F9),
                elevation: 0,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedTimeframe = tf['key']!;
                    });
                    _fetchHistory();
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Earnings & Performance Metrics Banner
  Widget _buildEarningsSummaryCard() {
    final earningsText = _summary['earningsFormatted'] ??
        'Rs. ${(_summary['totalEarnings'] ?? 0).toString()}';
    final completedCount = _summary['completedCount'] ?? 0;
    final cancelledCount = _summary['cancelledCount'] ?? 0;
    final totalRides = _summary['totalRides'] ?? _rides.length;

    return Container(
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF34D399),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Driver Revenue',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Verified',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            earningsText,
            style: GoogleFonts.inter(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155), thickness: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem(
                icon: Icons.check_circle_rounded,
                iconColor: const Color(0xFF34D399),
                title: 'Completed',
                value: '$completedCount',
              ),
              Container(width: 1, height: 32, color: const Color(0xFF334155)),
              _buildMetricItem(
                icon: Icons.cancel_rounded,
                iconColor: const Color(0xFFF87171),
                title: 'Cancelled',
                value: '$cancelledCount',
              ),
              Container(width: 1, height: 32, color: const Color(0xFF334155)),
              _buildMetricItem(
                icon: Icons.directions_car_rounded,
                iconColor: const Color(0xFF60A5FA),
                title: 'Total Rides',
                value: '$totalRides',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 5),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // Status Filter Tabs + Instant Search Field
  Widget _buildStatusAndSearchControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          // Search Field
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: GoogleFonts.inter(fontSize: 14, color: _textDark),
              decoration: InputDecoration(
                hintText: 'Search by passenger, route, or ID...',
                hintStyle: GoogleFonts.inter(color: _textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: _textMuted, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: _textMuted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Status Filter Tabs
          Row(
            children: [
              _buildStatusPill(label: 'All Trips', key: 'all'),
              const SizedBox(width: 8),
              _buildStatusPill(label: 'Completed', key: 'completed', icon: Icons.check_circle_outline),
              const SizedBox(width: 8),
              _buildStatusPill(label: 'Cancelled', key: 'cancelled', icon: Icons.highlight_off_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({
    required String label,
    required String key,
    IconData? icon,
  }) {
    final isSelected = _selectedStatus == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedStatus = key;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _primaryBlue : const Color(0xFFE2E8F0),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.white : _textMuted,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : _textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Ride Item Card
  Widget _buildRideHistoryCard(Map<String, dynamic> ride) {
    final requestId = (ride['requestId'] ?? ride['id'] ?? 'TRIP').toString();
    final passengerName = (ride['passengerName'] ?? 'Customer').toString();
    final pickup = (ride['pickupLocation'] ?? ride['pickup'] ?? 'Pickup Point').toString();
    final dropoff = (ride['dropoffLocation'] ?? ride['drop'] ?? 'Destination').toString();
    final fareFormatted = (ride['fareFormatted'] ?? 'Rs. ${ride['fare'] ?? 0}').toString();
    final status = (ride['status'] ?? 'COMPLETED').toString().toUpperCase();
    final scheduleType = (ride['scheduleType'] ?? ride['rideType'] ?? 'Pick & Drop').toString();
    final pickupTime = (ride['timeToReach'] ?? ride['scheduledTime'] ?? ride['pickupTime'] ?? '').toString();
    final startingFrom = (ride['startingFrom'] ?? ride['date'] ?? '').toString();

    final isCompleted = status == 'COMPLETED' || status == 'PAID' || status == 'FINISHED';
    final isCancelled = status.contains('CANCEL') || status == 'REJECTED';

    final Color statusBg = isCompleted
        ? const Color(0xFFDCFCE7)
        : (isCancelled ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7));
    final Color statusTextColor = isCompleted
        ? const Color(0xFF15803D)
        : (isCancelled ? const Color(0xFFB91C1C) : const Color(0xFFB45309));
    final String statusDisplay = isCompleted
        ? 'Completed'
        : (isCancelled ? 'Cancelled' : status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showTripDetailsSheet(ride),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: ID + Service type + Fare
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            requestId,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          scheduleType,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      fareFormatted,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isCompleted ? const Color(0xFF15803D) : _textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Route section
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.radio_button_checked, size: 14, color: Color(0xFF10B981)),
                        Container(
                          width: 1.5,
                          height: 26,
                          color: const Color(0xFFCBD5E1),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                        ),
                        const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFEF4444)),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pickup,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            dropoff,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),

                // Bottom row: Passenger + Time + Status badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 15, color: _textMuted),
                        const SizedBox(width: 5),
                        Text(
                          passengerName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _textDark,
                          ),
                        ),
                        if (pickupTime.isNotEmpty || startingFrom.isNotEmpty) ...[
                          Text(
                            ' • ${pickupTime.isNotEmpty ? pickupTime : startingFrom}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusDisplay,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Detailed Modal Sheet when clicking a trip
  void _showTripDetailsSheet(Map<String, dynamic> ride) {
    final requestId = (ride['requestId'] ?? ride['id'] ?? 'TRIP').toString();
    final passengerName = (ride['passengerName'] ?? 'Customer').toString();
    final passengerPhone = (ride['passengerPhone'] ?? '').toString();
    final pickup = (ride['pickupLocation'] ?? ride['pickup'] ?? 'Pickup Point').toString();
    final dropoff = (ride['dropoffLocation'] ?? ride['drop'] ?? 'Destination').toString();
    final fareFormatted = (ride['fareFormatted'] ?? 'Rs. ${ride['fare'] ?? 0}').toString();
    final status = (ride['status'] ?? 'COMPLETED').toString().toUpperCase();
    final vehicleType = (ride['vehicleType'] ?? 'Sedan').toString();
    final acPreference = (ride['acPreference'] ?? 'AC').toString();
    final timeToReach = (ride['timeToReach'] ?? ride['scheduledTime'] ?? '08:30 AM').toString();
    final timeToLeave = (ride['timeToLeave'] ?? '05:00 PM').toString();
    final startingFrom = (ride['startingFrom'] ?? ride['date'] ?? 'Today').toString();
    final scheduleType = (ride['scheduleType'] ?? 'Monthly Commute').toString();

    final isCompleted = status == 'COMPLETED' || status == 'PAID' || status == 'FINISHED';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Sheet Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trip Breakdown',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                          ),
                        ),
                        Text(
                          requestId,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _primaryBlue,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      fareFormatted,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isCompleted ? const Color(0xFF15803D) : _textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 16),

                // Route Info
                Text(
                  'Route Information',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSheetRow(
                  icon: Icons.trip_origin_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Pickup Location',
                  subtitle: pickup,
                ),
                const SizedBox(height: 12),
                _buildSheetRow(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFFEF4444),
                  title: 'Drop-off Location',
                  subtitle: dropoff,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 16),

                // Schedule & Passenger info
                Text(
                  'Passenger & Schedule',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSheetRow(
                  icon: Icons.person_rounded,
                  iconColor: _primaryBlue,
                  title: passengerName,
                  subtitle: passengerPhone.isNotEmpty ? passengerPhone : 'Contact on file',
                ),
                const SizedBox(height: 10),
                _buildSheetRow(
                  icon: Icons.schedule_rounded,
                  iconColor: Colors.orange,
                  title: 'Timings ($scheduleType)',
                  subtitle: 'Pickup: $timeToReach • Return: $timeToLeave\nStarting: $startingFrom',
                ),
                const SizedBox(height: 10),
                _buildSheetRow(
                  icon: Icons.directions_car_filled_rounded,
                  iconColor: Colors.indigo,
                  title: 'Vehicle & Comfort',
                  subtitle: '$vehicleType • $acPreference',
                ),
                const SizedBox(height: 20),

                // Report an issue button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(
                      'Report Issue for this Trip',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReportIssueScreen(
                            driverId: widget.driverId,
                            driverName: widget.driverName,
                            requestId: requestId,
                            customerName: passengerName,
                            customerPhone: passengerPhone,
                            pickupLocation: pickup,
                            dropoffLocation: dropoff,
                            fare: fareFormatted,
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
      },
    );
  }

  Widget _buildSheetRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_toggle_off_rounded,
                size: 40,
                color: _primaryBlue,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No Trip Records Found',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No rides matched "$_searchQuery". Try a different search.'
                  : 'You have no past ride records under the selected filters.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: _textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Refresh History',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: _fetchHistory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              'Connection Issue',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'Unable to reach the server.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: _textMuted),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _fetchHistory,
              child: const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
