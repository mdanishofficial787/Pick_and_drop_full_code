import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../api_config.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ride_and_serve/widgets/driver/dashed_border.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/services.dart'; // For Clipboard
import '../../services/auth_service.dart';
import 'payment_status_screen.dart';

class PaymentDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;

  const PaymentDetailsScreen({super.key, required this.rideData});

  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen> {
  bool _isConfirmed = false;
  File? _paymentProof;
  XFile? _webPaymentProof;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        if (kIsWeb) {
          _webPaymentProof = image;
        } else {
          _paymentProof = File(image.path);
        }
      });
    }
  }

  bool _isSubmitting = false;

  Future<void> _submitPayment() async {
    if (!_isConfirmed || (_paymentProof == null && _webPaymentProof == null)) return;
    setState(() => _isSubmitting = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final rideId = widget.rideData['id'] ?? widget.rideData['requestId'] ?? 'RS-9982';
      final fare = widget.rideData['fare']?.toString() ?? widget.rideData['fareFormatted'] ?? '4500';

      var request = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/api/payments/upload'));
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      
      final user = await AuthService.getCurrentUser();
      if (user != null && user.id.isNotEmpty) {
        request.fields['customerId'] = user.id;
      }

      request.fields['rideId'] = rideId;
      request.fields['fare'] = fare;

      if (kIsWeb && _webPaymentProof != null) {
        var bytes = await _webPaymentProof!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('paymentProof', bytes, filename: _webPaymentProof!.name));
      } else if (!kIsWeb && _paymentProof != null) {
        request.files.add(await http.MultipartFile.fromPath('paymentProof', _paymentProof!.path));
      }

      var response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PaymentStatusScreen(
          rideId: rideId, fare: fare, imageFile: _paymentProof, webImageFile: _webPaymentProof
        )));
      } else {
        final respStr = await response.stream.bytesToString();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $respStr')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideData['id'] ?? widget.rideData['requestId'] ?? 'RS-9982';
    final fare = widget.rideData['fareFormatted'] ?? 'Rs. 4500';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1959F6), // Matches screenshot blue header
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Payment Details',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('PAYMENT SUMMARY'),
            _buildPaymentSummaryCard(rideId, fare),
            const SizedBox(height: 20),
            
            _buildSectionTitle('BANK ACCOUNT DETAILS'),
            _buildBankDetailsCard(),
            const SizedBox(height: 20),
            
            _buildSectionTitle('UPLOAD PAYMENT PROOF'),
            _buildUploadSection(),
            const SizedBox(height: 20),
            
            _buildSectionTitle('PAYMENT CONFIRMATION'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _isConfirmed,
                    onChanged: (val) {
                      setState(() {
                        _isConfirmed = val ?? false;
                      });
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    activeColor: const Color(0xFF1959F6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'I confirm that I have transferred the above amount to the selected bank account.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_isConfirmed && (_paymentProof != null || _webPaymentProof != null) && !_isSubmitting) ? _submitPayment : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1959F6),
                  disabledBackgroundColor: const Color(0xFF94A3B8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  'Submit Payment',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF94A3B8),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(String rideId, String fare) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ride ID: #$rideId',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'STANDARD RIDE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Premium Business Ride • Dec 14 • 12.4 km',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Amount',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              Text(
                fare,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Payable Amount',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1959F6),
                ),
              ),
              Text(
                fare,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1959F6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBankDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1959F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Faysal Bank',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Title',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Alishba Aamir',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCopyableRow('Account Number', '3413444000007236'),
        ],
      ),
    );
  }

  Widget _buildCopyableRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
            ),
          ],
        ),
        InkWell(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied to clipboard!'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: const Color(0xFF1959F6),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.copy, size: 12, color: Color(0xFF1959F6)),
                const SizedBox(width: 4),
                Text(
                  'Copy',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1959F6)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload Payment Screenshot',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickImage,
          child: DashedBorder(
            color: const Color(0xFFCBD5E1),
            strokeWidth: 1.5,
            dashLength: 6,
            dashGap: 4,
            borderRadius: 16,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _paymentProof != null || _webPaymentProof != null
                  ? Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'Image Uploaded Successfully',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to change',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.upload_file, color: Color(0xFF1959F6), size: 24),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Upload Screenshot',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1959F6)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'JPEG, PNG up to 5MB',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
