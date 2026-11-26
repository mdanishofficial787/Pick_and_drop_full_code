import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import '/constants/api_constants.dart';
import '/services/location_service.dart';

class RideNavigationScreen extends StatefulWidget {
  final String rideId;
  final String pickupAddress;
  final String dropoffAddress;
  final String passengerName;
  final String passengerPhone;
  final String driverName;
  final String driverPhone;
  final bool isDriver;
  final LatLng? initialPickupCoord;
  final LatLng? initialDropoffCoord;

  const RideNavigationScreen({
    super.key,
    required this.rideId,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.passengerName = 'Passenger',
    this.passengerPhone = '',
    this.driverName = 'Driver',
    this.driverPhone = '',
    this.isDriver = false,
    this.initialPickupCoord,
    this.initialDropoffCoord,
  });

  @override
  State<RideNavigationScreen> createState() => _RideNavigationScreenState();
}

class _RideNavigationScreenState extends State<RideNavigationScreen> {
  final MapController _mapController = MapController();
  io.Socket? _socket;
  StreamSubscription<Position>? _positionStream;

  LatLng? _pickupCoord;
  LatLng? _dropoffCoord;
  LatLng? _driverCoord;

  List<LatLng> _routePoints = [];
  String _distanceKm = '--';
  int _durationMins = 0;
  bool _isLoadingRoute = true;
  bool _isNavigatingToDrop = false; // false = heading to pickup, true = heading to drop

  // Default fallback center is Lahore
  static const LatLng _defaultCenter = LatLng(31.5204, 74.3587);

