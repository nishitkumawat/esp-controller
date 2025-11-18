import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/device_auto_detect.dart';

class AddDevicePage extends StatefulWidget {
  AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final TextEditingController _deviceCodeController = TextEditingController();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  late DeviceAutoDetect autoDetect;

  @override
  void initState() {
    super.initState();

    // start auto-detect listener
    autoDetect = DeviceAutoDetect();
    autoDetect.startListener((deviceData) async {
      try {
        final deviceId = deviceData["device_id"]?.toString() ?? "";
        if (deviceId.isEmpty) return;
        print("Auto-detected device id: $deviceId");
        // auto-fill the input and trigger existing add flow
        _deviceCodeController.text = deviceId;
        await _addDevice();
      } catch (e) {
        print("Auto-detect callback error: $e");
      }
    });
  }

  @override
  void dispose() {
    _deviceCodeController.dispose();
    super.dispose();
  }

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = await _authService.getUserId();
      if (userId == null) {
        Fluttertoast.showToast(
          msg: 'User not logged in',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        setState(() => _isLoading = false);
        return;
      }

      final deviceCode = _deviceCodeController.text.trim();
      final response = await _apiService.addDevice(
        userId: userId,
        deviceCode: deviceCode,
      );

      setState(() => _isLoading = false);

      // Check response status
      if (response['status'] == 'success' || response['status'] == 'admin') {
        // Device added successfully, user is now admin
        Fluttertoast.showToast(
          msg: 'Device added successfully! You are now the admin.',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        // Navigate back to Your Devices page (index 0)
        Navigator.pop(context);
        // Trigger refresh in Your Devices page
        Future.delayed(const Duration(milliseconds: 100), () {
          // The Your Devices page will refresh when it becomes visible
        });
      } else if (response['status'] == 'already_linked') {
        // User already linked to device
        Fluttertoast.showToast(
          msg: 'Already Linked',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFFFFA500),
          textColor: Colors.white,
        );
        Navigator.pop(context);
      } else if (response['status'] == 'request_sent') {
        // Request sent
        Fluttertoast.showToast(
          msg: 'Request Sent',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: const Color(0xFFFFA500),
          textColor: Colors.white,
        );
        Navigator.pop(context);
      } else {
        throw Exception(response['message'] ?? 'Unknown error');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(
        msg: 'Failed to add device: ${e.toString()}',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  String? _validateDeviceCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter device code';
    }
    if (value.trim().length != 16) {
      return 'Device code must be 16 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Add Device',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFFFA500),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA500).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_circle_outline,
                    size: 60,
                    color: Color(0xFFFFA500),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Add New Device',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFA500),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 16-character device code',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                // Device Code Input
                TextFormField(
                  controller: _deviceCodeController,
                  decoration: InputDecoration(
                    labelText: 'Device Code',
                    hintText: 'Enter 16-character code',
                    prefixIcon: const Icon(
                      Icons.qr_code,
                      color: Color(0xFFFFA500),
                    ),
                    counterText: '',
                  ),
                  maxLength: 16,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  ],
                  validator: _validateDeviceCode,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _addDevice(),
                ),
                const SizedBox(height: 32),
                // Add Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _addDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFA500),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: _isLoading ? 2 : 6,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Add Device',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA500).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFA500).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFFFA500),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'If the device doesn\'t exist, you\'ll become the admin. If it exists and you\'re not linked, a request will be sent.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

