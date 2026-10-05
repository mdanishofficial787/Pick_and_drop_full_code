import 'package:flutter/material.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/edit_profile_screen.dart';
import 'package:ride_and_serve/screens/customer/login_page.dart';
import 'package:ride_and_serve/services/auth_service.dart';

class ProfileViewScreen extends StatefulWidget {
  final CustomerUser? user;

  const ProfileViewScreen({super.key, this.user});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  CustomerUser? _currentUser;

  static const Color _screenBg = Color(0xFFF4F7FC);
  static const Color _borderColor = Color(0xFFCBD5E1);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    if (widget.user != null) {
      _currentUser = widget.user;
    } else {
      _currentUser = await AuthService.getCurrentUser();
    }
    if (mounted) setState(() {});
  }

  void _handleLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (ctx) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _currentUser?.fullName ?? 'Ali';

    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile View',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // Clean Profile Avatar View
              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: (_currentUser?.photoUrl != null && _currentUser!.photoUrl!.isNotEmpty)
                        ? Image.network(_currentUser!.photoUrl!, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 50, color: Color(0xFF2563EB)))
                        : const Icon(Icons.person, size: 50, color: Color(0xFF2563EB)),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // User Name
              Text(
                name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),

              const SizedBox(height: 8),

              // Verified User Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 15),
                    SizedBox(width: 6),
                    Text(
                      'Verified User',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Menu Card Container
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Edit Profile Option
                    _buildMenuItem(
                      icon: Icons.person_outline_rounded,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Edit Profile',
                      onTap: () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => EditProfileScreen(user: _currentUser),
                          ),
                        );
                        if (updated != null && mounted) {
                          _loadUser();
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 64, endIndent: 20, color: Color(0xFFF1F5F9)),

                    // Ride History Option
                    _buildMenuItem(
                      icon: Icons.access_time_rounded,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Ride History',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Opening Ride History...'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 64, endIndent: 20, color: Color(0xFFF1F5F9)),

                    // Log Out Option
                    _buildMenuItem(
                      icon: Icons.logout_rounded,
                      iconBg: const Color(0xFFFEE2E2),
                      iconColor: const Color(0xFFEF4444),
                      title: 'Log Out',
                      titleColor: const Color(0xFF0F172A),
                      onTap: _handleLogout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: titleColor ?? const Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF2563EB), size: 22),
          ],
        ),
      ),
    );
  }
}
