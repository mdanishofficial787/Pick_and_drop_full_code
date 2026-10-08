import os

path1 = r'C:\RideAndServe\Frontend\lib\screens\driver\driver_dashboard_screen.dart'
with open(path1, 'r', encoding='utf-8') as f:
    text1 = f.read()

import1 = "import 'dart:convert';\nimport 'package:http/http.dart' as http;\nimport '../../api_config.dart';\n"
if 'package:http/http.dart' not in text1:
    text1 = text1.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\n" + import1)

# convert to stateful
text1 = text1.replace('class DriverDashboardScreen extends StatelessWidget', 'class DriverDashboardScreen extends StatefulWidget')
text1 = text1.replace('''  const DriverDashboardScreen({
    super.key,
    required this.driverName,
    this.driverId,
    this.profilePic,
    this.token,
  });''', '''  const DriverDashboardScreen({
    super.key,
    required this.driverName,
    this.driverId,
    this.profilePic,
    this.token,
  });

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
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
        Uri.parse('\/driver/\'),
        headers: widget.token != null ? {'Authorization': 'Bearer \'} : {},
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
''')

text1 = text1.replace('profilePic != null', 'currentProfilePic != null')
text1 = text1.replace('profilePic!', 'currentProfilePic!')
text1 = text1.replace('driverName.', 'currentDriverName.')
text1 = text1.replace('driverId', 'widget.driverId')
text1 = text1.replace('token', 'widget.token')
text1 = text1.replace('profilePic: profilePic', 'profilePic: currentProfilePic')
text1 = text1.replace('profilePic: widget.profilePic', 'profilePic: currentProfilePic')
text1 = text1.replace('driverName: driverName', 'driverName: currentDriverName')
text1 = text1.replace('driverName: widget.driverName', 'driverName: currentDriverName')

# update onTap to await and fetch
text1 = text1.replace('''                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProfileSettingsScreen(
                                  driverName: widget.currentDriverName,
                                  profilePic: currentProfilePic,
                                  widget.driverId: widget.widget.driverId,
                                  widget.token: widget.widget.token,
                                ),
                              ),
                            );
                          },''', '''                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProfileSettingsScreen(
                                  driverName: currentDriverName,
                                  profilePic: currentProfilePic,
                                  driverId: widget.driverId,
                                  token: widget.token,
                                ),
                              ),
                            );
                            _fetchProfile();
                          },''')

with open(path1, 'w', encoding='utf-8') as f:
    f.write(text1)


path2 = r'C:\RideAndServe\Frontend\lib\screens\driver\profile_settings_screen.dart'
with open(path2, 'r', encoding='utf-8') as f:
    text2 = f.read()

if 'package:http/http.dart' not in text2:
    text2 = text2.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\n" + import1)

text2 = text2.replace('class ProfileSettingsScreen extends StatelessWidget', 'class ProfileSettingsScreen extends StatefulWidget')
text2 = text2.replace('''  const ProfileSettingsScreen({
    super.key,
    required this.driverName,
    this.profilePic,
    this.driverId,
    this.token,
    this.onLogout,
  });''', '''  const ProfileSettingsScreen({
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
        Uri.parse('\/driver/\'),
        headers: widget.token != null ? {'Authorization': 'Bearer \'} : {},
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
''')

text2 = text2.replace('profilePic != null', 'currentProfilePic != null')
text2 = text2.replace('profilePic!', 'currentProfilePic!')
text2 = text2.replace('driverName', 'currentDriverName')
text2 = text2.replace('widget.currentDriverName', 'currentDriverName')
text2 = text2.replace('driverId', 'widget.driverId')
text2 = text2.replace('token', 'widget.token')
text2 = text2.replace('onLogout', 'widget.onLogout')
text2 = text2.replace('profilePic: profilePic', 'profilePic: currentProfilePic')
text2 = text2.replace('profilePic: widget.profilePic', 'profilePic: currentProfilePic')

text2 = text2.replace('''                    _buildMenuItem(context, icon: Icons.person_outline_rounded, iconBgColor: const Color(0xFFEFF6FF), iconColor: const Color(0xFF1959F6), title: 'Edit Profile', onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen(driverName: currentDriverName, profilePic: currentProfilePic, widget.driverId: widget.widget.driverId, widget.token: widget.widget.token)));
                    }, showDivider: true),''', '''                    _buildMenuItem(context, icon: Icons.person_outline_rounded, iconBgColor: const Color(0xFFEFF6FF), iconColor: const Color(0xFF1959F6), title: 'Edit Profile', onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen(driverName: currentDriverName, profilePic: currentProfilePic, driverId: widget.driverId, token: widget.token)));
                      _fetchProfile();
                    }, showDivider: true),''')

with open(path2, 'w', encoding='utf-8') as f:
    f.write(text2)

