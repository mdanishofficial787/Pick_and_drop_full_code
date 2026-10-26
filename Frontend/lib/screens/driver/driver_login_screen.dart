import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'driver_dashboard_screen.dart';
import '../../services/driver_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/screens/driver/forgot_password_screen.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Basic field validation first.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await DriverApiService.loginDriver(
        countryCode: '+92',
        phoneNumber: _phoneController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Extract the driver data from the response.
      final driverData =
          response['driver'] ??
          response['data'] ??
          response['user'] ??
          response;

      // Print the raw data to the terminal so we can debug exactly what the backend sends
      debugPrint("===== BACKEND LOGIN RESPONSE =====");
      debugPrint(driverData.toString());
      debugPrint("==================================");

      // Checking multiple common patterns for approval status (case-insensitive)
      final String statusStr =
          driverData['status']?.toString().toLowerCase() ?? '';
      final String verificationStr =
          driverData['verificationStatus']?.toString().toLowerCase() ?? '';
      final String isApprovedStr =
          driverData['isApproved']?.toString().toLowerCase() ?? '';
      final String adminStr =
          driverData['adminApproval']?.toString().toLowerCase() ?? '';

      final bool isApproved =
          driverData['isApproved'] == true ||
          driverData['adminApproval'] == true ||
          isApprovedStr == 'true' ||
          isApprovedStr == '1' ||
          statusStr == 'approved' ||
          statusStr == 'active' ||
          verificationStr == 'approved' ||
          verificationStr == 'verified' || // <-- Added this!
          adminStr == 'true' ||
          adminStr == 'approved';

      if (!isApproved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your account is still pending admin approval.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      }

      // Approved — go to the dashboard. pushReplacement so the user can't
      // swipe/back-button their way back to the login screen.
      // Backend wraps driver fields under a 'driver' key:
      // { success: true, driver: { _id: ..., Name: ... }, token: ... }
      final Map<String, dynamic> driverObj =
          (driverData['driver'] is Map<String, dynamic>
              ? driverData['driver'] as Map<String, dynamic>
              : (driverData['data'] is Map<String, dynamic>
                  ? driverData['data'] as Map<String, dynamic>
                  : driverData));
      final String driverName = driverObj['Name']?.toString() ??
          driverObj['name']?.toString() ??
          driverData['Name']?.toString() ??
          driverData['name']?.toString() ??
          'Driver';
      final String? driverId = driverObj['_id']?.toString() ??
          driverObj['id']?.toString() ??
          driverData['_id']?.toString() ??
          driverData['id']?.toString();
      
      final String? token = response['token']?.toString() ?? driverData['token']?.toString();

      String? extractUrl(dynamic field) {
        if (field == null) return null;
        if (field is String) return field;
        if (field is Map) {
          return field['url']?.toString();
        }
        return null;
      }

      final String? profilePic = extractUrl(driverObj['driverPhoto']) ??
          extractUrl(driverData['profilePic']) ??
          extractUrl(driverData['driverPhoto']);

      try {
        final prefs = await SharedPreferences.getInstance();
        final keySuffix = driverId != null ? '_$driverId' : '';
        await prefs.setString('saved_driver_name$keySuffix', driverName);
        await prefs.setString('driver_name', driverName);
        if (profilePic != null && profilePic.isNotEmpty) {
          await prefs.setString('saved_driver_photo$keySuffix', profilePic);
          await prefs.setString('driver_photo', profilePic);
        }
      } catch (_) {}

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              DriverDashboardScreen(
                driverName: driverName, 
                driverId: driverId,
                profilePic: profilePic,
                token: token,
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                // User Icon Circle
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E40AF),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.person, color: Colors.white, size: 60),
                  ),
                ),
                const SizedBox(height: 24),
                // Heading
                Text(
                  'Login',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 32),

                // Phone Number Field
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Phone Number',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('🇵🇰', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              '+92',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Phone Number',
                            hintStyle: GoogleFonts.inter(
                              color: Colors.grey.shade400,
                            ),
                            border: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Password Field
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Password',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Required';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1E40AF)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Remember Me
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (val) {
                          setState(() {
                            _rememberMe = val ?? false;
                          });
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        activeColor: const Color(0xFF1E40AF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remember Me',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFF1E40AF,
                      ).withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            'Login',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Forgot Password
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Forgot Password?',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
