import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/driver/capsule_input_field.dart';
import '../../widgets/driver/document_upload_tile.dart';
import '../../widgets/driver/step_progress_bar.dart';
import '../../services/driver_api_service.dart';

class PersonalInfoScreen extends StatefulWidget {
  final void Function(String token) onContinue;
  final VoidCallback? onBack;
  final ScrollController? scrollController;

  const PersonalInfoScreen({
    super.key,
    required this.onContinue,
    this.onBack,
    this.scrollController,
  });

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final ScrollController _scrollController;
  late final AnimationController _avatarAnimController;
  late final Animation<double> _avatarScaleAnim;

  // Form Controllers
  final _nameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _licenseExpiryController = TextEditingController();
  DateTime? _licenseExpiryDate;

  XFile? _avatarFile;
  final Map<String, XFile?> _uploadedDocFiles = {
    'CNIC FRONT': null,
    'CNIC BACK': null,
    'LICENSE FRONT': null,
    'LICENSE BACK': null,
  };

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _avatarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _avatarScaleAnim = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _avatarAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _avatarAnimController.dispose();
    _nameController.dispose();
    _cnicController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _licenseNumberController.dispose();
    _licenseExpiryController.dispose();
    super.dispose();
  }

  Future<void> _selectExpiryDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 2, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 15),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryBlue,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _licenseExpiryDate = picked;
        _licenseExpiryController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<XFile?> _pickImage(ImageSource source) async {
    final XFile? file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    return file;
  }

  void _showImagePickerModal(String title, Function(XFile) onSelected) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Upload $title',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlueLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  title: Text(
                    'Take Photo with Camera',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final file = await _pickImage(ImageSource.camera);
                    if (file != null) {
                      onSelected(file);
                      _showSnackbar('$title captured successfully!');
                    }
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlueLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final file = await _pickImage(ImageSource.gallery);
                    if (file != null) {
                      onSelected(file);
                      _showSnackbar('$title selected successfully!');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _validateAndSubmit() async {
    if (_isSubmitting) return;

    final missing = <String>[];
    if (_nameController.text.trim().isEmpty) missing.add('Full Name');
    if (_cnicController.text.trim().isEmpty) missing.add('CNIC Number');
    if (_phoneController.text.trim().isEmpty) missing.add('Phone Number');
    if (_emailController.text.trim().isEmpty) missing.add('Email');
    if (_passwordController.text.isEmpty) missing.add('Password');
    if (_licenseNumberController.text.trim().isEmpty) {
      missing.add('License Number');
    }
    if (_licenseExpiryDate == null) missing.add('License Expiry Date');
    if (_avatarFile == null) missing.add('Profile Photo');
    for (final key in _uploadedDocFiles.keys) {
      if (_uploadedDocFiles[key] == null) missing.add(key);
    }

    if (missing.isNotEmpty) {
      _showSnackbar('Please complete: ${missing.join(', ')}');
      return;
    }

    final cleanPhone = _phoneController.text.replaceAll(RegExp(r'[\s\-()]'), '');
    final pakPhoneRegex = RegExp(r'^((\+92|92)?(0)?3[0-9]{9})$');
    if (!pakPhoneRegex.hasMatch(cleanPhone)) {
      _showSnackbar('Please enter a valid Pakistani phone number (e.g. 03328904416)');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackbar('Password and Confirm Password do not match');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final token = await DriverApiService.registerDriver(
        name: _nameController.text.trim(),
        countryCode: '+92',
        phoneNumber: cleanPhone.startsWith('+92')
            ? '0${cleanPhone.substring(3)}'
            : (cleanPhone.startsWith('92') && cleanPhone.length == 12)
                ? '0${cleanPhone.substring(2)}'
                : cleanPhone.startsWith('3')
                    ? '0$cleanPhone'
                    : cleanPhone,
        email: _emailController.text.trim(),
        password: _passwordController.text,
        cnicNumber: _cnicController.text.trim(),
        license: _licenseNumberController.text.trim(),
        licenseExpiryDate: _licenseExpiryDate!.toIso8601String(),
        driverPhoto: _avatarFile!,
        cnicFront: _uploadedDocFiles['CNIC FRONT']!,
        cnicBack: _uploadedDocFiles['CNIC BACK']!,
        licenseFront: _uploadedDocFiles['LICENSE FRONT']!,
        licenseBack: _uploadedDocFiles['LICENSE BACK']!,
      );

      if (!mounted) return;
      widget.onContinue(token);
    } on ApiException catch (e) {
      _showSnackbar(e.message);
    } catch (e) {
      debugPrint('REGISTRATION ERROR: $e');
      _showSnackbar('Server Error: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.textPrimary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 22),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(
          'Driver Registration',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: StepProgressBar(
            currentStep: 1,
            onStepTapped: (step) {
              if (step == 2) {
                _validateAndSubmit();
              }
            },
          ),
        ),
      ),
      body: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 5.0,
        radius: const Radius.circular(8),
        thumbColor: AppColors.primaryBlue.withValues(alpha: 0.6),
        trackColor: AppColors.borderLight.withValues(alpha: 0.4),
        trackRadius: const Radius.circular(8),
        padding: const EdgeInsets.only(right: 2),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatarSection(),
                const SizedBox(height: 22),

                _buildSectionHeader(
                  icon: Icons.person_outline_rounded,
                  title: 'Basic Information',
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'FULL NAME',
                  hintText: 'Enter your full name',
                  controller: _nameController,
                  showLabelInside: false,
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'CNIC NUMBER',
                  hintText: '42101-XXXXXXXX-X',
                  controller: _cnicController,
                  showLabelInside: false,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'PHONE NUMBER',
                  hintText: '03328904416',
                  controller: _phoneController,
                  showLabelInside: false,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Phone number is required';
                    }
                    final clean = value.replaceAll(RegExp(r'[\s\-()]'), '');
                    final pakPhoneRegex = RegExp(r'^((\+92|92)?(0)?3[0-9]{9})$');
                    if (!pakPhoneRegex.hasMatch(clean)) {
                      return 'Enter a valid Pakistani number (e.g. 03328904416)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'EMAIL',
                  hintText: 'john@example.com',
                  controller: _emailController,
                  showLabelInside: false,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 18),

                _buildSectionHeader(
                  icon: Icons.lock_outline_rounded,
                  title: 'Account Security',
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'PASSWORD',
                  hintText: '••••••••',
                  controller: _passwordController,
                  showLabelInside: false,
                  isPassword: true,
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'CONFIRM PASSWORD',
                  hintText: '••••••••',
                  controller: _confirmPasswordController,
                  showLabelInside: false,
                  isPassword: true,
                ),
                const SizedBox(height: 18),

                _buildSectionHeader(
                  icon: Icons.badge_outlined,
                  title: 'Driving License',
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'DRIVING LICENSE NUMBER',
                  hintText: 'e.g. LIC-987654',
                  controller: _licenseNumberController,
                  showLabelInside: false,
                ),
                const SizedBox(height: 10),

                CapsuleInputField(
                  label: 'LICENSE EXPIRY DATE',
                  hintText: 'DD/MM/YYYY',
                  controller: _licenseExpiryController,
                  showLabelInside: false,
                  readOnly: true,
                  onTap: _selectExpiryDate,
                  suffixIcon: const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                _buildSectionHeader(
                  icon: Icons.file_copy_outlined,
                  title: 'Upload Documents',
                ),
                const SizedBox(height: 4),
                Text(
                  'Please upload clear photos of your CNIC and Driving License.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: DocumentUploadTile(
                        label: 'CNIC FRONT',
                        uploadPrompt: 'CNIC Front',
                        isUploaded: _uploadedDocFiles['CNIC FRONT'] != null,
                        fileName: 'CNIC_Front.jpg',
                        onTap: () =>
                            _showImagePickerModal('CNIC Front', (file) {
                              setState(
                                () => _uploadedDocFiles['CNIC FRONT'] = file,
                              );
                            }),
                        onClear: () => setState(
                          () => _uploadedDocFiles['CNIC FRONT'] = null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DocumentUploadTile(
                        label: 'CNIC BACK',
                        uploadPrompt: 'CNIC Back',
                        isUploaded: _uploadedDocFiles['CNIC BACK'] != null,
                        fileName: 'CNIC_Back.jpg',
                        onTap: () => _showImagePickerModal('CNIC Back', (file) {
                          setState(() => _uploadedDocFiles['CNIC BACK'] = file);
                        }),
                        onClear: () => setState(
                          () => _uploadedDocFiles['CNIC BACK'] = null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: DocumentUploadTile(
                        label: 'LICENSE FRONT',
                        uploadPrompt: 'License Front',
                        isUploaded: _uploadedDocFiles['LICENSE FRONT'] != null,
                        fileName: 'Lic_Front.jpg',
                        onTap: () =>
                            _showImagePickerModal('License Front', (file) {
                              setState(
                                () => _uploadedDocFiles['LICENSE FRONT'] = file,
                              );
                            }),
                        onClear: () => setState(
                          () => _uploadedDocFiles['LICENSE FRONT'] = null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DocumentUploadTile(
                        label: 'LICENSE BACK',
                        uploadPrompt: 'License Back',
                        isUploaded: _uploadedDocFiles['LICENSE BACK'] != null,
                        fileName: 'Lic_Back.jpg',
                        onTap: () =>
                            _showImagePickerModal('License Back', (file) {
                              setState(
                                () => _uploadedDocFiles['LICENSE BACK'] = file,
                              );
                            }),
                        onClear: () => setState(
                          () => _uploadedDocFiles['LICENSE BACK'] = null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.dashedBlue.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ensure all photos are clear and readable for faster verification.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primaryBlueDark,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _validateAndSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: AppColors.primaryBlue.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'SAVE & CONTINUE',
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.primaryBlueLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryBlue),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.borderLight)),
      ],
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: GestureDetector(
        onTapDown: (_) => _avatarAnimController.forward(),
        onTapUp: (_) {
          _avatarAnimController.reverse();
          _showImagePickerModal('Profile Photo', (file) {
            setState(() => _avatarFile = file);
          });
        },
        onTapCancel: () => _avatarAnimController.reverse(),
        child: AnimatedBuilder(
          animation: _avatarScaleAnim,
          builder: (context, child) =>
              Transform.scale(scale: _avatarScaleAnim.value, child: child),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.35),
                        width: 2.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _avatarFile != null
                          ? CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.primaryBlueLight,
                              backgroundImage: FileImage(
                                File(_avatarFile!.path),
                              ),
                            )
                          : const Icon(
                              Icons.person_outline_rounded,
                              size: 44,
                              color: AppColors.primaryBlue,
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.0),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _avatarFile != null ? 'Change Photo' : 'Add Profile Photo',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
