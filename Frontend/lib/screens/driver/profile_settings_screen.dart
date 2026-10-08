import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'edit_profile_screen.dart';
import '../welcome_screen.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../api_config.dart';

class ProfileSettingsScreen extends StatefulWidget {
  final String driverName;
  final String? profilePic;
  final String? driverId;
  final String? token;
  final VoidCallback? onLogout;

  const ProfileSettingsScreen({
    super.key,
    required this.driverName,
    this.profilePic,
    this.driverId,
    this.token,
    this.onLogout,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  String? currentProfilePic;
  String currentDriverName = "";

  @override
  void initState() {
    super.initState();
    currentProfilePic = widget.profilePic;
    currentDriverName = widget.driverName;
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    if (widget.driverId == null) return;
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/driver/${widget.driverId}'),
        headers: widget.token != null ? {'Authorization': 'Bearer ${widget.token}'} : {},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final d = data['driver'] ?? data['data'] ?? data;
        if (mounted) {
          setState(() {
            currentDriverName = d['fullName']?.toString() ?? d['name']?.toString() ?? currentDriverName;
            currentProfilePic = d['profilePic']?.toString() ?? d['profilePicture']?.toString() ?? currentProfilePic;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Profile Settings',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade200,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(child: _buildProfileImage()),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1959F6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              currentDriverName,
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 16),
                  const SizedBox(width: 5),
                  Text('Verified User', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF059669))),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  _buildMenuItem(context, icon: Icons.person_outline_rounded, iconBgColor: const Color(0xFFEFF6FF), iconColor: const Color(0xFF1959F6), title: 'Edit Profile', onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen(driverName: currentDriverName, profilePic: currentProfilePic, driverId: widget.driverId, token: widget.token)));
                  }, showDivider: true),
                  _buildMenuItem(context, icon: Icons.access_time_rounded, iconBgColor: const Color(0xFFEFF6FF), iconColor: const Color(0xFF1959F6), title: 'Ride History', onTap: () {}, showDivider: true),
                  _buildMenuItem(context, icon: Icons.logout_rounded, iconBgColor: const Color(0xFFFEE2E2), iconColor: const Color(0xFFDC2626), title: 'Log Out', onTap: () => _confirmLogout(context), showDivider: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage() {
    if (currentProfilePic != null && currentProfilePic!.isNotEmpty) {
      return Image.network(currentProfilePic!, fit: BoxFit.cover, width: 100, height: 100, errorBuilder: (_, __, ___) => _defaultAvatar());
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() => Container(color: const Color(0xFFE0E7FF), child: const Icon(Icons.person_rounded, color: Color(0xFF1959F6), size: 48));

  Widget _buildMenuItem(BuildContext context, {required IconData icon, required Color iconBgColor, required Color iconColor, required String title, required VoidCallback onTap, required bool showDivider}) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor, size: 22)),
                const SizedBox(width: 16),
                Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF111827)))),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 22),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, indent: 20, endIndent: 20, color: Colors.grey.shade100),
      ],
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to log out?', style: GoogleFonts.inter(color: Colors.grey.shade600)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade600))),
          ElevatedButton(
            onPressed: () { 
              Navigator.pop(ctx); 
              if (widget.onLogout != null) {
                widget.onLogout!();
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AccountTypeScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('Log Out', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
