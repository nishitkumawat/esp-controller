import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/mqtt_service.dart';
import '../services/api_service.dart';

class DeviceControlPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId; // Optional, used for backend logging & permissions
  final bool isAdmin; // Used for stronger delete warning

  const DeviceControlPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
    this.isAdmin = false,
  });

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage>
    with SingleTickerProviderStateMixin {
  final MqttService _mqttService = MqttService();
  final ApiService _apiService = ApiService();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _isSending = false;
  String? _activeCommand;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Maps UI commands to Arduino commands: UP → OPEN, DOWN → CLOSE, STOP → STOP
  Future<void> _sendCommand(String command) async {
    if (_isSending) return;

    setState(() {
      _isSending = true;
      _activeCommand = command;
    });

    // Map UI commands to Arduino commands
    String actualCommand;
    if (command == "UP") {
      actualCommand = "OPEN";
    } else if (command == "DOWN") {
      actualCommand = "CLOSE";
    } else {
      actualCommand = "STOP";
    }

    try {
      // Send via MQTT
      await _mqttService.send(widget.deviceCode, actualCommand);

      // Log in backend (optional)
      if (widget.deviceId != null) {
        _apiService.controlDevice(
          deviceId: widget.deviceId!,
          command: actualCommand,
        ).catchError((e) {
          print("Backend acknowledgment failed → $e");
        });
      }

      Fluttertoast.showToast(
        msg: "Command: $actualCommand Sent ✅",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFFFA500),
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      setState(() {
        _isSending = false;
        _activeCommand = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.deviceName),
        backgroundColor: const Color(0xFFFFA500),
        actions: [
          if (widget.deviceId != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _confirmAndDeleteDevice,
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Device Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA500).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFA500).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.devices, color: Color(0xFFFFA500), size: 32),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.deviceName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text("Code: ${widget.deviceCode}",
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Buttons
              _buildCommandButton("UP", const Color(0xFFFFA500), Icons.arrow_upward),
              const SizedBox(height: 16),
              _buildCommandButton("STOP", Colors.grey, Icons.stop),
              const SizedBox(height: 16),
              _buildCommandButton("DOWN", Colors.red, Icons.arrow_downward),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteDevice() async {
    if (widget.deviceId == null) {
      Fluttertoast.showToast(
        msg: "Cannot remove device: missing device id",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Device'),
          content: Text(
            widget.isAdmin
                ? 'You are the admin for this device. Deleting it will permanently remove it for you and all members. This action cannot be undone.'
                : 'Are you sure you want to remove this device from your account?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.deleteDevice(deviceId: widget.deviceId!);
      Fluttertoast.showToast(
        msg: 'Device removed from your account successfully',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
      // Return true so the caller knows to refresh its list.
      Navigator.of(context).pop(true);
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Network Error',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Widget _buildCommandButton(String command, Color color, IconData icon) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: color,
      child: InkWell(
        onTap: _isSending ? null : () => _sendCommand(command),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _isSending && _activeCommand == command
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                command,
                style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
