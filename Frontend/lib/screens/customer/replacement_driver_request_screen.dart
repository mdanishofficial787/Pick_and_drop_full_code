import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ride_and_serve/constants/api_constants.dart';
import 'package:ride_and_serve/constants/app_colors.dart';

class ReplacementDriverRequestScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const ReplacementDriverRequestScreen({
    super.key,
    required this.data,
  });

  @override
  State<ReplacementDriverRequestScreen> createState() => _ReplacementDriverRequestScreenState();
}

class _ReplacementDriverRequestScreenState extends State<ReplacementDriverRequestScreen> {
  String _vehicleArrangement = 'Separate';
  String _vehicleType = 'Sedan Executive';
  String _genderPreference = 'Male Only';
  String _acPreference = 'AC';
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final rideId = widget.data['rideId'] ?? widget.data['mongoId'] ?? widget.data['_id'] ?? widget.data['requestId'] ?? 'REQ-8031';

    setState(() {
      _isSubmitting = true;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.requestReplacement(rideId.toString())),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rideId': rideId,
          'vehicleArrangement': _vehicleArrangement,
          'vehicleType': _vehicleType,
          'genderPreference': _genderPreference,
          'acPreference': _acPreference,
          'additionalNotes': _notesController.text.trim(),
        }),
      );

      final result = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && result['success'] == true) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                SizedBox(width: 10),
                Text('Request Submitted', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'Your replacement driver request has been sent to our Admin Dispatch team. We will assign a new driver shortly.',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Back from Replacement screen
                  Navigator.pop(context); // Back to Dashboard
                },
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to submit request'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Network error: $err'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String affectedDate = widget.data['affectedDate'] ?? widget.data['startingFrom'] ?? 'May 21, 2026';
    final String affectedTime = widget.data['affectedTime'] ?? '08:00 AM - 10:00 AM';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          color: AppColors.primaryBlue,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 16,
            bottom: 12,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Replacement Driver Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Select your preferences for the replacement driver.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Affected Ride Details
            const Text(
              'Affected Ride Details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0052CC),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.primaryBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        affectedDate,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        affectedTime,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 1. Vehicle Arrangement
            const Text(
              '1. Vehicle Arrangement',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0052CC),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OptionPill(
                    label: 'Separate',
                    icon: Icons.radio_button_checked_rounded,
                    isSelected: _vehicleArrangement == 'Separate',
                    onTap: () => setState(() => _vehicleArrangement = 'Separate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionPill(
                    label: 'Combined',
                    icon: Icons.group_work_outlined,
                    isSelected: _vehicleArrangement == 'Combined',
                    onTap: () => setState(() => _vehicleArrangement = 'Combined'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 2. Vehicle Type
            const Text(
              '2. Vehicle Type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0052CC),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OptionPill(
                    label: 'Sedan Executive',
                    icon: Icons.radio_button_checked_rounded,
                    isSelected: _vehicleType == 'Sedan Executive',
                    onTap: () => setState(() => _vehicleType = 'Sedan Executive'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionPill(
                    label: 'Sedan',
                    icon: Icons.directions_car_rounded,
                    isSelected: _vehicleType == 'Sedan',
                    onTap: () => setState(() => _vehicleType = 'Sedan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 3. Gender Preference
            const Text(
              '3. Gender Preference',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0052CC),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OptionPill(
                    label: 'Male Only',
                    icon: Icons.radio_button_checked_rounded,
                    isSelected: _genderPreference == 'Male Only',
                    onTap: () => setState(() => _genderPreference = 'Male Only'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OptionPill(
                    label: 'Female Only',
                    icon: Icons.person_outline_rounded,
                    isSelected: _genderPreference == 'Female Only',
                    onTap: () => setState(() => _genderPreference = 'Female Only'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OptionPill(
                    label: 'Both',
                    icon: Icons.people_outline_rounded,
                    isSelected: _genderPreference == 'Both',
                    onTap: () => setState(() => _genderPreference = 'Both'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 4. AC Preference
            const Text(
              '4. AC Preference',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0052CC),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OptionPill(
                    label: 'AC',
                    icon: Icons.ac_unit_rounded,
                    isSelected: _acPreference == 'AC',
                    onTap: () => setState(() => _acPreference = 'AC'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionPill(
                    label: 'Non-AC',
                    icon: Icons.mode_fan_off_rounded,
                    isSelected: _acPreference == 'Non-AC',
                    onTap: () => setState(() => _acPreference = 'Non-AC'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 5. Additional Notes
            const Text(
              '5. Additional Notes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0052CC),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: 4,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                decoration: const InputDecoration(
                  hintText: 'Any special requests or instructions?',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                onPressed: _isSubmitting ? null : _submitRequest,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Send Request to Admin',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _OptionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : const Color(0xFFCBD5E1),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.primaryBlue,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
