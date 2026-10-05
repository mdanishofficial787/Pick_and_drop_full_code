import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:ride_and_serve/constants/app_colors.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/location_map_picker_modal.dart';
import 'package:ride_and_serve/services/location_service.dart';
import 'package:ride_and_serve/services/ride_service.dart';

class HireDriverScreen extends StatefulWidget {
  final CustomerUser? user;

  const HireDriverScreen({super.key, this.user});

  @override
  State<HireDriverScreen> createState() => _HireDriverScreenState();
}

class _HireDriverScreenState extends State<HireDriverScreen> {
  // Theme Colors
  static const Color _primaryBlue = AppColors.primaryBlue;
  static const Color _screenBg = Color(0xFFF7F8FC);
  static const Color _cardBg = Colors.white;

  // Controllers
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropoffController = TextEditingController();

  // Date & Time State
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _timeToReach = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _offTime = const TimeOfDay(hour: 17, minute: 0);

  // LocationIQ & Map Selection State
  LocationSuggestion? _selectedPickupLocation;
  LocationSuggestion? _selectedDropoffLocation;

  List<LocationSuggestion> _pickupSuggestions = [];
  List<LocationSuggestion> _dropoffSuggestions = [];

  bool _isSearchingPickup = false;
  bool _isSearchingDropoff = false;

  bool _showPickupOverlay = false;
  bool _showDropoffOverlay = false;

  Timer? _pickupDebounce;
  Timer? _dropoffDebounce;

