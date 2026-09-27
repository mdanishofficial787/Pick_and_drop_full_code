import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import '/theme/app_theme.dart';
import 'preferred_routes_screen.dart';
import 'manage_availability_screen.dart';
import 'ride_management_screen.dart';
import 'report_issue_screen.dart';
import 'profile_settings_screen.dart';
import 'route_match_setup_screen.dart';

class DriverDashboardScreen extends StatelessWidget {
  final String driverName;
  final String? driverId;
  final String? profilePic;
  final String? token;

  const DriverDashboardScreen({
    super.key,
    required this.driverName,
    this.driverId,
    this.profilePic,
    this.token,
  });

  void _showActionFeedback(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title module opened.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Top Curved Blue Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 48,
                bottom: 26,
                left: 18,
                right: 18,
              ),
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x331A56DB),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (profilePic != null && profilePic!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12, top: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.white24,
                            backgroundImage: NetworkImage(profilePic!),
                          ),
                        )
                      else
                        Container(
                          margin: const EdgeInsets.only(bottom: 12, top: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const CircleAvatar(
                            radius: 36,
                            backgroundColor: Colors.white24,
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      Text(
                        'WELCOME, ${driverName.toUpperCase()}!',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your rides & bookings',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Dashboard Options List
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      children: [
                        // Card 1: Preferred Routes
                        _buildMenuCard(
                          context: context,
                          icon: Icons.calendar_month_outlined,
                          title: 'Preferred Routes',
                          subtitle: 'Set your preferred routes and location.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PreferredRoutesScreen(driverId: driverId),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 2: Availability Management
                        _buildMenuCard(
                          context: context,
                          icon: Icons.access_time_rounded,
                          title: 'Availability Management',
                          subtitle: 'Set your available time slots.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ManageAvailabilityScreen(
                                  driverId: driverId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 3: Ride Management
                        _buildMenuCard(
                          context: context,
                          icon: Icons.groups_rounded,
                          title: 'Ride management',
                          subtitle:
                              'Manage your assigned and incoming ride requests.',
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                              ),
                              builder: (ctx) => SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(
                                          bottom: 20,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Select Ride Type',
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.calendar_month_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Monthly pick and drop',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: driverId,
                                                    driverName: driverName,
                                                    filterPrefix: 'REQ-',
                                                    moduleName:
                                                        'Monthly Pick & Drop',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.schedule_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Scheduled rides',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: driverId,
                                                    driverName: driverName,
                                                    filterPrefix: 'SCH-',
                                                    moduleName:
                                                        'Scheduled Rides',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.person_outline_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Hire driver',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: driverId,
                                                    driverName: driverName,
                                                    filterPrefix: 'HDR-',
                                                    moduleName: 'Hire Driver',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.luggage_rounded,
                                          color: Color(0xFF1959F6),
                                        ),
                                        title: Text(
                                          'Travel & Tourism',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RideManagementScreen(
                                                    driverId: driverId,
                                                    driverName: driverName,
                                                    filterPrefix: 'TT-',
                                                    moduleName:
                                                        'Travel & Tourism',
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 4: Report an Issue
                        _buildMenuCard(
                          context: context,
                          icon: Icons.warning_rounded,
                          title: 'Report an Issue',
                          subtitle: 'Select passenger(s) and report an issue.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReportIssueScreen(
                                  driverId: driverId,
                                  driverName: driverName,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Card 5: Route Matching
                        _buildMenuCard(
                          context: context,
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Route Matching',
                          subtitle: 'See suggested Route Requests.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RouteMatchSetupScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // Profile View
                        _buildMenuCard(
                          context: context,
                          icon: Icons.history_rounded,
                          title: 'Profile View',
                          subtitle: 'View your past rides and invoices.',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProfileSettingsScreen(
                                  driverName: driverName,
                                  profilePic: profilePic,
                                  driverId: driverId,
                                  token: token,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // Need Assistance Card
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.borderLight,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Need Assistance?',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _showActionFeedback(
                                      context,
                                      'Support Hotline: Calling 24/7 Helpline...',
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.primaryBlueLight,
                                              width: 1,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.phone_rounded,
                                            color: AppColors.primaryBlue,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Contact',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryBlueLight, width: 1),
              ),
              child: Icon(icon, color: AppColors.primaryBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
