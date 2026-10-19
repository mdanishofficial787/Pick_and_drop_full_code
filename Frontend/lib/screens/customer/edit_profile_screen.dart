import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ride_and_serve/models/user_model.dart';
import 'package:ride_and_serve/screens/customer/profile_image_cropper.dart';
import 'package:ride_and_serve/services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  final CustomerUser? user;

  const EditProfileScreen({super.key, this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  CustomerUser? _currentUser;

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  Uint8List? _selectedPhotoBytes;
  bool _isSaving = false;
  bool _isLoading = true;
  bool _saved = false; // true once the profile was updated successfully

  static const Color _screenBg = Color(0xFFF4F7FC);
  static const Color _borderColor = Color(0xFFCBD5E1);
  static const int _maxPhotoBytes = 4 * 1024 * 1024; // Vercel body limit ~4.5MB

  @override
  void initState() {
    super.initState();
    _loadInitialUserData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialUserData() async {
    // Prefer the freshest saved user, fall back to the one passed in
    _currentUser = await AuthService.getCurrentUser() ?? widget.user;

    if (_currentUser != null) {
      _fullNameController.text = _currentUser!.fullName;
      _emailController.text = _currentUser!.email;
      // Backend expects digits only (7-15)
      _phoneController.text =
          (_currentUser!.phoneNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _pickAndCropImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    if (!mounted) return;

    final Uint8List? croppedBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (ctx) => ProfileImageCropperPage(
          imageBytes: bytes,
          title: 'Adjust Profile Picture',
        ),
      ),
    );

    if (croppedBytes == null || !mounted) return;

    if (croppedBytes.length > _maxPhotoBytes) {
      _showError('Photo is too large. Please choose a smaller image (under 4 MB).');
      return;
    }

    setState(() => _selectedPhotoBytes = croppedBytes);
  }

  String? _validate() {
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.length < 3) return 'Full name must be at least 3 characters';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    if (!RegExp(r'^[0-9]{7,15}$').hasMatch(phone)) {
      return 'Phone number must be 7 to 15 digits (numbers only)';
    }
    return null;
  }

  Future<void> _handleSaveChanges() async {
    if (_currentUser == null || _currentUser!.id.isEmpty) {
      _showError('User not loaded. Please log in again.');
      return;
    }

    final error = _validate();
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final response = await AuthService.updateProfile(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        photoBytes: _selectedPhotoBytes,
        customerId: _currentUser!.id,
      );

      if (!mounted) return;

      debugPrint('updateProfile success=${response.isSuccess}');

      if (response.isSuccess) {
        final updatedUser = await AuthService.getCurrentUser();
        if (!mounted) return;

        _saved = true;
        if (updatedUser != null) {
          setState(() {
            _currentUser = updatedUser;
            _selectedPhotoBytes = null; // show the saved photo from the server
          });
        }
        _showSuccessSheet(updatedUser);
      } else {
        _showError(response.message ?? 'Update failed. Please try again.');
      }
    } catch (e, st) {
      debugPrint('updateProfile error: $e\n$st');
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSuccessSheet(CustomerUser? user) {
    final name = user?.fullName ?? _fullNameController.text.trim();
    final email = user?.email ?? _emailController.text.trim();
    final phone = user?.phoneNumber ?? _phoneController.text.trim();
    final photoUrl = user?.photoUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFFF4FBF7),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 54),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Profile Updated',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your profile has been updated successfully.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFEFF6FF),
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? const Icon(Icons.person, color: Color(0xFF2563EB), size: 30)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        const SizedBox(height: 2),
                        Text(email, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        Text(phone, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.pop(ctx), // just close the sheet
                child: const Text(
                  'Back to Profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    ).then((_) {
      // Runs however the sheet closes (button, swipe down, or tap outside)
      if (mounted) Navigator.pop(context, true);
    });
  }

  Widget _buildAvatar() {
    final photoUrl = _currentUser?.photoUrl;

    Widget child;
    if (_selectedPhotoBytes != null) {
      child = Image.memory(_selectedPhotoBytes!, fit: BoxFit.cover);
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      child = Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) =>
            const Icon(Icons.person, size: 50, color: Color(0xFF2563EB)),
      );
    } else {
      child = const Icon(Icons.person, size: 50, color: Color(0xFF2563EB));
    }

    return Container(
      width: 105,
      height: 105,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _saved);
      },
      child: Scaffold(
        backgroundColor: _screenBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
            onPressed: () => Navigator.pop(context, _saved),
          ),
          title: const Text(
            'Edit Profile',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          centerTitle: true,
        ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),

                    // Avatar with camera icon overlay
                    Center(
                      child: Stack(
                        children: [
                          _buildAvatar(),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: InkWell(
                              onTap: _isSaving ? null : _pickAndCropImage,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    _buildInputGroup(
                      label: 'Full Name',
                      controller: _fullNameController,
                      icon: Icons.person_outline_rounded,
                      keyboardType: TextInputType.name,
                    ),
                    const SizedBox(height: 18),

                    _buildInputGroup(
                      label: 'Email Address',
                      controller: _emailController,
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 18),

                    _buildInputGroup(
                      label: 'Phone Number',
                      controller: _phoneController,
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                    ),

                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _isSaving ? null : _handleSaveChanges,
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildInputGroup({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required TextInputType keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Icon(icon, color: const Color(0xFF2563EB), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                enabled: !_isSaving,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}