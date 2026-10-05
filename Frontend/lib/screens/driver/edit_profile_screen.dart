import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '/api_config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';

class EditProfileScreen extends StatefulWidget {
  final String driverName;
  final String? email;
  final String? phone;
  final String? profilePic;
  final String? driverId;
  final String? token;

  const EditProfileScreen({
    super.key,
    required this.driverName,
    this.email,
    this.phone,
    this.profilePic,
    this.driverId,
    this.token,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;

  bool _isLoading = false;
  bool _isSaving = false;

  // Which field is currently in edit mode
  String? _editingField;
  XFile? _newProfilePic;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.driverName);
    _emailController = TextEditingController(text: widget.email ?? '');
    _phoneController = TextEditingController(text: widget.phone ?? '');
    _fetchDriverDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchDriverDetails() async {
    if (widget.driverId == null) return;
    setState(() => _isLoading = true);
    try {
      final headers = <String, String>{};
      if (widget.token != null) {
        headers['Authorization'] = 'Bearer ${widget.token}';
      }
      final res = await http.get(
        Uri.parse('$kBaseUrl/driver/${widget.driverId}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final driverData = data['driver'] ?? data['data'] ?? data;
        final email = driverData['email']?.toString() ?? driverData['Email']?.toString() ?? '';
        final phone = driverData['phoneNumber']?.toString() ?? driverData['phone']?.toString() ?? driverData['Phone']?.toString() ?? '';
        setState(() {
          if (email.isNotEmpty) _emailController.text = email;
          if (phone.isNotEmpty) _phoneController.text = phone;
        });
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _saveChanges() async {
  if (widget.driverId == null) {
    _showSnack('Driver ID not found', isError: true);
    return;
  }
  if (widget.token == null) {
    _showSnack('Authentication error: Token is missing. Please log in again.', isError: true);
    return;
  }
  setState(() => _isSaving = true);
  try {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.token}',
    };
    http.Response res;
    if (_newProfilePic != null) {
      final request = http.MultipartRequest('PATCH', Uri.parse('$kBaseUrl/driver/${widget.driverId}'));
      request.headers.addAll({'Authorization': 'Bearer ${widget.token}'});
      final nameVal = _nameController.text.trim();
      final emailVal = _emailController.text.trim();
      final phoneVal = _phoneController.text.trim();
      
      if (nameVal.isNotEmpty) request.fields['Name'] = nameVal;
      if (emailVal.isNotEmpty) request.fields['Email'] = emailVal;
      if (phoneVal.isNotEmpty) request.fields['PhoneNumber'] = phoneVal;

      final bytes = await _newProfilePic!.readAsBytes();
      String name = _newProfilePic!.name.isNotEmpty ? _newProfilePic!.name : 'profilePic.jpg';
      final ext = name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';

      request.files.add(http.MultipartFile.fromBytes(
        'driverPhoto',
        bytes,
        filename: name,
        contentType: MediaType('image', ext),
      ));

      final streamedResponse = await request.send();
      res = await http.Response.fromStream(streamedResponse);
    } else {
      final Map<String, dynamic> bodyData = {};
      final nameVal = _nameController.text.trim();
      final emailVal = _emailController.text.trim();
      final phoneVal = _phoneController.text.trim();
      
      if (nameVal.isNotEmpty) bodyData['Name'] = nameVal;
      if (emailVal.isNotEmpty) bodyData['Email'] = emailVal;
      if (phoneVal.isNotEmpty) bodyData['PhoneNumber'] = phoneVal;

      res = await http.patch(
        Uri.parse('$kBaseUrl/driver/${widget.driverId}'),
        headers: headers,
        body: jsonEncode(bodyData),
      );
    }

    debugPrint('PATCH ${res.statusCode}: ${res.body}'); // <-- see exactly what the server says

    if (res.statusCode == 200) {
      _showSnack('Profile updated successfully!');
      if (mounted) Navigator.pop(context, true);
    } else {
      String errorMsg = 'Failed to update profile (${res.statusCode})';
      try {
        final body = jsonDecode(res.body);
        errorMsg = body['message']?.toString() ?? errorMsg;
      } catch (_) {
        // body wasn't JSON — keep the generic message but log the raw body
        debugPrint('Non-JSON error body: ${res.body}');
      }
      _showSnack(errorMsg, isError: true);
    }
  } catch (e) {
    _showSnack('Error: $e', isError: true);
    debugPrint('SAVE EXCEPTION: $e');
  }
  if (mounted) setState(() => _isSaving = false);
}
  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() => _newProfilePic = file);
    }
  }

  void _showImagePickerModal() {
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Update Profile Photo',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF1959F6)),
                  title: Text('Take Photo with Camera', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF1959F6)),
                  title: Text('Choose from Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F4F8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Edit Profile',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1959F6)))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      children: [
                        // Profile Photo
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade200,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
                              ),
                              child: ClipOval(child: _buildProfileImage()),
                            ),
                            GestureDetector(
                              onTap: _showImagePickerModal,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(color: const Color(0xFF1959F6), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // Fields Card
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Column(
                            children: [
                              _buildField(
                                icon: Icons.person_outline_rounded,
                                label: 'Name',
                                controller: _nameController,
                                fieldKey: 'name',
                                keyboardType: TextInputType.name,
                                showDivider: true,
                              ),
                              _buildField(
                                icon: Icons.email_outlined,
                                label: 'Email',
                                controller: _emailController,
                                fieldKey: 'email',
                                keyboardType: TextInputType.emailAddress,
                                showDivider: true,
                              ),
                              _buildField(
                                icon: Icons.phone_outlined,
                                label: 'Phone Number',
                                controller: _phoneController,
                                fieldKey: 'phone',
                                keyboardType: TextInputType.phone,
                                showDivider: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Save Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1959F6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : Text('Save Changes', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileImage() {
    if (_newProfilePic != null) {
      return FutureBuilder<Uint8List>(
        future: _newProfilePic!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              width: 90,
              height: 90,
            );
          }
          return _defaultAvatar();
        },
      );
    }
    if (widget.profilePic != null && widget.profilePic!.isNotEmpty) {
      return Image.network(widget.profilePic!, fit: BoxFit.cover, width: 90, height: 90, errorBuilder: (_, __, ___) => _defaultAvatar());
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() => Container(color: const Color(0xFFE0E7FF), child: const Icon(Icons.person_rounded, color: Color(0xFF1959F6), size: 44));

  Widget _buildField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String fieldKey,
    required TextInputType keyboardType,
    required bool showDivider,
  }) {
    final isEditing = _editingField == fieldKey;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: const Color(0xFF1959F6), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    isEditing
                        ? TextField(
                            controller: controller,
                            keyboardType: keyboardType,
                            autofocus: true,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827)),
                            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                            onSubmitted: (_) => setState(() => _editingField = null),
                          )
                        : Text(
                            controller.text.isNotEmpty ? controller.text : 'Tap pencil to edit',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: controller.text.isNotEmpty ? const Color(0xFF111827) : Colors.grey.shade400),
                          ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _editingField = isEditing ? null : fieldKey),
                child: Icon(isEditing ? Icons.check_rounded : Icons.edit_outlined, color: const Color(0xFF1959F6), size: 20),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
      ],
    );
  }
}
