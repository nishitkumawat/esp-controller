import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/mqtt_service_factory.dart';
import '../services/api_service.dart';
import 'home_page.dart';

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
  late final dynamic _mqttService;
  final ApiService _apiService = ApiService();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _isSending = false;
  String? _activeCommand;

  void _goToHomeTab(int index) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _mqttService = MqttServiceFactory.getMqttService(widget.deviceCode);
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
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'MachMate',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withOpacity(0.06)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.deviceName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.deviceCode,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Your Devices'),
                onTap: () => _goToHomeTab(0),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Add Device'),
                onTap: () => _goToHomeTab(1),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Account'),
                onTap: () => _goToHomeTab(2),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'v1',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Text(widget.deviceName),
        backgroundColor: Colors.white,
        elevation: 0,
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
          padding: const EdgeInsets.all(16),
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
                        Icons.devices_outlined,
                        color: Color(0xFFFFA500),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.deviceName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2C3E50),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.deviceCode,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

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
