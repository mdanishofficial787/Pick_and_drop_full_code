import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/location_map_picker_modal.dart';
import 'package:ride_and_serve/services/auth_service.dart';
import 'package:ride_and_serve/services/location_service.dart';
import 'package:ride_and_serve/services/ride_service.dart';

class TravelAndTourismScreen extends StatefulWidget {
  final CustomerUser? user;

  const TravelAndTourismScreen({super.key, this.user});

  @override
  State<TravelAndTourismScreen> createState() => _TravelAndTourismScreenState();
}

class _TravelAndTourismScreenState extends State<TravelAndTourismScreen> {
  CustomerUser? _currentUser;

  // App Theme Colors
  static const Color _navyBlue = Color(0xFF0F2B5B);
  static const Color _screenBg = Color(0xFFF4F7FC);
  static const Color _unselectedPillBg = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFCBD5E1);

  // Form State
  final _cnicController = TextEditingController();
  final _destinationController = TextEditingController();

  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _returnPickupController = TextEditingController();
  final _returnDropoffController = TextEditingController();
  final _fareController = TextEditingController();

  LocationSuggestion? _selectedPickupLocation;
  LocationSuggestion? _selectedDropoffLocation;
  LocationSuggestion? _selectedReturnPickupLocation;
  LocationSuggestion? _selectedReturnDropoffLocation;

  List<LocationSuggestion> _pickupSuggestions = [];
  List<LocationSuggestion> _dropoffSuggestions = [];
  List<LocationSuggestion> _returnPickupSuggestions = [];
  List<LocationSuggestion> _returnDropoffSuggestions = [];

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
  DateTime _travelDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _travelTime = const TimeOfDay(hour: 15, minute: 32);

  DateTime _returnDate = DateTime.now().add(const Duration(days: 5));
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

    _cnicController.dispose();
    _destinationController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    _returnPickupController.dispose();
    _returnDropoffController.dispose();
    _fareController.dispose();
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
        } else if (fieldIndex == 1) {
          _dropoffSuggestions = results;
          _showDropoffOverlay = results.isNotEmpty;
        } else if (fieldIndex == 2) {
          _returnPickupSuggestions = results;
          _showReturnPickupOverlay = results.isNotEmpty;
        } else if (fieldIndex == 3) {
          _returnDropoffSuggestions = results;
          _showReturnDropoffOverlay = results.isNotEmpty;
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
      'Select Pickup Location (Going)',
      'Select Drop Location (Going)',
      'Select Return Pickup Location',
      'Select Return Drop Location'
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

  // Date / Time Pickers
  Future<void> _selectDate({bool isReturn = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isReturn ? _returnDate : _travelDate,
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
          _travelDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime({bool isReturn = false}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isReturn ? _returnTime : _travelTime,
    );
    if (picked != null) {
      setState(() {
        if (isReturn) {
          _returnTime = picked;
        } else {
          _travelTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  // Submit Travel & Tourism Request
  Future<void> _handleSubmitTravelRequest() async {
    if (_cnicController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your CNIC number'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_pickupController.text.trim().isEmpty || _dropoffController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Pickup and Drop locations'), backgroundColor: Colors.redAccent),
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

      final startingFromStr = DateFormat('yyyy-MM-dd').format(_travelDate);
      final travelTimeStr = _formatTime(_travelTime);

      final num fareValue = num.tryParse(_fareController.text.replaceAll(',', '').trim()) ?? 15000;

      final customScheduleData = {
        'cnic': _cnicController.text.trim(),
        'destination': _destinationController.text.trim(),
        'tripType': 'Two Way',
        'travelDate': startingFromStr,
        'travelTime': travelTimeStr,
        'returnPickupLocation': _returnPickupController.text.trim(),
        'returnDropoffLocation': _returnDropoffController.text.trim(),
        'returnDate': DateFormat('yyyy-MM-dd').format(_returnDate),
        'returnTime': _formatTime(_returnTime),
      };

      final response = await RideService.submitTravelRequest(
        passengerName: passengerName,
        passengerPhone: passengerPhone,
        passengerEmail: passengerEmail,
        cnic: _cnicController.text.trim(),
        pickupLocation: _pickupController.text.trim(),
        dropoffLocation: _dropoffController.text.trim(),
        travelDate: startingFromStr,
        travelTime: travelTimeStr,
        returnDate: DateFormat('yyyy-MM-dd').format(_returnDate),
        returnTime: _formatTime(_returnTime),
        returnPickupLocation: _returnPickupController.text.trim(),
        returnDropoffLocation: _returnDropoffController.text.trim(),
        vehicleType: 'SUV',
        acPreference: 'AC',
        passengersCount: 4,
        fare: fareValue.toInt(),
        notes: 'CNIC: ${_cnicController.text.trim()}',
        customerId: _currentUser?.id,
        customSchedule: customScheduleData,
      );

      if (!mounted) return;

      if (response.success) {
        final reqId = response.requestId ?? 'TT-7001';
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
                    child: const Icon(Icons.flight_takeoff_rounded, color: Color(0xFF16A34A), size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text('TRAVEL REQUEST SUBMITTED!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Text('Request ID: $reqId', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyBlue)),
                  const SizedBox(height: 12),
                  const Text(
                    'Your Travel & Tourism booking request has been sent to Passenger Request Queue. Admin will assign your driver shortly.',
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
            Text('Travel and Tourism', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('Book a ride for your travel journey', style: TextStyle(fontSize: 11, color: Color(0xFF93C5FD), fontWeight: FontWeight.normal)),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.directions_car_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [


              // ---------------------------------------------------------------
              // Plan Your Adventure Card
              // ---------------------------------------------------------------
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.card_travel_rounded, color: _navyBlue, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Plan Your Adventure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                            Text('Book a driver for your travel journey', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Customer CNIC *
                    const Text('Customer CNIC *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cnicController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g. 12345-1234567-1',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.badge_outlined, color: _navyBlue, size: 20),
                        fillColor: _unselectedPillBg,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _navyBlue, width: 1.5)),
                      ),
                    ),


                    const SizedBox(height: 16),


                    // Travel Dates Calendar
                    const Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: _navyBlue, size: 18),
                        SizedBox(width: 6),
                        Text('Travel Dates', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Embedded Calendar Preview Widget
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _unselectedPillBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('MMMM yyyy').format(_travelDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navyBlue)),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                                    onPressed: () => setState(() => _travelDate = _travelDate.subtract(const Duration(days: 30))),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                                    onPressed: () => setState(() => _travelDate = _travelDate.add(const Duration(days: 30))),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () => _selectDate(isReturn: false),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _borderColor)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.calendar_month_rounded, color: _navyBlue, size: 18),
                                  const SizedBox(width: 8),
                                  Text(DateFormat('EEE, dd MMM yyyy').format(_travelDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navyBlue)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 18, color: _navyBlue),
                                  SizedBox(width: 6),
                                  Text('Time', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                ],
                              ),
                              InkWell(
                                onTap: () => _selectTime(isReturn: false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(color: _navyBlue, borderRadius: BorderRadius.circular(10)),
                                  child: Text(_formatTime(_travelTime), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // TWO WAY ACTIVE DETAILS Card
              // ---------------------------------------------------------------
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
                        Icon(Icons.circle, color: Color(0xFF2563EB), size: 10),
                        SizedBox(width: 8),
                        Text('TWO WAY ACTIVE DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.5)),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Pickup Location (Going)
                    _buildInputField(
                      controller: _pickupController,
                      label: 'Pickup Location (Going)',
                      hint: 'Enter Pickup Location',
                      icon: Icons.location_on_outlined,
                      index: 0,
                      overlay: _showPickupOverlay,
                      suggestions: _pickupSuggestions,
                    ),

                    const SizedBox(height: 12),

                    // Drop Location (Going)
                    _buildInputField(
                      controller: _dropoffController,
                      label: 'Drop Location (Going)',
                      hint: 'Enter Drop Location',
                      icon: Icons.near_me_outlined,
                      index: 1,
                      overlay: _showDropoffOverlay,
                      suggestions: _dropoffSuggestions,
                    ),

                    const SizedBox(height: 12),

                    // Return Pickup Location
                    _buildInputField(
                      controller: _returnPickupController,
                      label: 'Return Pickup Location',
                      hint: 'Enter Return Pickup Location',
                      icon: Icons.location_on_outlined,
                      index: 2,
                      overlay: _showReturnPickupOverlay,
                      suggestions: _returnPickupSuggestions,
                    ),

                    const SizedBox(height: 12),

                    // Return Drop Location
                    _buildInputField(
                      controller: _returnDropoffController,
                      label: 'Return Drop Location',
                      hint: 'Enter Return Drop Location',
                      icon: Icons.near_me_outlined,
                      index: 3,
                      overlay: _showReturnDropoffOverlay,
                      suggestions: _returnDropoffSuggestions,
                    ),

                    const SizedBox(height: 14),

                    // Return Date & Return Time
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Return Date', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _selectDate(isReturn: true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(color: _unselectedPillBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_month_rounded, size: 16, color: _navyBlue),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(DateFormat('MMM dd, yyyy').format(_returnDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Return Time', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _selectTime(isReturn: true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(color: _unselectedPillBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 16, color: _navyBlue),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(_formatTime(_returnTime), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ---------------------------------------------------------------
              // Fare Section
              // ---------------------------------------------------------------
              Row(
                children: [
                  const Text('Fare ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
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
                              'The fare may increase or decrease by 1k - 5k depending on the route, location and demand.',
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
              // Bottom Submit Button: SUBMIT REQUEST
              // ---------------------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _handleSubmitTravelRequest,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'SUBMIT REQUEST',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
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
  // Helper Widgets
  // ---------------------------------------------------------------------------
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required int index,
    required bool overlay,
    required List<LocationSuggestion> suggestions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: (val) => _onSearchLocation(val, index),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            prefixIcon: Icon(icon, color: _navyBlue, size: 18),
            suffixIcon: IconButton(
              icon: const Icon(Icons.my_location_rounded, color: _navyBlue, size: 18),
              onPressed: () => _openMapPicker(index),
            ),
            fillColor: _unselectedPillBg,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
}
