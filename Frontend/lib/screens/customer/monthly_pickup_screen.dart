import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/location_map_picker_modal.dart';
import 'package:ride_and_serve/services/auth_service.dart';
import 'package:ride_and_serve/services/location_service.dart';
import 'package:ride_and_serve/services/ride_service.dart';

class MonthlyPickupScreen extends StatefulWidget {
  final CustomerUser? user;

  const MonthlyPickupScreen({super.key, this.user});

  @override
  State<MonthlyPickupScreen> createState() => _MonthlyPickupScreenState();
}

class _MonthlyPickupScreenState extends State<MonthlyPickupScreen> {
  CustomerUser? _currentUser;

  // Primary Theme Colors matching exact UI in screenshot
  static const Color _navyBlue = Color(0xFF0F2B5B);
  static const Color _screenBg = Color(0xFFF4F7FC);
  static const Color _unselectedPillBg = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFCBD5E1);

  // Form State
  String _tripType = 'One Way'; // 'One Way' or 'Two Way'
  String _serviceType = 'Separate'; // 'Separate' (Different vehicles) or 'Combined' (Same vehicle)
  String _vehicleType = 'Sedan Executive'; // 'Sedan Executive', 'Sedan', 'SUV / Crossover'
  String _genderPreference = 'Both'; // 'Male Only', 'Female Only', 'Both'
  String _acPreference = 'AC'; // 'AC' or 'Non-AC'
  int _passengersCount = 2; // '1', '2', '3', '4' (Default 2 as shown in screenshot)

  // Days Selection
  List<String> _selectedDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']; // default Mon-Fri
  String _schedulePreset = 'Mon - Fri'; // 'Mon - Fri', 'Mon - Sat', 'Custom'

  // Locations Controllers & LocationIQ State
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _returnPickupController = TextEditingController();
  final _returnDropoffController = TextEditingController();

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
  TimeOfDay _timeToReach = const TimeOfDay(hour: 8, minute: 30);
  final TimeOfDay _timeToLeave = const TimeOfDay(hour: 17, minute: 0);

  DateTime _returnDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _returnTime = const TimeOfDay(hour: 17, minute: 0);

  final _fareController = TextEditingController();
  final _notesController = TextEditingController();

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
          initialPosition: targetPos ?? const LatLng(33.6844, 73.0479),
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

  // Date & Time Pickers
  Future<void> _selectDate({bool isReturn = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isReturn ? _returnDate : _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _navyBlue),
          ),
          child: child!,
        );
      },
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

  // ---------------------------------------------------------------------------
  // Submit Request Handler
  // ---------------------------------------------------------------------------
  Future<void> _handleSubmitRide() async {
    if (_pickupController.text.trim().isEmpty || _dropoffController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter pickup and drop-off locations'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_tripType == 'Two Way' &&
        (_returnPickupController.text.trim().isEmpty || _returnDropoffController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter return pickup and drop-off locations for Two Way trip'),
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
      final timeLeaveStr = _formatTime(_timeToLeave);

      final num fareValue = (_tripType == 'Two Way') ? 12000 : 9500;

      final customScheduleData = {
        'tripType': _tripType,
        'serviceType': _serviceType,
        'vehicleType': _vehicleType,
        'genderPreference': _genderPreference,
        'acPreference': _acPreference,
        'passengersCount': _passengersCount,
        'selectedDays': _selectedDays,
        'schedulePreset': _schedulePreset,
        'returnPickupLocation': _tripType == 'Two Way' ? _returnPickupController.text.trim() : null,
        'returnDropoffLocation': _tripType == 'Two Way' ? _returnDropoffController.text.trim() : null,
        'returnDate': _tripType == 'Two Way' ? DateFormat('yyyy-MM-dd').format(_returnDate) : null,
        'returnTime': _tripType == 'Two Way' ? _formatTime(_returnTime) : null,
      };

      final response = await RideService.bookMonthlyRide(
        passengerName: passengerName,
        passengerPhone: passengerPhone,
        passengerEmail: passengerEmail,
        pickupLocation: _pickupController.text.trim(),
        dropoffLocation: _dropoffController.text.trim(),
        startingFrom: startingFromStr,
        timeToReach: timeReachStr,
        timeToLeave: timeLeaveStr,
        scheduleType: _schedulePreset,
        scheduleTime: timeReachStr,
        customSchedule: customScheduleData,
        vehicleTypeSelection: _serviceType,
        seatingArrangement: _vehicleType,
        vehicleType: _vehicleType,
        acPreference: _acPreference,
        passengersCount: _passengersCount,
        fare: fareValue.toInt(),
        notes: _notesController.text.trim(),
        customerId: _currentUser?.id,
        tripType: _tripType,
        genderPreference: _genderPreference,
      );

      if (!mounted) return;

      if (response.success) {
        final reqId = response.requestId ?? 'REQ-MONTHLY';
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
                  const Text('BOOKING SUBMITTED!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Text('Request ID: $reqId', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navyBlue)),
                  const SizedBox(height: 12),
                  const Text(
                    'Your monthly pickup booking request has been sent to Ride Dispatch. Admin will assign a verified driver shortly.',
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
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Pick & Drop',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            Text(
              _tripType == 'One Way'
                  ? 'Choose your ride preferences and tell us where you want to go.'
                  : 'Add your pick-up and drop-off locations for both legs of the trip.',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.normal),
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
              // SECTION 1. Trip Type (One Way vs Two Way Toggle Pills)
              // ---------------------------------------------------------------
              _buildSectionHeader(number: '1', title: 'Trip Type', icon: Icons.location_on_rounded),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'One Way',
                      icon: Icons.radio_button_checked_rounded,
                      isSelected: _tripType == 'One Way',
                      onTap: () => setState(() => _tripType = 'One Way'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSelectablePill(
                      label: 'Two Way',
                      icon: Icons.radio_button_unchecked_rounded,
                      isSelected: _tripType == 'Two Way',
                      onTap: () => setState(() => _tripType = 'Two Way'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Conditional Views for One Way vs Two Way
              if (_tripType == 'One Way') ...[
                // -------------------------------------------------------------
                // SECTION 2. Pickup & Drop Location (One Way)
                // -------------------------------------------------------------
                _buildSectionHeader(number: '2', title: 'Pickup & Drop Location', icon: Icons.place_rounded),
                const SizedBox(height: 10),
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

                const SizedBox(height: 20),

                // -------------------------------------------------------------
                // SECTION: Select Your Days
                // -------------------------------------------------------------
                _buildSectionHeader(number: '', title: 'Select Your Days', icon: Icons.calendar_month_rounded),
                const SizedBox(height: 10),
                // Individual day chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) {
                    final isSelected = _selectedDays.contains(day);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedDays.remove(day);
                          } else {
                            _selectedDays.add(day);
                          }
                          final monFri = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
                          final monSat = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                          if (_listEquals(_selectedDays, monFri)) {
                            _schedulePreset = 'Mon - Fri';
                          } else if (_listEquals(_selectedDays, monSat)) {
                            _schedulePreset = 'Mon - Sat';
                          } else {
                            _schedulePreset = 'Custom';
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? _navyBlue : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? _navyBlue : _borderColor),
                        ),
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                // Preset buttons
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
                            _schedulePreset = 'Mon - Fri';
                          });
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _schedulePreset == 'Mon - Fri' ? _navyBlue : Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: _schedulePreset == 'Mon - Fri' ? _navyBlue : _borderColor),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Monday \u2013 Friday',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _schedulePreset == 'Mon - Fri' ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                            _schedulePreset = 'Mon - Sat';
                          });
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _schedulePreset == 'Mon - Sat' ? _navyBlue : Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: _schedulePreset == 'Mon - Sat' ? _navyBlue : _borderColor),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Monday \u2013 Saturday',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _schedulePreset == 'Mon - Sat' ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _schedulePreset = 'Custom';
                        });
                      },
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _schedulePreset == 'Custom' ? _navyBlue : Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: _schedulePreset == 'Custom' ? _navyBlue : _borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.settings_rounded, size: 14, color: _schedulePreset == 'Custom' ? Colors.white : const Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              'Custom',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _schedulePreset == 'Custom' ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // -------------------------------------------------------------
                // SECTION 3. Ride Options (Service, Vehicle, Gender, AC)
                // -------------------------------------------------------------
                _buildSectionHeader(number: '3', title: 'Ride Options', icon: Icons.directions_car_rounded),
                const SizedBox(height: 12),

                // Service Type (Separate vs Combined)
                Row(
                  children: [
                    const Text('Service Type ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailedPill(
                        title: 'Separate',
                        subtitle: 'Different vehicles for male and female',
                        isSelected: _serviceType == 'Separate',
                        onTap: () => setState(() => _serviceType = 'Separate'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDetailedPill(
                        title: 'Combined',
                        subtitle: 'Same vehicle for all passengers',
                        isSelected: _serviceType == 'Combined',
                        onTap: () => setState(() => _serviceType = 'Combined'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Vehicle Type & Seats
                const Text('Vehicle Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                if (_serviceType == 'Combined') ...[
                  Row(
                    children: [
                      Expanded(
                        child: _buildSelectablePill(
                          label: 'Sedan',
                          icon: Icons.directions_car_rounded,
                          isSelected: _vehicleType == 'Sedan' || _vehicleType == 'Sedan Executive',
                          onTap: () => setState(() => _vehicleType = 'Sedan'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSelectablePill(
                          label: 'SUV',
                          icon: Icons.directions_car_rounded,
                          isSelected: _vehicleType == 'SUV' || _vehicleType == 'SUV / Crossover',
                          onTap: () => setState(() => _vehicleType = 'SUV'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Seats / Passengers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [1, 2, 3, 4].map((cnt) {
                            final isSel = _passengersCount == cnt;
                            return InkWell(
                              onTap: () => setState(() => _passengersCount = cnt),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 44,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isSel ? _navyBlue : _unselectedPillBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isSel ? _navyBlue : _borderColor),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$cnt',
                                  style: TextStyle(
                                    color: isSel ? Colors.white : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      _buildCarSeatVisual(_passengersCount),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: ['Sedan Executive', 'Sedan', 'SUV / Crossover'].contains(_vehicleType) ? _vehicleType : 'Sedan Executive',
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
                ],

                const SizedBox(height: 16),

                // Gender Preference
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

                // AC Preference
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

                const SizedBox(height: 16),

                // Additional Notes (Optional)
                Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, color: _navyBlue, size: 20),
                    const SizedBox(width: 6),
                    const Text('Add Additional Notes ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const Text('(Optional)', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Any special instructions or notes...',
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _navyBlue, width: 1.5)),
                  ),
                ),
              ] else ...[
                // -------------------------------------------------------------
                // TWO WAY TRIP VIEW (Trip 1 & Trip 2 Legs)
                // -------------------------------------------------------------
                // Trip 1 - Home to School (Morning)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          CircleAvatar(radius: 12, backgroundColor: _navyBlue, child: Text('1', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                          SizedBox(width: 8),
                          Text('Trip 1 - Home to School ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          Text('(Morning)', style: TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildLocationInput(controller: _pickupController, label: 'From', hint: 'Enter pickup location', icon: Icons.place_rounded, index: 0, overlay: _showPickupOverlay, suggestions: _pickupSuggestions, isSearching: _isSearchingPickup),
                      const SizedBox(height: 8),
                      _buildLocationInput(controller: _dropoffController, label: 'To', hint: 'Enter drop location', icon: Icons.place_rounded, index: 1, overlay: _showDropoffOverlay, suggestions: _dropoffSuggestions, isSearching: _isSearchingDropoff),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectDate(isReturn: false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: _unselectedPillBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_month_rounded, size: 18, color: _navyBlue),
                                    const SizedBox(width: 6),
                                    Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectTime(isReturn: false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: _unselectedPillBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, size: 18, color: _navyBlue),
                                    const SizedBox(width: 6),
                                    Text(_formatTime(_timeToReach), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Trip 2 - School to Home (Evening)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          CircleAvatar(radius: 12, backgroundColor: _navyBlue, child: Text('2', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                          SizedBox(width: 8),
                          Text('Trip 2 - School to Home ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          Text('(Evening)', style: TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildLocationInput(controller: _returnPickupController, label: 'From', hint: 'Enter pickup location', icon: Icons.place_rounded, index: 2, overlay: _showReturnPickupOverlay, suggestions: _returnPickupSuggestions, isSearching: _isSearchingReturnPickup),
                      const SizedBox(height: 8),
                      _buildLocationInput(controller: _returnDropoffController, label: 'To', hint: 'Enter drop location', icon: Icons.place_rounded, index: 3, overlay: _showReturnDropoffOverlay, suggestions: _returnDropoffSuggestions, isSearching: _isSearchingReturnDropoff),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectDate(isReturn: true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: _unselectedPillBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_month_rounded, size: 18, color: _navyBlue),
                                    const SizedBox(width: 6),
                                    Text(DateFormat('dd MMM yyyy').format(_returnDate), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectTime(isReturn: true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: _unselectedPillBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, size: 18, color: _navyBlue),
                                    const SizedBox(width: 6),
                                    Text(_formatTime(_returnTime), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Enter Fare Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_balance_wallet_rounded, color: _navyBlue, size: 22),
                          SizedBox(width: 8),
                          Text('Enter Fare', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('Enter the expected fare for this trip', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _fareController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 12,000',
                          suffixText: 'PKR',
                          fillColor: _unselectedPillBg,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Options Summary Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your Selected Options (Summary)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navyBlue)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _buildSummaryItem('Service Type', _serviceType)),
                          Expanded(child: _buildSummaryItem('AC Preference', _acPreference)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildSummaryItem('Vehicle Type', _vehicleType)),
                          Expanded(child: _buildSummaryItem('Trip Type', _tripType)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildSummaryItem('Gender Preference', _genderPreference)),
                          Expanded(child: _buildSummaryItem('Locations & Time', 'As selected above')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Bottom Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _handleSubmitRide,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Send Request',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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

  Widget _buildSectionHeader({required String number, required String title, required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: _navyBlue, size: 20),
        const SizedBox(width: 8),
        Text(number.isNotEmpty ? '$number. $title' : title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _buildSelectablePill({required String label, IconData? icon, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? _navyBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? _navyBlue : _borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? (isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
              size: 18,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedPill({required String title, required String subtitle, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _navyBlue : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? _navyBlue : _borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 16, color: isSelected ? Colors.white : const Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF0F172A))),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 10.5, color: isSelected ? Colors.white70 : const Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }

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
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          _buildLocationInput(controller: fromController, label: 'From', hint: 'Enter pickup location', icon: Icons.place_rounded, index: fromIndex, overlay: fromOverlay, suggestions: fromSuggestions, isSearching: fromSearching),
          const SizedBox(height: 10),
          _buildLocationInput(controller: toController, label: 'To', hint: 'Enter drop location', icon: Icons.place_rounded, index: toIndex, overlay: toOverlay, suggestions: toSuggestions, isSearching: toSearching),
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
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: (val) => _onSearchLocation(val, index),
          decoration: InputDecoration(
            hintText: hint,
            fillColor: _unselectedPillBg,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.chevron_right_rounded, color: _navyBlue),
              onPressed: () => _openMapPicker(index),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
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

  Widget _buildSummaryItem(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _navyBlue)),
      ],
    );
  }

  Widget _buildCarSeatVisual(int seatsCount) {
    return Container(
      width: 115,
      height: 90,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.radio_button_checked_rounded, size: 12, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Container(
                height: 3,
                width: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSingleSeat(isOccupied: false, isDriver: true),
              _buildSingleSeat(isOccupied: seatsCount >= 1),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSingleSeat(isOccupied: seatsCount >= 2),
              _buildSingleSeat(isOccupied: seatsCount >= 3 || seatsCount >= 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSingleSeat({required bool isOccupied, bool isDriver = false}) {
    return Container(
      width: 28,
      height: 20,
      decoration: BoxDecoration(
        color: isDriver
            ? const Color(0xFFCBD5E1)
            : (isOccupied ? const Color(0xFF1D4ED8) : const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDriver
              ? const Color(0xFF94A3B8)
              : (isOccupied ? const Color(0xFF1E3A8A) : const Color(0xFFCBD5E1)),
          width: 1.2,
        ),
      ),
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.from(a)..sort();
    final sortedB = List<String>.from(b)..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}