  @override
  void initState() {
    super.initState();
    _pickupCoord = widget.initialPickupCoord;
    _dropoffCoord = widget.initialDropoffCoord;

    _setupSocket();
    _initializeCoordinatesAndRoute();

    if (widget.isDriver) {
      _startDriverLiveTracking();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _socket?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _setupSocket() {
    try {
      final baseUrl = ApiConstants.baseUrl;
      _socket = io.io(
        baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .build(),
      );

      _socket?.connect();

      _socket?.onConnect((_) {
        final cleanRideId = widget.rideId.replaceAll(
          RegExp(r'_(completed|accepted|started|assigned)', caseSensitive: false),
          '',
        );
        _socket?.emit('join-ride', cleanRideId);
      });

      // Customer listens for live driver coordinates
      if (!widget.isDriver) {
        _socket?.on('driver-location-updated', (data) {
          if (data is Map && mounted) {
            final lat = (data['lat'] is num) ? (data['lat'] as num).toDouble() : null;
            final lng = (data['lng'] is num) ? (data['lng'] as num).toDouble() : null;
            if (lat != null && lng != null) {
              setState(() {
                _driverCoord = LatLng(lat, lng);
              });
            }
          }
        });
      }
    } catch (e) {
      debugPrint('RideNavigationScreen socket error: $e');
    }
  }

  Future<void> _initializeCoordinatesAndRoute() async {
    setState(() => _isLoadingRoute = true);

    // 1. Resolve Driver position if driver
    if (widget.isDriver) {
      final pos = await LocationService.getCurrentGpsPosition();
      if (pos != null) {
        _driverCoord = LatLng(pos.latitude, pos.longitude);
      }
    }

    // 2. Geocode Pickup if needed
    _pickupCoord ??= await LocationService.geocodeAddress(
      widget.pickupAddress,
      fallbackLat: _driverCoord?.latitude ?? _defaultCenter.latitude,
      fallbackLon: _driverCoord?.longitude ?? _defaultCenter.longitude,
    );

    // 3. Geocode Dropoff if needed
    _dropoffCoord ??= await LocationService.geocodeAddress(
      widget.dropoffAddress,
      fallbackLat: (_pickupCoord?.latitude ?? _defaultCenter.latitude) + 0.04,
      fallbackLon: (_pickupCoord?.longitude ?? _defaultCenter.longitude) + 0.04,
    );

    // Fallbacks if geocoding had no results
    _pickupCoord ??= _driverCoord ?? _defaultCenter;
    _dropoffCoord ??= LatLng(_pickupCoord!.latitude + 0.035, _pickupCoord!.longitude + 0.035);
    _driverCoord ??= LatLng(_pickupCoord!.latitude - 0.015, _pickupCoord!.longitude - 0.015);

    // 4. Calculate Road Driving Route
    await _calculateRoadRoute();

    if (mounted) {
      setState(() => _isLoadingRoute = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBoundsToAllMarkers());
    }
  }

  Future<void> _calculateRoadRoute() async {
    if (_pickupCoord == null || _dropoffCoord == null) return;

    final LatLng start = (widget.isDriver && _driverCoord != null) ? _driverCoord! : _pickupCoord!;
    final LatLng end = _isNavigatingToDrop ? _dropoffCoord! : (_pickupCoord ?? _dropoffCoord!);

    final routeData = await LocationService.getDrivingRoute(start, end);
    if (mounted) {
      setState(() {
        _routePoints = (routeData['points'] as List<LatLng>?) ?? [start, end];
        _distanceKm = routeData['distanceKm']?.toString() ?? '--';
        _durationMins = (routeData['durationMins'] is int) ? routeData['durationMins'] : 0;
      });
    }
  }

  void _startDriverLiveTracking() {
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        if (!mounted) return;
        final newCoord = LatLng(position.latitude, position.longitude);

        setState(() {
          _driverCoord = newCoord;
        });

        // Broadcast to customer through socket
        final cleanRideId = widget.rideId.replaceAll(
          RegExp(r'_(completed|accepted|started|assigned)', caseSensitive: false),
          '',
        );
        _socket?.emit('driver-location-update', {
          'rideId': cleanRideId,
          'lat': position.latitude,
          'lng': position.longitude,
          'heading': position.heading,
          'speed': position.speed,
        });
      });
    } catch (e) {
      debugPrint('Error starting driver tracking stream: $e');
    }
  }

  void _fitBoundsToAllMarkers() {
    final List<LatLng> points = [];
    if (_driverCoord != null) points.add(_driverCoord!);
    if (_pickupCoord != null) points.add(_pickupCoord!);
    if (_dropoffCoord != null) points.add(_dropoffCoord!);

    if (points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(40, 90, 40, 260),
      ),
    );
  }

  void _openGoogleMaps() {
    final target = _isNavigatingToDrop ? _dropoffCoord : _pickupCoord;
    if (target != null) {
      LocationService.launchExternalNavigation(
        destLat: target.latitude,
        destLng: target.longitude,
        destAddress: _isNavigatingToDrop ? widget.dropoffAddress : widget.pickupAddress,
        originLat: _driverCoord?.latitude,
        originLng: _driverCoord?.longitude,
      );
    }
  }

  Future<void> _callPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available.')),
      );
      return;
    }
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.isDriver;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── 1. MAP VIEW ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pickupCoord ?? _defaultCenter,
              initialZoom: 14.5,
              minZoom: 5.0,
              maxZoom: 18.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rideandserve.app',
              ),

              // Road Polyline
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFF1959F6),
                    ),
                  ],
                ),

              // Markers Layer
              MarkerLayer(
                markers: [
                  // Pickup Marker (Green)
                  if (_pickupCoord != null)
                    Marker(
                      point: _pickupCoord!,
                      width: 44,
                      height: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            child: const Icon(Icons.trip_origin_rounded, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),

                  // Drop-off Marker (Red)
                  if (_dropoffCoord != null)
                    Marker(
                      point: _dropoffCoord!,
                      width: 44,
                      height: 44,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                            child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),

                  // Driver Vehicle Marker (Moving Blue Car Badge)
                  if (_driverCoord != null)
                    Marker(
                      point: _driverCoord!,
                      width: 48,
                      height: 48,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
                          ],
                        ),
                        child: const Icon(Icons.directions_car_filled_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── 2. TOP BAR (Back button + Title + Target toggle) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Back Button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),

                // Title Pill
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDriver ? Icons.navigation_rounded : Icons.radar_rounded,
                          color: const Color(0xFF1959F6),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isDriver ? 'Driver Navigation' : 'Live Ride Tracking',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isLoadingRoute)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1959F6)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'LIVE',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF16A34A),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 3. MAP CONTROLS (Recenter & Fit View) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 76,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'nav_fit_bounds_btn',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1959F6),
                  elevation: 3,
                  onPressed: _fitBoundsToAllMarkers,
                  child: const Icon(Icons.center_focus_strong_rounded),
                ),
                const SizedBox(height: 10),
                if (isDriver)
                  FloatingActionButton.small(
                    heroTag: 'nav_toggle_dest_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: _isNavigatingToDrop ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                    elevation: 3,
                    onPressed: () {
                      setState(() {
                        _isNavigatingToDrop = !_isNavigatingToDrop;
                      });
                      _calculateRoadRoute();
                    },
                    child: Icon(_isNavigatingToDrop ? Icons.flag_rounded : Icons.person_pin_circle_rounded),
                  ),
              ],
            ),
          ),

          // ── 4. BOTTOM TRIP INFO PANEL ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(context).padding.bottom + 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Route Metrics Row (Distance + Estimated Time)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF1959F6)),
                            const SizedBox(width: 6),
                            Text(
                              _durationMins > 0 ? '$_durationMins mins' : '10-15 mins',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1959F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.route_outlined, size: 16, color: Color(0xFF4B5563)),
                            const SizedBox(width: 6),
                            Text(
                              '$_distanceKm km',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Navigation Phase Label (Driver side)
                      if (isDriver)
                        GestureDetector(
                          onTap: () {
                            setState(() => _isNavigatingToDrop = !_isNavigatingToDrop);
                            _calculateRoadRoute();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isNavigatingToDrop ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _isNavigatingToDrop ? 'To Drop-off ➔' : 'To Pickup ➔',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isNavigatingToDrop ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Location Summary (Pickup & Drop)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.trip_origin_rounded, color: Color(0xFF16A34A), size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.pickupAddress.isNotEmpty ? widget.pickupAddress : 'Pickup Point',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 7),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(width: 2, height: 12, color: Colors.grey.shade300),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.dropoffAddress.isNotEmpty ? widget.dropoffAddress : 'Destination',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Contact Person & Action Buttons
                  Row(
                    children: [
                      // Contact info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDriver ? 'Passenger' : 'Assigned Driver',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            Text(
                              isDriver ? widget.passengerName : widget.driverName,
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Call Button
                      IconButton(
                        onPressed: () => _callPhone(isDriver ? widget.passengerPhone : widget.driverPhone),
                        icon: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.phone_rounded, color: Color(0xFF16A34A), size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Main Button
                  if (isDriver)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _openGoogleMaps,
                        icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                        label: Text(
                          _isNavigatingToDrop ? 'Start GPS to Drop-off' : 'Start GPS to Pickup',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1959F6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sync_rounded, size: 16, color: Color(0xFF1959F6)),
                          const SizedBox(width: 8),
                          Text(
                            'Tracking driver in real-time',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E3A8A)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
