const fs = require('fs');
let code = fs.readFileSync('Frontend/lib/screens/customer/payment_details_screen.dart', 'utf-8');

// Revert all 'child: _isSubmitting ? ...' back to 'child: Text('
code = code.replace(/child: _isSubmitting \? const SizedBox\(width: 20, height: 20, child: CircularProgressIndicator\(color: Colors\.white, strokeWidth: 2\)\) : Text\(/g, 'child: Text(');

// Add missing imports
if (!code.includes('package:http/http.dart')) {
    code = code.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:http/http.dart' as http;\nimport 'package:shared_preferences/shared_preferences.dart';\nimport '../../api_config.dart';"
    );
}

// Ensure the button shows loading
code = code.replace(
    "child: Text(\n                    'Submit Payment',",
    "child: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(\n                    'Submit Payment',"
);

// Fix the onPressed
code = code.replace(
    /onPressed: \(_isConfirmed && \(_paymentProof != null \|\| _webPaymentProof != null\) && !_isSubmitting\) \? _submitPayment : null,/g,
    "onPressed: (_isConfirmed && (_paymentProof != null || _webPaymentProof != null) && !_isSubmitting) ? _submitPayment : null,"
);


// Add _isSubmitting variable and replace _submitPayment method
const oldSubmitPayment = /void _submitPayment\(\) \{[\s\S]*?\}\n/;
const newSubmitPayment = `
  bool _isSubmitting = false;

  Future<void> _submitPayment() async {
    if (!_isConfirmed || (_paymentProof == null && _webPaymentProof == null)) return;
    setState(() => _isSubmitting = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      final rideId = widget.rideData['id'] ?? widget.rideData['requestId'] ?? 'RS-9982';
      final fare = widget.rideData['fare']?.toString() ?? widget.rideData['fareFormatted'] ?? '4500';

      var request = http.MultipartRequest('POST', Uri.parse('\${kBaseUrl}/api/payments/upload'));
      if (token != null) request.headers['Authorization'] = 'Bearer ' + token;
      request.fields['rideId'] = rideId;
      request.fields['fare'] = fare;

      if (kIsWeb && _webPaymentProof != null) {
        var bytes = await _webPaymentProof!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('paymentProof', bytes, filename: _webPaymentProof!.name));
      } else if (!kIsWeb && _paymentProof != null) {
        request.files.add(await http.MultipartFile.fromPath('paymentProof', _paymentProof!.path));
      }

      var response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PaymentStatusScreen(
          rideId: rideId, fare: fare, imageFile: _paymentProof, webImageFile: _webPaymentProof
        )));
      } else {
        final respStr = await response.stream.bytesToString();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: \${respStr}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: \${e}')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
`;

if (code.includes('void _submitPayment() {')) {
    code = code.replace(oldSubmitPayment, newSubmitPayment);
}

fs.writeFileSync('Frontend/lib/screens/customer/payment_details_screen.dart', code);
