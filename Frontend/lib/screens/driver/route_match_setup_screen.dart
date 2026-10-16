import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../constants/api_constants.dart';
import '../../services/driver_api_service.dart';
import 'route_customers_screen.dart';

class RouteMatchSetupScreen extends StatefulWidget {
  final String? driverId;
  final String driverName;

  const RouteMatchSetupScreen({
    super.key,
    this.driverId,
    this.driverName = 'Arbab',
  });

  @override
  State<RouteMatchSetupScreen> createState() => _RouteMatchSetupScreenState();
}

class _RouteMatchSetupScreenState extends State<RouteMatchSetupScreen> {
  int _preferredRouteIndex = 1; // Default to Route B (index 1)
  final TextEditingController _startPointController = TextEditingController();
  final TextEditingController _endPointController = TextEditingController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  @override
  void dispose() {
    _startPointController.dispose();
    _endPointController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getDefaultFallbackRoutes() {
    return [
      {
        'routeId': 'ROUTE-A',
        'routeName': 'Route A',
        'pickupPoint': 'Pickup Point',
        'dropoffPoint': 'Drop Point',
        'timeRange': '7:00 AM - 9:00 AM',
        'customerCount': 8,
        'status': 'Pending',
        'isPreferred': false,
        'customers': [
          {
            'requestId': 'REQ-8031',
            'customerName': 'Sarah Khan',
            'phone': '+92 300 1122331',
            'pickupLocation': 'I-8/4, Street 12, Islamabad',
            'dropoffLocation': 'Blue Area, Saudi Pak Tower',
            'time': '7:15 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8032',
            'customerName': 'Muhammad Ali',
            'phone': '+92 321 2233442',
            'pickupLocation': 'I-8/2, Main Road, Islamabad',
            'dropoffLocation': 'F-6 Markaz, Super Market',
            'time': '7:25 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8033',
            'customerName': 'Ahmed Raza',
            'phone': '+92 333 3344553',
            'pickupLocation': 'H-8/1, Near HEC, Islamabad',
            'dropoffLocation': 'G-7/2, Street 8, Islamabad',
            'time': '7:40 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8034',
            'customerName': 'Fatima Noor',
            'phone': '+92 345 4455664',
            'pickupLocation': 'I-9/1, Street 3, Islamabad',
            'dropoffLocation': 'Blue Area, ISE Towers',
            'time': '7:55 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8035',
            'customerName': 'Zainab Bibi',
            'phone': '+92 301 5566775',
            'pickupLocation': 'I-8/3, Street 25, Islamabad',
            'dropoffLocation': 'F-7 Markaz, Jinnah Super',
            'time': '8:10 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8036',
            'customerName': 'Hamza Tariq',
            'phone': '+92 312 6677886',
            'pickupLocation': 'G-8/4, Street 18, Islamabad',
            'dropoffLocation': 'Zero Point Interchange',
            'time': '8:25 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8037',
            'customerName': 'Ayesha Malik',
            'phone': '+92 305 7788997',
            'pickupLocation': 'I-8/1, Service Road, Islamabad',
            'dropoffLocation': 'Blue Area, Stock Exchange',
            'time': '8:35 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8038',
            'customerName': 'Bilal Ahmed',
            'phone': '+92 322 8899008',
            'pickupLocation': 'H-9/2, Near Metro, Islamabad',
            'dropoffLocation': 'Pak Secretariat, Gate 3',
            'time': '8:50 AM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
        ],
      },
      {
        'routeId': 'ROUTE-B',
        'routeName': 'Route B',
        'pickupPoint': 'Pickup Point',
        'dropoffPoint': 'Drop Point',
        'timeRange': '1:00 PM - 3:00 PM',
        'customerCount': 15,
        'status': 'Pending',
        'isPreferred': true,
        'customers': [
          {
            'requestId': 'REQ-8041',
            'customerName': 'Omar Farooq',
            'phone': '+92 300 2345671',
            'pickupLocation': 'F-10 Markaz, Islamabad',
            'dropoffLocation': 'Blue Area, Beverly Centre',
            'time': '1:10 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8042',
            'customerName': 'Sana Javed',
            'phone': '+92 321 3456782',
            'pickupLocation': 'F-11/2, Street 14, Islamabad',
            'dropoffLocation': 'G-8 Markaz, Islamabad',
            'time': '1:20 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8043',
            'customerName': 'Hassan Shah',
            'phone': '+92 333 4567893',
            'pickupLocation': 'G-10/4, Street 22, Islamabad',
            'dropoffLocation': 'Blue Area, Ufone Tower',
            'time': '1:30 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8044',
            'customerName': 'Maryam Nawaz',
            'phone': '+92 345 5678904',
            'pickupLocation': 'F-8/3, Park Road, Islamabad',
            'dropoffLocation': 'F-6/1, School Road',
            'time': '1:40 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8045',
            'customerName': 'Usman Ghani',
            'phone': '+92 302 6789015',
            'pickupLocation': 'G-11/3, Main Double Road',
            'dropoffLocation': 'Blue Area, Kulsum Plaza',
            'time': '1:50 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8046',
            'customerName': 'Khadija Bibi',
            'phone': '+92 313 7890126',
            'pickupLocation': 'E-11/2, MPCHS, Islamabad',
            'dropoffLocation': 'F-7/2, Street 11, Islamabad',
            'time': '2:00 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8047',
            'customerName': 'Zubair Khan',
            'phone': '+92 306 8901237',
            'pickupLocation': 'F-10/1, Street 30, Islamabad',
            'dropoffLocation': 'Zero Point, Islamabad',
            'time': '2:10 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8048',
            'customerName': 'Anum Tariq',
            'phone': '+92 324 9012348',
            'pickupLocation': 'G-9/1, Street 4, Islamabad',
            'dropoffLocation': 'Blue Area, Green Trust Tower',
            'time': '2:20 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8049',
            'customerName': 'Kamran Akmal',
            'phone': '+92 334 0123459',
            'pickupLocation': 'G-10/2, Near Court, Islamabad',
            'dropoffLocation': 'Pak Secretariat, Block A',
            'time': '2:30 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8050',
            'customerName': 'Hina Altaf',
            'phone': '+92 303 1234560',
            'pickupLocation': 'F-11/4, Street 9, Islamabad',
            'dropoffLocation': 'Centaurus Mall, Jinnah Ave',
            'time': '2:35 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8051',
            'customerName': 'Waqas Younis',
            'phone': '+92 323 2345671',
            'pickupLocation': 'F-10/3, Street 15, Islamabad',
            'dropoffLocation': 'Blue Area, Islamabad',
            'time': '2:40 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8052',
            'customerName': 'Mahnoor Baloch',
            'phone': '+92 335 3456782',
            'pickupLocation': 'G-11/1, Street 3, Islamabad',
            'dropoffLocation': 'F-8 Markaz, Ayub Market',
            'time': '2:45 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8053',
            'customerName': 'Danish Taimoor',
            'phone': '+92 346 4567893',
            'pickupLocation': 'F-8/2, Street 7, Islamabad',
            'dropoffLocation': 'Blue Area, Islamabad',
            'time': '2:50 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8054',
            'customerName': 'Sadia Imam',
            'phone': '+92 307 5678904',
            'pickupLocation': 'G-9/3, Street 19, Islamabad',
            'dropoffLocation': 'F-6 Markaz, Islamabad',
            'time': '2:55 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8055',
            'customerName': 'Babar Azam',
            'phone': '+92 314 6789015',
            'pickupLocation': 'F-10/4, Street 40, Islamabad',
            'dropoffLocation': 'Blue Area, Islamabad',
            'time': '3:00 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
        ],
      },
      {
        'routeId': 'ROUTE-C',
        'routeName': 'Route C',
        'pickupPoint': 'Pickup Point',
        'dropoffPoint': 'Drop Point',
        'timeRange': '6:00 PM - 8:00 PM',
        'customerCount': 5,
        'status': 'Pending',
        'isPreferred': false,
        'customers': [
          {
            'requestId': 'REQ-8061',
            'customerName': 'Noman Ali',
            'phone': '+92 300 9988771',
            'pickupLocation': 'Saddar, Cantt, Rawalpindi',
            'dropoffLocation': 'Blue Area, Islamabad',
            'time': '6:15 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8062',
            'customerName': 'Farah Naz',
            'phone': '+92 321 8877662',
            'pickupLocation': 'Commercial Market, Rawalpindi',
            'dropoffLocation': 'F-7 Markaz, Islamabad',
            'time': '6:30 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8063',
            'customerName': 'Tariq Jameel',
            'phone': '+92 333 7766553',
            'pickupLocation': 'Chandni Chowk, Murree Road',
            'dropoffLocation': 'Zero Point, Islamabad',
            'time': '6:50 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8064',
            'customerName': 'Mehwish Hayat',
            'phone': '+92 345 6655444',
            'pickupLocation': 'Westridge 1, Rawalpindi',
            'dropoffLocation': 'F-6/2, Islamabad',
            'time': '7:15 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
          {
            'requestId': 'REQ-8065',
            'customerName': 'Asim Azhar',
            'phone': '+92 301 5544335',
            'pickupLocation': 'Faizabad Interchange',
            'dropoffLocation': 'Blue Area, Islamabad',
            'time': '7:45 PM',
            'fareFormatted': 'Rs. 9,500',
            'status': 'Pending Acceptance',
          },
        ],
      },
    ];
  }

  Future<void> _fetchRoutes() async {
    try {
      final response = await http
          .get(Uri.parse(ApiConstants.suggestedRoutes))
          .timeout(const Duration(seconds: 4))
          .catchError((_) => http.Response('{}', 500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List rawRoutes = data['routes'] ?? [];
        if (rawRoutes.isNotEmpty) {
          final mapped = rawRoutes.map((r) => Map<String, dynamic>.from(r)).toList();
          if (mounted) {
            setState(() {
              _routes = mapped;
              for (int i = 0; i < _routes.length; i++) {
                if (_routes[i]['isPreferred'] == true) {
                  _preferredRouteIndex = i;
                }
              }
              _isLoading = false;
            });
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback if backend is slow/offline
    if (mounted) {
      setState(() {
        _routes = _getDefaultFallbackRoutes();
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePreferred(int index) async {
    setState(() {
      _preferredRouteIndex = index;
    });

    if (index < _routes.length) {
      final routeId = _routes[index]['routeId'] ?? _routes[index]['_id'];
      if (routeId != null) {
        try {
          await http.patch(
            Uri.parse(ApiConstants.togglePreferredRoute(routeId.toString())),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'isPreferred': true}),
          );
        } catch (_) {}
      }
    }
  }

  void _openRouteCustomers(Map<String, dynamic> route, int index) async {
    final updatedRoute = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteCustomersScreen(
          route: route,
          driverId: widget.driverId,
          driverName: widget.driverName,
          onRouteAccepted: (updated) {
            setState(() {
              _routes[index] = updated;
            });
          },
        ),
      ),
    );

    if (updatedRoute != null && mounted) {
      setState(() {
        _routes[index] = updatedRoute;
      });
    }
  }

  Future<void> _handleSave() async {
    final startPoint = _startPointController.text.trim();
    final endPoint = _endPointController.text.trim();

    if (startPoint.isNotEmpty && widget.driverId != null) {
      try {
        await DriverApiService.savePreferredRoutes(
          driverId: widget.driverId!,
          startPoint: startPoint,
          endPoint: endPoint,
          time: _preferredRouteIndex < _routes.length
              ? _routes[_preferredRouteIndex]['timeRange'] ?? ''
              : '',
        );
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Route Preferences Saved!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routesToRender = _routes.isNotEmpty ? _routes : _getDefaultFallbackRoutes();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Route Match Setup',
          style: GoogleFonts.inter(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested Route Requests',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on your available timing',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Route Cards
                  for (int i = 0; i < routesToRender.length; i++) ...[
                    _buildRouteCard(
                      index: i,
                      route: routesToRender[i],
                    ),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 12),
                  _buildLocationInput(Icons.location_on, 'Start Point', _startPointController),
                  const SizedBox(height: 12),
                  _buildLocationInput(Icons.location_on, 'End Point', _endPointController),
                  const SizedBox(height: 30),
                  Text(
                    'Marking a route as preferred will match you with more customers along this route',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007BFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Save',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRouteCard({
    required int index,
    required Map<String, dynamic> route,
  }) {
    final routeName = route['routeName'] ?? 'Route ${String.fromCharCode(65 + index)}';
    final pickupPoint = route['pickupPoint'] ?? 'Pickup Point';
    final dropoffPoint = route['dropoffPoint'] ?? 'Drop Point';
    final timeRange = route['timeRange'] ?? '7:00 AM - 9:00 AM';
    final count = (route['customers'] as List?)?.length ?? route['customerCount'] ?? 8;
    final isAccepted = route['status'] == 'ACCEPTED';
    final bool isPreferred = _preferredRouteIndex == index;

    return InkWell(
      onTap: () => _openRouteCustomers(route, index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAccepted ? const Color(0xFF86EFAC) : Colors.grey[300]!,
            width: isAccepted ? 1.5 : 1,
          ),
          boxShadow: [
            if (isAccepted)
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$routeName: $pickupPoint → $dropoffPoint',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (isAccepted)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Accepted',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF16A34A),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        timeRange,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '$count customer requests',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• Tap to view & accept',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF007BFF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                InkWell(
                  onTap: () => _togglePreferred(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPreferred ? Colors.transparent : Colors.grey[300]!,
                      ),
                    ),
                    child: Icon(
                      isPreferred ? Icons.star : Icons.star_border,
                      color: isPreferred ? const Color(0xFF007BFF) : Colors.grey[400],
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mark as Preferred',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInput(IconData icon, String hintText, TextEditingController controller) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF007BFF)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: GoogleFonts.inter(color: Colors.grey[500]),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
