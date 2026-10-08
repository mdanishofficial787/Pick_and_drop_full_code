import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ride_management_screen.dart'; // To access RideInfo
import 'dart:convert';
import 'package:http/http.dart' as http;
import '/api_config.dart';

class RideDetailsScreen extends StatefulWidget {
  final RideInfo ride;
  final String tabType;
  final String driverId;

  const RideDetailsScreen({
    super.key,
    required this.ride,
    required this.tabType,
    required this.driverId,
  });

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  bool _isLoading = false;

  Future<void> _handleAction(String action) async {
    setState(() => _isLoading = true);
    try {
      final endpoint = '$kBaseUrl/api/rides/status/${widget.ride.id}';
      final response = await http.put(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': action,
          'driverId': widget.driverId,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true); // true indicates success/refresh needed
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: ')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    switch (widget.ride.status.toUpperCase()) {
      case 'ASSIGNED':
        statusColor = const Color(0xFFD97706);
        statusLabel = 'New Request';
        break;
      case 'ACCEPTED':
        statusColor = const Color(0xFF1959F6);
        statusLabel = 'Accepted';
        break;
      case 'IN_TRANSIT':
        statusColor = const Color(0xFF7E22CE);
        statusLabel = 'In Transit';
        break;
      case 'COMPLETED':
        statusColor = const Color(0xFF16A34A);
        statusLabel = 'Completed';
        break;
      case 'CANCELLED':
        statusColor = const Color(0xFFDC2626);
        statusLabel = 'Cancelled';
        break;
      case 'NO_DRIVER_FOUND':
        statusColor = const Color(0xFF9CA3AF);
        statusLabel = 'No Driver Found';
        break;
      case 'APPROVED':
        statusColor = const Color(0xFF16A34A);
        statusLabel = 'Approved';
        break;
      default:
        statusColor = const Color(0xFF6B7280);
        statusLabel = widget.ride.status;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ride Details',
          style: GoogleFonts.inter(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_outline,
                          color: Color(0xFF6B7280), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.ride.name,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Text(
                      widget.ride.phone,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Monthly Pass Badge
              if (widget.ride.scheduleType.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.ride.scheduleType.toUpperCase() == 'HIRE DRIVER'
                            ? Icons.person_outline
                            : (widget.ride.scheduleType.toUpperCase() == 'TRAVEL & TOURISM'
                                ? Icons.luggage
                                : (widget.ride.scheduleType.toUpperCase() == 'SCHEDULE RIDE'
                                    ? Icons.access_time_filled
                                    : Icons.star)),
                        color: const Color(0xFF1D4ED8),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.ride.scheduleType.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Route Information Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Route Information',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Timeline and locations
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeline
                        Column(
                          children: [
                            const SizedBox(height: 20),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF1959F6), width: 3),
                              ),
                            ),
                            Container(
                              width: 2,
                              height: 48,
                              color: Colors.grey.shade300, // Dashed line ideally, but simple line for now
                            ),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFDC2626), width: 3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Location Boxes
                        Expanded(
                          child: Column(
                            children: [
                              _buildLocationBox('Pickup Point', widget.ride.pickup),
                              const SizedBox(height: 12),
                              _buildLocationBox('Drop Point', widget.ride.drop),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Times
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimeBox('Pickup Time', widget.ride.pickupTime.isNotEmpty ? widget.ride.pickupTime : widget.ride.scheduledTime.isNotEmpty ? widget.ride.scheduledTime : 'ASAP'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTimeBox('Est. Drop Time', widget.ride.dropoffTime.isNotEmpty ? widget.ride.dropoffTime : 'TBD'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Status Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildLocationBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : 'N/A',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time, size: 12, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.tabType == 'requests') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _handleAction('CANCELLED'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFDC2626)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Reject',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _handleAction('ACCEPTED'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1959F6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Text(
                'Accept',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (widget.tabType == 'assigned') {
      final status = widget.ride.status.toUpperCase();
      if (status == 'ACCEPTED') {
        return _buildFullWidthButton('Start Trip', const Color(0xFF1959F6), () => _handleAction('IN_TRANSIT'));
      } else if (status == 'IN_TRANSIT') {
        return _buildFullWidthButton('Complete Trip', const Color(0xFF16A34A), () => _handleAction('COMPLETED'));
      }
    }
    
    // Default / Completed / Cancelled state
    return _buildFullWidthButton('Back to Ride Management', const Color(0xFF1959F6), () => Navigator.pop(context));
  }

  Widget _buildFullWidthButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

