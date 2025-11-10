import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/mqtt_service.dart';
import '../services/api_service.dart';

class DeviceControlPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId; // Optional, for API calls

  DeviceControlPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
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

  Future<void> _sendCommand(String command) async {
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      // Send command via MQTT
      await _mqttService.send(widget.deviceCode, command);

      // Acknowledge with backend (optional, but required by spec)
      if (widget.deviceId != null) {
        try {
          await _apiService.controlDevice(
            deviceId: widget.deviceId!,
            command: command,
          );
        } catch (e) {
          // Continue even if backend acknowledgment fails
          print('Backend acknowledgment failed: $e');
        }
      }

      Fluttertoast.showToast(
        msg: 'Command sent: $command',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFFFA500),
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to send command: ${e.toString()}',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.deviceName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFFFA500),
        elevation: 0,
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
                  border: Border.all(
                    color: const Color(0xFFFFA500).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.devices,
                      color: Color(0xFFFFA500),
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.deviceName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Code: ${widget.deviceCode}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Control Buttons
              _buildCommandButton(
                'UP',
                const Color(0xFFFFA500),
                Icons.arrow_upward,
              ),
              const SizedBox(height: 16),
              _buildCommandButton(
                'STOP',
                Colors.grey,
                Icons.stop,
              ),
              const SizedBox(height: 16),
              _buildCommandButton(
                'DOWN',
                Colors.red,
                Icons.arrow_downward,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommandButton(
    String command,
    Color color,
    IconData icon,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.8 + (0.2 * value),
            child: child,
          ),
        );
      },
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: color,
        child: InkWell(
          onTap: _isSending ? null : () => _sendCommand(command),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  color,
                  color.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isSending)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  command,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
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

