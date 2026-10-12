import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:ride_and_serve/constants/api_constants.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/payment_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerPaymentHistoryScreen extends StatefulWidget {
  final CustomerUser? user;

  const CustomerPaymentHistoryScreen({super.key, this.user});

  @override
  State<CustomerPaymentHistoryScreen> createState() => _CustomerPaymentHistoryScreenState();
}

class _CustomerPaymentHistoryScreenState extends State<CustomerPaymentHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _rides = [];

  static const Color _primaryBlue = Color(0xFF1959F6);
  static const Color _screenBg = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchHistoryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistoryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final customerId = widget.user?.id ?? prefs.getString('customerId') ?? '';
      final phone = widget.user?.phoneNumber ?? prefs.getString('phoneNumber') ?? '';
      final email = widget.user?.email ?? prefs.getString('email') ?? '';

      // 1. Fetch Payments History
      final paymentUrl = Uri.parse(
        '${ApiConstants.customerPaymentHistory}?customerId=$customerId&phone=$phone',
      );
      final paymentHeaders = <String, String>{
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final paymentResponse = await http
          .get(paymentUrl, headers: paymentHeaders)
          .timeout(const Duration(seconds: 8));

      List<Map<String, dynamic>> fetchedPayments = [];
      if (paymentResponse.statusCode == 200) {
        final body = json.decode(paymentResponse.body);
        if (body['data'] is List) {
          fetchedPayments = List<Map<String, dynamic>>.from(
            body['data'].map((item) => Map<String, dynamic>.from(item)),
          );
        }
      }

      // 2. Fetch Customer Rides History
      final rideUrl = Uri.parse(
        '${ApiConstants.getCustomerRides}?customerId=$customerId&phone=$phone&email=$email',
      );
      final rideResponse = await http
          .get(rideUrl, headers: paymentHeaders)
          .timeout(const Duration(seconds: 8));

      List<Map<String, dynamic>> fetchedRides = [];
      if (rideResponse.statusCode == 200) {
        final body = json.decode(rideResponse.body);
        final list = body['rides'] ?? body['data'] ?? [];
        if (list is List) {
          fetchedRides = List<Map<String, dynamic>>.from(
            list.map((item) => Map<String, dynamic>.from(item)),
          );
        }
      }

      if (mounted) {
        setState(() {
          _payments = fetchedPayments;
          _rides = fetchedRides;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load data. Please check connection.';
          _isLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    final s = status.toUpperCase();
    if (s.contains('VERIFIED') || s.contains('COMPLETED') || s.contains('ACCEPTED')) {
      return const Color(0xFF10B981); // Green
    }
    if (s.contains('REJECT') || s.contains('CANCEL')) {
      return const Color(0xFFEF4444); // Red
    }
    return const Color(0xFFF59E0B); // Amber / Pending
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateVal.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Payment & Ride History',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _fetchHistoryData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(
              icon: const Icon(Icons.receipt_long_rounded, size: 20),
              text: 'Payments (${_payments.length})',
            ),
            Tab(
              icon: const Icon(Icons.directions_car_rounded, size: 20),
              text: 'Rides (${_rides.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryBlue))
          : _errorMessage != null
              ? _buildErrorView()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPaymentsTab(),
                    _buildRidesTab(),
                  ],
                ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _fetchHistoryData,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              label: const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: PAYMENTS LIST ---
  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.payments_outlined,
        title: 'No Payments Yet',
        subtitle: 'When you submit ride payments, their status and verification details will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchHistoryData,
      color: _primaryBlue,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final payment = _payments[index];
          final String status = payment['status'] ?? 'PENDING VERIFICATION';
          final Color statusColor = _getStatusColor(status);
          final String fare = payment['fare']?.toString() ?? 'Rs. 0';
          final String rideId = payment['rideId'] ?? 'N/A';
          final String remarks = payment['adminRemarks']?.toString().trim() ?? '';
          final String proofUrl = payment['paymentProofUrl']?.toString() ?? '';
          final String date = _formatDate(payment['createdAt']);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Ride ID + Fare
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.tag_rounded, color: _primaryBlue, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ride ID',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                              ),
                              Text(
                                rideId,
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        fare,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),

                  // Status Badge & Date
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: statusColor, size: 8),
                            const SizedBox(width: 6),
                            Text(
                              status,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (date.isNotEmpty)
                        Text(
                          date,
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                        ),
                    ],
                  ),

                  // Remarks (if any)
                  if (remarks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Admin Remarks: $remarks',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF991B1B), fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Payment Proof thumbnail preview (if available)
                  if (proofUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _showProofDialog(proofUrl, rideId),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.image_outlined, size: 16, color: Color(0xFF475569)),
                            const SizedBox(width: 6),
                            Text(
                              'View Receipt / Proof',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- TAB 2: RIDES LIST ---
  Widget _buildRidesTab() {
    if (_rides.isEmpty) {
      return _buildEmptyState(
        icon: Icons.directions_car_outlined,
        title: 'No Rides Found',
        subtitle: 'You have not booked any rides yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchHistoryData,
      color: _primaryBlue,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rides.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ride = _rides[index];
          final String requestId = ride['requestId'] ?? ride['id'] ?? 'REQ-N/A';
          final String status = ride['status'] ?? 'Pending';
          final Color statusColor = _getStatusColor(status);
          final String fare = ride['fareFormatted'] ?? (ride['fare'] != null ? 'Rs. ${ride['fare']}' : 'N/A');
          final String pickup = ride['pickupLocation'] ?? ride['pickup'] ?? 'Pickup location not specified';
          final String dropoff = ride['dropoffLocation'] ?? ride['destination'] ?? 'Destination not specified';
          final String driverName = ride['assignedDriverName'] ?? ride['assignedDriver'] ?? '';
          final String driverPhone = ride['assignedDriverPhone'] ?? '';
          final String date = _formatDate(ride['createdAt']);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Request ID & Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        requestId,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),

                  // Route: Pickup & Destination
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.trip_origin_rounded, color: Color(0xFF10B981), size: 16),
                          Container(width: 1.5, height: 24, color: const Color(0xFFCBD5E1)),
                          const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 16),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pickup,
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              dropoff,
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),

                  // Bottom Info Row: Fare & Driver
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Agreed Fare', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                          Text(
                            fare,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: _primaryBlue),
                          ),
                        ],
                      ),
                      if (driverName.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Driver', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                            Text(
                              driverName,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // Action Button: If completed or needs payment
                  if (status == 'Fare Accepted' || status == 'Completed' || status == 'ACCEPTED') ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryBlue,
                          side: const BorderSide(color: _primaryBlue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PaymentDetailsScreen(rideData: ride),
                            ),
                          ).then((_) => _fetchHistoryData());
                        },
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: const Text('Submit / View Payment Proof', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF94A3B8), size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  void _showProofDialog(String imageUrl, String rideId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text('Receipt - $rideId', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16)),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF0F172A)),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(),
                      ),
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(30.0),
                  child: Text('Unable to load image proof.'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
