import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/location_map_picker_modal.dart';
import 'package:ride_and_serve/screens/customer/travel_tourism_screen.dart';
import 'package:ride_and_serve/services/auth_service.dart';
import 'package:ride_and_serve/services/location_service.dart';
import 'package:ride_and_serve/services/ride_service.dart';

class SchedulePickupScreen extends StatefulWidget {
  final CustomerUser? user;

  const SchedulePickupScreen({super.key, this.user});

  @override
  State<SchedulePickupScreen> createState() => _SchedulePickupScreenState();
}

class _SchedulePickupScreenState extends State<SchedulePickupScreen> {
  CustomerUser? _currentUser;

  // Primary Theme Colors matching exact UI in screenshot
  static const Color _navyBlue = Color(0xFF0F2B5B);
  static const Color _screenBg = Color(0xFFF4F7FC);
  static const Color _unselectedPillBg = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFCBD5E1);

  // Form State
  String _rideType = 'One Way'; // 'One Way' or 'Two Way'
  String _vehicleType = 'Sedan Executive'; // 'Sedan Executive', 'Sedan', 'SUV / Crossover'
  String _genderPreference = 'Both'; // 'Male Only', 'Female Only', 'Both'
  String _acPreference = 'AC'; // 'AC' or 'Non-AC'

  // Locations Controllers & Search State
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _returnPickupController = TextEditingController();
  final _returnDropoffController = TextEditingController();

  final _fareController = TextEditingController();
  final _notesController = TextEditingController();

  LocationSuggestion? _selectedPickupLocation;
  LocationSuggestion? _selectedDropoffLocation;
  LocationSuggestion? _selectedReturnPickupLocation;
  LocationSuggestion? _selectedReturnDropoffLocation;

  List<LocationSuggestion> _pickupSuggestions = [];
  List<LocationSuggestion> _dropoffSuggestions = [];
  List<LocationSuggestion> _returnPickupSuggestions = [];
  List<LocationSuggestion> _returnDropoffSuggestions = [];

  bool _isSearchingPickup = false;
  bool _isSearchingDropoff = false;
  bool _isSearchingReturnPickup = false;
  bool _isSearchingReturnDropoff = false;

  bool _showPickupOverlay = false;
  bool _showDropoffOverlay = false;
  bool _showReturnPickupOverlay = false;
  bool _showReturnDropoffOverlay = false;

  Timer? _pickupDebounce;
  Timer? _dropoffDebounce;
  Timer? _returnPickupDebounce;
  Timer? _returnDropoffDebounce;

  double? _userGpsLat;
  double? _userGpsLon;

  // Dates & Times
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _timeToReach = const TimeOfDay(hour: 10, minute: 30);

  DateTime _returnDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _returnTime = const TimeOfDay(hour: 17, minute: 0);

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
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

  Future<void> _loadUser() async {
    if (widget.user != null) {
      _currentUser = widget.user;
    } else {
      _currentUser = await AuthService.getCurrentUser();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropoffDebounce?.cancel();
    _returnPickupDebounce?.cancel();
    _returnDropoffDebounce?.cancel();

    _pickupController.dispose();
    _dropoffController.dispose();
    _returnPickupController.dispose();
    _returnDropoffController.dispose();

    _fareController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Autocomplete Search Handlers
  // ---------------------------------------------------------------------------
  void _onSearchLocation(String query, int fieldIndex) {
    if (fieldIndex == 0) {
      _pickupDebounce?.cancel();
      _pickupDebounce = Timer(const Duration(milliseconds: 350), () => _performSearch(query, fieldIndex));
    } else if (fieldIndex == 1) {
      _dropoffDebounce?.cancel();
      _dropoffDebounce = Timer(const Duration(milliseconds: 350), () => _performSearch(query, fieldIndex));
    } else if (fieldIndex == 2) {
      _returnPickupDebounce?.cancel();
      _returnPickupDebounce = Timer(const Duration(milliseconds: 350), () => _performSearch(query, fieldIndex));
    } else if (fieldIndex == 3) {
      _returnDropoffDebounce?.cancel();
      _returnDropoffDebounce = Timer(const Duration(milliseconds: 350), () => _performSearch(query, fieldIndex));
    }
  }

  Future<void> _performSearch(String query, int fieldIndex) async {
    if (query.trim().length < 2) {
      setState(() {
        if (fieldIndex == 0) {
          _pickupSuggestions = [];
          _showPickupOverlay = false;
        } else if (fieldIndex == 1) {
          _dropoffSuggestions = [];
          _showDropoffOverlay = false;
        } else if (fieldIndex == 2) {
          _returnPickupSuggestions = [];
          _showReturnPickupOverlay = false;
        } else if (fieldIndex == 3) {
          _returnDropoffSuggestions = [];
          _showReturnDropoffOverlay = false;
        }
      });
      return;
    }

    setState(() {
      if (fieldIndex == 0) _isSearchingPickup = true;
      if (fieldIndex == 1) _isSearchingDropoff = true;
      if (fieldIndex == 2) _isSearchingReturnPickup = true;
      if (fieldIndex == 3) _isSearchingReturnDropoff = true;
    });

    final results = await LocationService.searchPlaces(
      query,
      userLat: _userGpsLat,
      userLon: _userGpsLon,
    );

    if (mounted) {
      setState(() {
        if (fieldIndex == 0) {
          _pickupSuggestions = results;
          _showPickupOverlay = results.isNotEmpty;
          _isSearchingPickup = false;
        } else if (fieldIndex == 1) {
          _dropoffSuggestions = results;
          _showDropoffOverlay = results.isNotEmpty;
          _isSearchingDropoff = false;
        } else if (fieldIndex == 2) {
          _returnPickupSuggestions = results;
          _showReturnPickupOverlay = results.isNotEmpty;
          _isSearchingReturnPickup = false;
        } else if (fieldIndex == 3) {
          _returnDropoffSuggestions = results;
          _showReturnDropoffOverlay = results.isNotEmpty;
          _isSearchingReturnDropoff = false;
        }
      });
    }
  }

  // Open Map Picker Modal
  Future<void> _openMapPicker(int fieldIndex) async {
    LatLng? targetPos;
    String typedAddr = '';

    if (fieldIndex == 0) {
      if (_selectedPickupLocation != null) {
        targetPos = LatLng(_selectedPickupLocation!.latitude, _selectedPickupLocation!.longitude);
      }
      typedAddr = _pickupController.text.trim();
    } else if (fieldIndex == 1) {
      if (_selectedDropoffLocation != null) {
        targetPos = LatLng(_selectedDropoffLocation!.latitude, _selectedDropoffLocation!.longitude);
      }
      typedAddr = _dropoffController.text.trim();
    } else if (fieldIndex == 2) {
      if (_selectedReturnPickupLocation != null) {
        targetPos = LatLng(_selectedReturnPickupLocation!.latitude, _selectedReturnPickupLocation!.longitude);
      }
      typedAddr = _returnPickupController.text.trim();
    } else if (fieldIndex == 3) {
      if (_selectedReturnDropoffLocation != null) {
        targetPos = LatLng(_selectedReturnDropoffLocation!.latitude, _selectedReturnDropoffLocation!.longitude);
      }
      typedAddr = _returnDropoffController.text.trim();
    }

    final titles = [
      'Select Pickup Location',
      'Select Drop-off Location',
      'Select Return Pickup Location',
      'Select Return Drop-off Location'
    ];

    final LocationSuggestion? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => LocationMapPickerModal(
          title: titles[fieldIndex],
          initialPosition: targetPos ?? LatLng(_userGpsLat ?? 31.5204, _userGpsLon ?? 74.3587),
          initialAddress: typedAddr.isNotEmpty ? typedAddr : null,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (fieldIndex == 0) {
          _selectedPickupLocation = result;
          _pickupController.text = result.fullAddress;
          _showPickupOverlay = false;
        } else if (fieldIndex == 1) {
          _selectedDropoffLocation = result;
          _dropoffController.text = result.fullAddress;
          _showDropoffOverlay = false;
        } else if (fieldIndex == 2) {
          _selectedReturnPickupLocation = result;
          _returnPickupController.text = result.fullAddress;
          _showReturnPickupOverlay = false;
        } else if (fieldIndex == 3) {
          _selectedReturnDropoffLocation = result;
          _returnDropoffController.text = result.fullAddress;
          _showReturnDropoffOverlay = false;
        }
      });
    }
  }

  // Pick Date & Time
  Future<void> _selectDate({bool isReturn = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isReturn ? _returnDate : _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: _navyBlue)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isReturn) {
          _returnDate = picked;
        } else {
          _selectedDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime({bool isReturn = false}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isReturn ? _returnTime : _timeToReach,
    );
    if (picked != null) {
      setState(() {
        if (isReturn) {
          _returnTime = picked;
        } else {
          _timeToReach = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  // Submit Schedule Ride Request
  Future<void> _handleSubmitScheduleRide() async {
    if (_pickupController.text.trim().isEmpty || _dropoffController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both Pickup and Drop-off locations'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_rideType == 'Two Way' &&
        (_returnPickupController.text.trim().isEmpty || _returnDropoffController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter return pickup and drop-off locations for Two Way ride'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final rawPhone = _currentUser?.phoneNumber?.trim();
      final rawName = _currentUser?.fullName.trim();
      final passengerName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Customer User';
      final passengerPhone = (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : '+923001234567';
      final passengerEmail = _currentUser?.email ?? 'customer@example.com';

      final startingFromStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final timeReachStr = _formatTime(_timeToReach);

      final num fareValue = num.tryParse(_fareController.text.replaceAll(',', '').trim()) ?? (_rideType == 'Two Way' ? 12000 : 7500);

      final customScheduleData = {
        'rideType': _rideType,
        'vehicleType': _vehicleType,
        'genderPreference': _genderPreference,
        'acPreference': _acPreference,
        'selectedDays': [DateFormat('E').format(_selectedDate)],
        'returnPickupLocation': _rideType == 'Two Way' ? _returnPickupController.text.trim() : null,
        'returnDropoffLocation': _rideType == 'Two Way' ? _returnDropoffController.text.trim() : null,
        'returnDate': _rideType == 'Two Way' ? DateFormat('yyyy-MM-dd').format(_returnDate) : null,
        'returnTime': _rideType == 'Two Way' ? _formatTime(_returnTime) : null,
      };

      final response = await RideService.bookScheduleRide(
        passengerName: passengerName,
        passengerPhone: passengerPhone,
        passengerEmail: passengerEmail,
        pickupLocation: _pickupController.text.trim(),
        dropoffLocation: _dropoffController.text.trim(),
        startingFrom: startingFromStr,
        timeToReach: timeReachStr,
        timeToLeave: _rideType == 'Two Way' ? _formatTime(_returnTime) : '05:00 PM',
        rideType: _rideType,
        vehicleType: _vehicleType,
        acPreference: _acPreference,
        genderPreference: _genderPreference,
        fare: fareValue.toInt(),
        notes: _notesController.text.trim(),
        customerId: _currentUser?.id,
        customSchedule: customScheduleData,
      );

      if (!mounted) return;

      if (response.success) {
        final reqId = response.requestId ?? 'SCH-9001';
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text('RIDE SCHEDULED!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Text('Request ID: $reqId', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navyBlue)),
                  const SizedBox(height: 12),
                  const Text(
                    'Your scheduled ride request has been sent to Passenger Request Queue in Ride Dispatch console.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navyBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      child: const Text('BACK TO DASHBOARD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        backgroundColor: _navyBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schedule Ride',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              'Book a ride for your convenience.',
              style: TextStyle(fontSize: 11, color: Color(0xFF93C5FD), fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------------------------------------------------------
              // Banner Button: Travel & Tourism
              // ---------------------------------------------------------------
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => TravelAndTourismScreen(user: _currentUser),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.card_travel_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text('|', style: TextStyle(color: Colors.white54, fontSize: 18)),
                      const SizedBox(width: 12),
                      const Text(
                        'Travel & Tourism',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 24),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Pickup & Drop Location Card (Going)
              _buildLocationCard(
                fromController: _pickupController,
                toController: _dropoffController,
                fromIndex: 0,
                toIndex: 1,
                fromOverlay: _showPickupOverlay,
                toOverlay: _showDropoffOverlay,
                fromSuggestions: _pickupSuggestions,
                toSuggestions: _dropoffSuggestions,
                fromSearching: _isSearchingPickup,
                toSearching: _isSearchingDropoff,
              ),

              if (_rideType == 'Two Way') ...[
                const SizedBox(height: 12),
                _buildLocationCard(
                  fromController: _returnPickupController,
                  toController: _returnDropoffController,
                  fromIndex: 2,
                  toIndex: 3,
                  fromOverlay: _showReturnPickupOverlay,
                  toOverlay: _showReturnDropoffOverlay,
                  fromSuggestions: _returnPickupSuggestions,
                  toSuggestions: _returnDropoffSuggestions,
                  fromSearching: _isSearchingReturnPickup,
                  toSearching: _isSearchingReturnDropoff,
                  title: 'Return Trip Locations',
                ),
              ],

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // Select Date & Select Time Pickers
              // ---------------------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.autorenew_rounded, size: 14, color: _navyBlue),
                            SizedBox(width: 4),
                            Text('Select Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _selectDate(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month_rounded, color: _navyBlue, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd MMM yyyy').format(_selectedDate),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.autorenew_rounded, size: 14, color: _navyBlue),
                            SizedBox(width: 4),
                            Text('Select Time', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _selectTime(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time_rounded, color: _navyBlue, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTime(_timeToReach),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // Ride Type (One Way / Two Way)
              // ---------------------------------------------------------------
              const Text('Ride Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'One Way',
                      icon: Icons.radio_button_checked_rounded,
                      isSelected: _rideType == 'One Way',
                      onTap: () => setState(() => _rideType = 'One Way'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'Two Way',
                      icon: Icons.radio_button_unchecked_rounded,
                      isSelected: _rideType == 'Two Way',
                      onTap: () => setState(() => _rideType = 'Two Way'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // Vehicle Type Dropdown
              // ---------------------------------------------------------------
              const Text('Vehicle Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _vehicleType,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _navyBlue),
                    items: ['Sedan Executive', 'Sedan', 'SUV / Crossover'].map((v) {
                      return DropdownMenuItem<String>(
                        value: v,
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car_rounded, color: _navyBlue, size: 20),
                            const SizedBox(width: 10),
                            Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _vehicleType = val);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // Gender Preference
              // ---------------------------------------------------------------
              const Text('Gender Preference', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'Male Only',
                      isSelected: _genderPreference == 'Male Only',
                      onTap: () => setState(() => _genderPreference = 'Male Only'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'Female Only',
                      isSelected: _genderPreference == 'Female Only',
                      onTap: () => setState(() => _genderPreference = 'Female Only'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'Both',
                      isSelected: _genderPreference == 'Both',
                      onTap: () => setState(() => _genderPreference = 'Both'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // AC Preference
              // ---------------------------------------------------------------
              const Text('AC Preference', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'AC',
                      icon: Icons.ac_unit_rounded,
                      isSelected: _acPreference == 'AC',
                      onTap: () => setState(() => _acPreference = 'AC'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'Non-AC',
                      isSelected: _acPreference == 'Non-AC',
                      onTap: () => setState(() => _acPreference = 'Non-AC'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ---------------------------------------------------------------
              // Fair Section
              // ---------------------------------------------------------------
              Row(
                children: [
                  const Text('Fair ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _fareController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Enter Fare',
                        suffixText: 'PKR',
                        suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                        fillColor: Colors.white,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _borderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _navyBlue, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFBAE6FD)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_rounded, color: Color(0xFF0284C7), size: 18),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'The final fare may increase or decrease by 1k - 5k depending on the route, location and demand.',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF0369A1), height: 1.25),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ---------------------------------------------------------------
              // Bottom Action Button: Search Available Rides / Send Request
              // ---------------------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _handleSubmitScheduleRide,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('|', style: TextStyle(color: Colors.white54, fontSize: 18)),
                            SizedBox(width: 8),
                            Text(
                              'Search Available Rides',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI Helper Widgets
  // ---------------------------------------------------------------------------
  Widget _buildLocationCard({
    required TextEditingController fromController,
    required TextEditingController toController,
    required int fromIndex,
    required int toIndex,
    required bool fromOverlay,
    required bool toOverlay,
    required List<LocationSuggestion> fromSuggestions,
    required List<LocationSuggestion> toSuggestions,
    required bool fromSearching,
    required bool toSearching,
    String? title,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navyBlue)),
            const SizedBox(height: 10),
          ],
          _buildLocationInput(
            controller: fromController,
            label: 'From',
            hint: 'Enter pickup location',
            icon: Icons.place_rounded,
            index: fromIndex,
            overlay: fromOverlay,
            suggestions: fromSuggestions,
            isSearching: fromSearching,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          _buildLocationInput(
            controller: toController,
            label: 'To',
            hint: 'Enter drop location',
            icon: Icons.place_rounded,
            index: toIndex,
            overlay: toOverlay,
            suggestions: toSuggestions,
            isSearching: toSearching,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required int index,
    required bool overlay,
    required List<LocationSuggestion> suggestions,
    required bool isSearching,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _navyBlue, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (val) => _onSearchLocation(val, index),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            fillColor: _unselectedPillBg,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.chevron_right_rounded, color: _navyBlue),
              onPressed: () => _openMapPicker(index),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _navyBlue, width: 1.5)),
          ),
        ),
        if (overlay && suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (ctx, idx) {
                final item = suggestions[idx];
                return ListTile(
                  dense: true,
                  title: Text(item.fullAddress, style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    setState(() {
                      controller.text = item.fullAddress;
                      if (index == 0) {
                        _selectedPickupLocation = item;
                        _showPickupOverlay = false;
                      } else if (index == 1) {
                        _selectedDropoffLocation = item;
                        _showDropoffOverlay = false;
                      } else if (index == 2) {
                        _selectedReturnPickupLocation = item;
                        _showReturnPickupOverlay = false;
                      } else if (index == 3) {
                        _selectedReturnDropoffLocation = item;
                        _showReturnDropoffOverlay = false;
                      }
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSelectablePill({
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? _navyBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? _navyBlue : _borderColor, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : (icon ?? Icons.radio_button_unchecked_rounded),
              color: isSelected ? Colors.white : const Color(0xFF64748B),
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF0F172A),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