  double? _userGpsLat;
  double? _userGpsLon;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initUserGpsPosition();
  }

  Future<void> _initUserGpsPosition() async {
    final pos = await LocationService.getCurrentGpsPosition();
    if (pos != null && mounted) {
      setState(() {
        _userGpsLat = pos.latitude;
        _userGpsLon = pos.longitude;
      });
    }
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropoffDebounce?.cancel();
    _cnicController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LocationIQ & Map Picker Helpers
  // ---------------------------------------------------------------------------
  Future<void> _useCurrentGpsLocation({required bool isPickup}) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Detecting your GPS location...'), duration: Duration(seconds: 1)),
    );

    final pos = await LocationService.getCurrentGpsPosition();
    if (pos != null) {
      final res = await LocationService.reverseGeocode(pos.latitude, pos.longitude);
      if (res != null && mounted) {
        setState(() {
          if (isPickup) {
            _selectedPickupLocation = res;
            _pickupController.text = res.fullAddress;
            _showPickupOverlay = false;
          } else {
            _selectedDropoffLocation = res;
            _dropoffController.text = res.fullAddress;
            _showDropoffOverlay = false;
          }
        });
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get GPS location. Please check location permissions.')),
      );
    }
  }

  void _onPickupChanged(String query) {
    _pickupDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _pickupSuggestions = [];
        _showPickupOverlay = false;
        _isSearchingPickup = false;
      });
      return;
    }

    setState(() {
      _isSearchingPickup = true;
      _showPickupOverlay = true;
    });

    _pickupDebounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await LocationService.searchPlaces(query, userLat: _userGpsLat, userLon: _userGpsLon);
      if (mounted) {
        setState(() {
          _pickupSuggestions = suggestions;
          _isSearchingPickup = false;
          _showPickupOverlay = true;
        });
      }
    });
  }

  void _onDropoffChanged(String query) {
    _dropoffDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _dropoffSuggestions = [];
        _showDropoffOverlay = false;
        _isSearchingDropoff = false;
      });
      return;
    }

    setState(() {
      _isSearchingDropoff = true;
      _showDropoffOverlay = true;
    });

    _dropoffDebounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await LocationService.searchPlaces(query, userLat: _userGpsLat, userLon: _userGpsLon);
      if (mounted) {
        setState(() {
          _dropoffSuggestions = suggestions;
          _isSearchingDropoff = false;
          _showDropoffOverlay = true;
        });
      }
    });
  }

  Future<void> _openMapPicker({required bool isPickup}) async {
    LatLng? targetPos;
    final LocationSuggestion? savedLoc = isPickup ? _selectedPickupLocation : _selectedDropoffLocation;
    final String typedAddr = isPickup ? _pickupController.text.trim() : _dropoffController.text.trim();

    if (savedLoc != null) {
      targetPos = LatLng(savedLoc.latitude, savedLoc.longitude);
    } else if (typedAddr.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Locating address on map...'), duration: Duration(seconds: 1)),
      );
      final searchResults = await LocationService.searchPlaces(typedAddr, userLat: _userGpsLat, userLon: _userGpsLon);
      if (searchResults.isNotEmpty) {
        targetPos = LatLng(searchResults.first.latitude, searchResults.first.longitude);
      }
    }

    if (targetPos == null && _userGpsLat != null && _userGpsLon != null) {
      targetPos = LatLng(_userGpsLat!, _userGpsLon!);
    }

    if (!mounted) return;

    final LocationSuggestion? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => LocationMapPickerModal(
          title: isPickup ? 'Select Pickup Location' : 'Select Drop-off Location',
          initialPosition: targetPos ?? const LatLng(31.5204, 74.3587),
          initialAddress: typedAddr.isNotEmpty ? typedAddr : null,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (isPickup) {
          _selectedPickupLocation = result;
          _pickupController.text = result.fullAddress;
          _showPickupOverlay = false;
        } else {
          _selectedDropoffLocation = result;
          _dropoffController.text = result.fullAddress;
          _showDropoffOverlay = false;
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Date & Time Selection
  // ---------------------------------------------------------------------------
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryBlue),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTimeToReach() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeToReach,
    );
    if (picked != null) {
      setState(() => _timeToReach = picked);
    }
  }

  Future<void> _selectOffTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _offTime,
    );
    if (picked != null) {
      setState(() => _offTime = picked);
    }
  }

  String _formatTime(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  // ---------------------------------------------------------------------------
  // Submit Request
  // ---------------------------------------------------------------------------
  Future<void> _handleSubmitRequest() async {
    final cnic = _cnicController.text.trim();
    final pickup = _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();

    if (cnic.isEmpty || cnic.length < 13) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Customer CNIC (e.g. 12345-1234567-1)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (pickup.isEmpty || dropoff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both pickup and drop-off locations'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final rawPhone = widget.user?.phoneNumber?.trim();
      final rawName = widget.user?.fullName.trim();
      final customerName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Customer User';
      final customerPhone = (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : '+923001234567';
      final customerEmail = widget.user?.email ?? 'customer@example.com';

      final bookingDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final reachTimeStr = _formatTime(_timeToReach);
      final offTimeStr = _formatTime(_offTime);

      final response = await RideService.submitDriverHireRequest(
        customerName: customerName,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
        cnic: cnic,
        bookingDate: bookingDateStr,
        pickupLocation: pickup,
        dropoffLocation: dropoff,
        timeToReach: reachTimeStr,
        offTime: offTimeStr,
        fare: 3500,
        customerId: widget.user?.id,
      );

      if (!mounted) return;

      if (response.success) {
        final reqId = response.requestId ?? 'HDR-SUBMITTED';
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 35,
                      backgroundColor: Color(0xFFE8F5E9),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 50),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Driver Hiring Submitted!',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        reqId,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Your driver hiring request has been dispatched to the Admin Console.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        String msg = response.message;
        if (msg.contains('Cannot POST') || msg.contains('<!DOCTYPE html>')) {
          msg = 'Backend server needs to be restarted. Please restart the backend server (npm start) to activate the /api/driver-hire route.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error hiring driver: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Hire Driver',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Column(
                  children: [
                    Text(
                      'Hire a Professional Driver',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Complete the form below to schedule your round-trip driver.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Card 1: CNIC Input Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Customer CNIC *'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _cnicController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [_CnicInputFormatter()],
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: '12345-1234567-1',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                          prefixIcon: Icon(Icons.badge_outlined, color: Color(0xFF64748B), size: 20),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Card 2: Calendar Select Date Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: _primaryBlue),
                        const SizedBox(width: 8),
                        _buildLabel('Select Date *'),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Interactive Calendar Display Card
                    InkWell(
                      onTap: _selectDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _primaryBlue.withValues(alpha: 0.5), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Tap to change booking date',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _primaryBlue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_calendar_rounded, color: _primaryBlue, size: 22),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Card 3: Locations & Times Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pickup Location
                    _buildLocationInput(
                      label: 'Pickup Location *',
                      controller: _pickupController,
                      hint: 'Enter pickup address',
                      icon: Icons.location_on_outlined,
                      iconColor: _primaryBlue,
                      onChanged: _onPickupChanged,
                      onMapTap: () => _openMapPicker(isPickup: true),
                    ),

                    if (_showPickupOverlay)
                      _buildAutocompleteDropdown(
                        suggestions: _pickupSuggestions,
                        isLoading: _isSearchingPickup,
                        isPickup: true,
                        onSelect: (suggestion) {
                          setState(() {
                            _selectedPickupLocation = suggestion;
                            _pickupController.text = suggestion.fullAddress;
                            _showPickupOverlay = false;
                          });
                        },
                      ),

                    const SizedBox(height: 12),

                    // Time To Reach
                    _buildLabel('Time To Reach *'),
                    const SizedBox(height: 6),
                    _buildClickableInput(
                      icon: Icons.access_time_rounded,
                      text: _formatTime(_timeToReach),
                      hint: 'e.g 08:30 am',
                      onTap: _selectTimeToReach,
                    ),

                    const SizedBox(height: 14),

                    // Drop-off Location
                    _buildLocationInput(
                      label: 'Drop-off Location *',
                      controller: _dropoffController,
                      hint: 'Enter drop-off address',
                      icon: Icons.near_me_outlined,
                      iconColor: Colors.redAccent,
                      onChanged: _onDropoffChanged,
                      onMapTap: () => _openMapPicker(isPickup: false),
                    ),

                    if (_showDropoffOverlay)
                      _buildAutocompleteDropdown(
                        suggestions: _dropoffSuggestions,
                        isLoading: _isSearchingDropoff,
                        isPickup: false,
                        onSelect: (suggestion) {
                          setState(() {
                            _selectedDropoffLocation = suggestion;
                            _dropoffController.text = suggestion.fullAddress;
                            _showDropoffOverlay = false;
                          });
                        },
                      ),

                    const SizedBox(height: 12),

                    // Off Time
                    _buildLabel('Off Time *'),
                    const SizedBox(height: 6),
                    _buildClickableInput(
                      icon: Icons.access_time_rounded,
                      text: _formatTime(_offTime),
                      hint: 'e.g 05:00 pm',
                      onTap: _selectOffTime,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SUBMIT REQUEST BUTTON
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text(
                          'SUBMIT REQUEST',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------
  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        color: Color(0xFF64748B),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildClickableInput({
    required IconData icon,
    required String text,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              text.isNotEmpty ? text : hint,
              style: TextStyle(
                fontSize: 14,
                fontWeight: text.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                color: text.isNotEmpty ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
              ),
            ),
            Icon(icon, color: const Color(0xFF64748B), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInput({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<String> onChanged,
    required VoidCallback onMapTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
              InkWell(
                onTap: onMapTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Row(
                    children: [
                      Icon(Icons.map_outlined, size: 14, color: iconColor),
                      const SizedBox(width: 3),
                      Text(
                        'Map',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: iconColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: Icon(Icons.close, size: 14, color: Colors.black45),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutocompleteDropdown({
    required List<LocationSuggestion> suggestions,
    required bool isLoading,
    required bool isPickup,
    required ValueChanged<LocationSuggestion> onSelect,
  }) {
    final int totalCount = suggestions.length + 1;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isLoading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryBlue)),
                  SizedBox(width: 10),
                  Text('Searching precise location in Pakistan...', style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: totalCount,
              separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const CircleAvatar(
                      radius: 13,
                      backgroundColor: Color(0xFFE0F2FE),
                      child: Icon(Icons.my_location_rounded, size: 15, color: _primaryBlue),
                    ),
                    title: const Text(
                      'Use Current Location',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
                    ),
                    subtitle: const Text(
                      'Detect exact GPS location via satellite',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    onTap: () => _useCurrentGpsLocation(isPickup: isPickup),
                  );
                }

                final item = suggestions[i - 1];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.location_on_outlined, size: 18, color: _primaryBlue),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelect(item),
                );
              },
            ),
    );
  }
}

// CNIC Input Formatter (12345-1234567-1)
class _CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final StringBuffer formatted = StringBuffer();

    for (int i = 0; i < digitsOnly.length && i < 13; i++) {
      if (i == 5 || i == 12) {
        formatted.write('-');
      }
      formatted.write(digitsOnly[i]);
    }

    final String resultStr = formatted.toString();
    return TextEditingValue(
      text: resultStr,
      selection: TextSelection.collapsed(offset: resultStr.length),
    );
  }
}
