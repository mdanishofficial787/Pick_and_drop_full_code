import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RouteMatchSetupScreen extends StatefulWidget {
  const RouteMatchSetupScreen({super.key});

  @override
  State<RouteMatchSetupScreen> createState() => _RouteMatchSetupScreenState();
}

class _RouteMatchSetupScreenState extends State<RouteMatchSetupScreen> {
  int _preferredRouteIndex = 1; // Default to Route B (index 1)

  @override
  Widget build(BuildContext context) {
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
      body: SingleChildScrollView(
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
            _buildRouteCard(
              index: 0,
              routeName: 'Route A',
              time: '7:00 AM - 9:00 AM',
              requests: '8 customer requests',
            ),
            const SizedBox(height: 12),
            _buildRouteCard(
              index: 1,
              routeName: 'Route B',
              time: '1:00 PM - 3:00 PM',
              requests: '15 customer requests',
            ),
            const SizedBox(height: 12),
            _buildRouteCard(
              index: 2,
              routeName: 'Route C',
              time: '6:00 PM - 8:00 PM',
              requests: '5 customer requests',
            ),
            const SizedBox(height: 24),
            _buildLocationInput(Icons.location_on, 'Start Point'),
            const SizedBox(height: 12),
            _buildLocationInput(Icons.location_on, 'End Point'),
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
                onPressed: () {
                  // Handle save logic
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007BFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    required String routeName,
    required String time,
    required String requests,
  }) {
    bool isPreferred = _preferredRouteIndex == index;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$routeName: Pickup Point → Drop Point',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  requests,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _preferredRouteIndex = index;
                  });
                },
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
    );
  }

  Widget _buildLocationInput(IconData icon, String hintText) {
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
