const fs = require('fs');

const path1 = 'C:/RideAndServe/Frontend/lib/screens/driver/driver_dashboard_screen.dart';
let text1 = fs.readFileSync(path1, 'utf-8');

const import1 = "import 'dart:convert';\nimport 'package:http/http.dart' as http;\nimport '../../api_config.dart';\n";
if (!text1.includes('package:http/http.dart')) {
    text1 = text1.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\n" + import1);
}

text1 = text1.replace('class DriverDashboardScreen extends StatelessWidget', 'class DriverDashboardScreen extends StatefulWidget');
text1 = text1.replace(  const DriverDashboardScreen({
    super.key,
    required this.driverName,
    this.driverId,
    this.profilePic,
    this.token,
  });,   const DriverDashboardScreen({
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
        Uri.parse('\\/driver/\\'),
        headers: widget.token != null ? {'Authorization': 'Bearer \\'} : {},
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
);

text1 = text1.split('profilePic != null').join('currentProfilePic != null');
text1 = text1.split('profilePic!').join('currentProfilePic!');
text1 = text1.split('driverName.').join('currentDriverName.');
text1 = text1.split('driverId').join('widget.driverId');
text1 = text1.split('token').join('widget.token');
text1 = text1.split('profilePic: profilePic').join('profilePic: currentProfilePic');
text1 = text1.split('profilePic: widget.profilePic').join('profilePic: currentProfilePic');
text1 = text1.split('driverName: driverName').join('driverName: currentDriverName');
text1 = text1.split('driverName: widget.driverName').join('driverName: currentDriverName');
text1 = text1.split('widget.widget.').join('widget.');

// Fix the onTap navigation
let searchStr =                           onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProfileSettingsScreen(
                                  driverName: currentDriverName,
                                  profilePic: currentProfilePic,
                                  driverId: widget.driverId,
                                  token: widget.token,
                                ),
                              ),
                            );
                          },;

if (!text1.includes(searchStr)) {
  // Let's just do a generic replace for ProfileSettingsScreen route
  text1 = text1.replace(uilder: (_) => ProfileSettingsScreen(, uilder: (_) => ProfileSettingsScreen();
}

fs.writeFileSync(path1, text1, 'utf-8');


const path2 = 'C:/RideAndServe/Frontend/lib/screens/driver/profile_settings_screen.dart';
let text2 = fs.readFileSync(path2, 'utf-8');

if (!text2.includes('package:http/http.dart')) {
    text2 = text2.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\n" + import1);
}

text2 = text2.replace('class ProfileSettingsScreen extends StatelessWidget', 'class ProfileSettingsScreen extends StatefulWidget');
text2 = text2.replace(  const ProfileSettingsScreen({
    super.key,
    required this.driverName,
    this.profilePic,
    this.driverId,
    this.token,
    this.onLogout,
  });,   const ProfileSettingsScreen({
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
        Uri.parse('\\/driver/\\'),
        headers: widget.token != null ? {'Authorization': 'Bearer \\'} : {},
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
);

text2 = text2.split('profilePic != null').join('currentProfilePic != null');
text2 = text2.split('profilePic!').join('currentProfilePic!');
text2 = text2.split('driverName').join('currentDriverName');
text2 = text2.split('widget.currentDriverName').join('currentDriverName');
text2 = text2.split('driverId').join('widget.driverId');
text2 = text2.split('token').join('widget.token');
text2 = text2.split('onLogout').join('widget.onLogout');
text2 = text2.split('profilePic: profilePic').join('profilePic: currentProfilePic');
text2 = text2.split('profilePic: widget.profilePic').join('profilePic: currentProfilePic');
text2 = text2.split('widget.widget.').join('widget.');

fs.writeFileSync(path2, text2, 'utf-8');

