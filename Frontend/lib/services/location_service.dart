import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationSuggestion {
  final String id;
  final String title;
  final String subtitle;
  final String fullAddress;
  final double latitude;
  final double longitude;
  final bool isCurrentLocation;

  LocationSuggestion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
    this.isCurrentLocation = false,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    final String displayName = json['display_name'] ?? '';
    final Map<String, dynamic> addr = (json['address'] is Map) ? Map<String, dynamic>.from(json['address']) : {};

    // Extract exact place name (building, landmark, road, suburb, or first part of display_name)
    String placeName = json['display_place']?.toString().trim() ?? '';
    if (placeName.isEmpty) {
      placeName = addr['name']?.toString().trim() ??
          addr['road']?.toString().trim() ??
          addr['suburb']?.toString().trim() ??
          addr['neighbourhood']?.toString().trim() ??
          addr['amenity']?.toString().trim() ??
          '';
    }

    List<String> rawParts = displayName.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (placeName.isEmpty && rawParts.isNotEmpty) {
      placeName = rawParts.first;
    }
    if (placeName.isEmpty) placeName = 'Location';

    // Build clean subtitle (city, state, country)
    String city = addr['city'] ?? addr['city_district'] ?? addr['town'] ?? addr['county'] ?? '';
    String state = addr['state'] ?? '';
    String suburb = addr['suburb'] ?? addr['neighbourhood'] ?? '';

    List<String> subParts = [];
    if (suburb.isNotEmpty && suburb.toLowerCase() != placeName.toLowerCase()) {
      subParts.add(suburb);
    }
    if (city.isNotEmpty && city.toLowerCase() != placeName.toLowerCase()) {
      subParts.add(city);
    }
    if (state.isNotEmpty && state.toLowerCase() != city.toLowerCase()) {
      subParts.add(state);
    }

    String cleanSubtitle = subParts.isNotEmpty ? subParts.join(', ') : (rawParts.length > 1 ? rawParts.sublist(1).take(2).join(', ') : 'Pakistan');

    // Build concise full address
    String cleanFullAddr = rawParts.take(4).join(', ');
    if (cleanFullAddr.isEmpty) cleanFullAddr = displayName;

    double parseCoord(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is double) return val;
      if (val is int) return val.toDouble();
      return double.tryParse(val.toString()) ?? fallback;
    }

    return LocationSuggestion(
      id: json['place_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: placeName,
      subtitle: cleanSubtitle,
      fullAddress: cleanFullAddr,
      latitude: parseCoord(json['lat'], 31.5204),
      longitude: parseCoord(json['lon'], 74.3587),
    );
  }
}

class LocationService {
  static const String apiKey = 'pk.215498a4e99268cde5c380624d981804';

  /// Get exact GPS coordinates of device inside Pakistan
  static Future<Position?> getCurrentGpsPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Autocomplete places bounded to Pakistan & biased towards current lat/lon if available
  static Future<List<LocationSuggestion>> searchPlaces(String query, {double? userLat, double? userLon}) async {
    if (query.trim().length < 2) return [];

    final String encodedQuery = Uri.encodeComponent(query.trim());
    
    // Proximity viewbox if user coordinates are available
    String viewboxParam = '';
    if (userLat != null && userLon != null) {
      double delta = 0.3; // ~30km box around user
      double minLon = userLon - delta;
      double minLat = userLat - delta;
      double maxLon = userLon + delta;
      double maxLat = userLat + delta;
      viewboxParam = '&viewbox=$minLon,$minLat,$maxLon,$maxLat&bounded=0';
    }

    final Uri url = Uri.parse(
      'https://api.locationiq.com/v1/autocomplete?key=$apiKey&q=$encodedQuery&countrycodes=pk&limit=10&format=json$viewboxParam',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => LocationSuggestion.fromJson(item)).toList();
      }
    } catch (e) {
      // Fallback
    }
    return [];
  }

  /// Reverse geocode exact (lat, lon) pin drop in Pakistan to precise address
  static Future<LocationSuggestion?> reverseGeocode(double lat, double lon) async {
    final Uri url = Uri.parse(
      'https://us1.locationiq.com/v1/reverse?key=$apiKey&lat=$lat&lon=$lon&format=json&addressdetails=1',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return LocationSuggestion.fromJson(data);
      }
    } catch (e) {
      // Fallback
    }

    return LocationSuggestion(
      id: 'custom_${lat.toStringAsFixed(5)}_${lon.toStringAsFixed(5)}',
      title: 'Pinned Location',
      subtitle: '(${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})',
      fullAddress: 'Location (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})',
      latitude: lat,
      longitude: lon,
    );
  }
}
