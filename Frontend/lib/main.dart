import 'package:flutter/material.dart';
import 'package:ride_and_serve/screens/welcome_screen.dart';
import 'package:ride_and_serve/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RideAndServeApp());
}

class RideAndServeApp extends StatelessWidget {
  const RideAndServeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ride & Serve',
      theme: AppTheme.lightTheme,
      home: const AccountTypeScreen(),
    );
  }
}
