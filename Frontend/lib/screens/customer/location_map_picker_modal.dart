import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ride_and_serve/constants/app_colors.dart';
import 'package:ride_and_serve/services/location_service.dart';

class LocationMapPickerModal extends StatefulWidget {
  final String title;
  final LatLng? initialPosition;
  final String? initialAddress;

  const LocationMapPickerModal({
    super.key,
    required this.title,
    this.initialPosition,
    this.initialAddress,
  });

  @override
  State<LocationMapPickerModal> createState() => _LocationMapPickerModalState();
}

class _LocationMapPickerModalState extends State<LocationMapPickerModal> {
  late final MapController _mapController;
  late LatLng _currentCenter;
  
  bool _isGeocoding = false;
  bool _isLocatingGps = false;
  LocationSuggestion? _selectedSuggestion;
  String _addressText = 'Fetching address...';
  Timer? _debounceTimer;

  static const LatLng _lahoreDefault = LatLng(31.5204, 74.3587);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentCenter = widget.initialPosition ?? _lahoreDefault;

    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _addressText = widget.initialAddress!;
    }
    _fetchAddressForCenter(_currentCenter);

    if (widget.initialPosition == null) {
      _moveToCurrentGpsLocation();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _moveToCurrentGpsLocation() async {
    setState(() => _isLocatingGps = true);
    final pos = await LocationService.getCurrentGpsPosition();
    if (pos != null && mounted) {
      final gpsLatLng = LatLng(pos.latitude, pos.longitude);
      _mapController.move(gpsLatLng, 16.5);
      setState(() {
        _currentCenter = gpsLatLng;
        _isLocatingGps = false;
      });
      _fetchAddressForCenter(gpsLatLng);
    } else if (mounted) {
      setState(() => _isLocatingGps = false);
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      setState(() {
        _currentCenter = camera.center;
        _isGeocoding = true;
        _addressText = 'Updating location...';
      });

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _fetchAddressForCenter(camera.center);
      });
    }
  }

  Future<void> _fetchAddressForCenter(LatLng center) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);

    final res = await LocationService.reverseGeocode(center.latitude, center.longitude);

    if (mounted) {
      setState(() {
        _isGeocoding = false;
        if (res != null) {
          _selectedSuggestion = res;
          _addressText = res.fullAddress;
        } else {
          _addressText = '(${center.latitude.toStringAsFixed(4)}, ${center.longitude.toStringAsFixed(4)})';
        }
      });
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
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // FlutterMap Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 15.5,
              minZoom: 5.0,
              maxZoom: 18.5,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rideandserve.app',
              ),
            ],
          ),

          // Center Pin Marker (InDrive / Uber style)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Drag map to drop pin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.location_on,
                    size: 48,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ),
          ),

          // Pin Base Shadow Dot
          Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Top Address Header Panel
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.my_location, color: AppColors.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isGeocoding ? 'Locating...' : (_selectedSuggestion?.title ?? 'Selected Location'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _addressText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_isGeocoding)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue),
                    ),
                ],
              ),
            ),
          ),

          // Floating GPS Target Button (InDrive "My Location" 🎯)
          Positioned(
            bottom: 90,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'my_location_btn',
              onPressed: _isLocatingGps ? null : _moveToCurrentGpsLocation,
              backgroundColor: Colors.white,
              elevation: 4,
              child: _isLocatingGps
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primaryBlue),
                    )
                  : const Icon(Icons.my_location_rounded, color: AppColors.primaryBlue, size: 26),
            ),
          ),

          // Bottom Confirm Location Button
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isGeocoding
                    ? null
                    : () {
                        final result = _selectedSuggestion ??
                            LocationSuggestion(
                              id: 'pin_${_currentCenter.latitude}_${_currentCenter.longitude}',
                              title: 'Pinned Location',
                              subtitle: _addressText,
                              fullAddress: _addressText,
                              latitude: _currentCenter.latitude,
                              longitude: _currentCenter.longitude,
                            );
                        Navigator.pop(context, result);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'CONFIRM THIS LOCATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
