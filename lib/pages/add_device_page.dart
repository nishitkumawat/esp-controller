import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/device_auto_detect.dart';

class AddDevicePage extends StatefulWidget {
  final VoidCallback? onDeviceAdded;

  const AddDevicePage({super.key, this.onDeviceAdded});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final TextEditingController _deviceCodeController = TextEditingController();
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _canSubmit = false;

  late DeviceAutoDetect autoDetect;

  @override
  void initState() {
    super.initState();

    _deviceCodeController.addListener(_recomputeCanSubmit);

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

    _recomputeCanSubmit();
  }

  void _recomputeCanSubmit() {
    final code = _deviceCodeController.text.trim();
    final next = code.length == 16;
    if (next == _canSubmit) return;
    if (!mounted) return;
    setState(() {
      _canSubmit = next;
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
      
      // Check if this device is already in the user's devices
      try {
        final userDevices = await _apiService.getUserDevices();
        if (userDevices['devices'] is List) {
          final devices = List<dynamic>.from(userDevices['devices']);
          if (devices.any((device) => 
              device['device_code']?.toString().toLowerCase() == deviceCode.toLowerCase())) {
            Fluttertoast.showToast(
              msg: 'This device is already in your list',
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.orange,
              textColor: Colors.white,
            );
            setState(() => _isLoading = false);
            return;
          }
        }
      } catch (e) {
        print('Error checking existing devices: $e');
        // Continue with adding the device if we can't check existing ones
      }

      final response = await _apiService.addDevice(
        userId: userId,
        deviceCode: deviceCode,
      );

      setState(() => _isLoading = false);
      
      Fluttertoast.showToast(
        msg: response['message'] ?? 
            'Device added successfully. If this device is new you will become the admin, otherwise a request is sent to the current admin.',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );

      // Notify parent (HomePage) so it can switch to the devices tab.
      widget.onDeviceAdded?.call();
    } catch (e) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(
        msg: 'Error: ${e.toString().replaceAll('Exception: ', '')}',
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Add Device',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3E50),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFA500).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner,
                          color: Color(0xFFFFA500),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add your device',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enter the 16-character code',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: TextFormField(
                    controller: _deviceCodeController,
                    decoration: InputDecoration(
                      hintText: 'Device code',
                      prefixIcon: const Icon(Icons.qr_code),
                      border: InputBorder.none,
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
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_canSubmit) ? null : _addDevice,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.disabled)) {
                          return const Color(0xFFB8C1CC);
                        }
                        return const Color(0xFF2C3E50);
                      }),
                      foregroundColor: MaterialStateProperty.all(Colors.white),
                      elevation: MaterialStateProperty.all(0),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
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
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFA500).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.info_outline, color: Color(0xFFFFA500)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'If the device doesn\'t exist, you\'ll become the admin. If it exists and you\'re not linked, a request will be sent.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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

