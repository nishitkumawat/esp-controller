import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

class ShutterControlPage extends StatefulWidget {
  const ShutterControlPage({super.key});

  @override
  State<ShutterControlPage> createState() => _ShutterControlPageState();
}

class _ShutterControlPageState extends State<ShutterControlPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController idController = TextEditingController();
  final MqttService mqtt = MqttService();
  final AuthService authService = AuthService();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    loadSavedId();

    // Fade-in animation for dashboard
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  void loadSavedId() async {
    final prefs = await SharedPreferences.getInstance();
    idController.text = prefs.getString("device_id") ?? "";
  }

  void saveId() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("device_id", idController.text.trim());
  }

  void sendCommand(String cmd) {
    final id = idController.text.trim();
    if (id.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Please enter a device ID',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
        fontSize: 16.0,
      );
      return;
    }
    mqtt.send(id, cmd);
    saveId();
    Fluttertoast.showToast(
      msg: 'Command sent: $cmd',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFFFFA500),
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  Future<void> logout() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(color: Color(0xFFFFA500)),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFA500),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoggingOut = true);
      await authService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "MachMate Controller",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFFFA500),
        elevation: 0,
        actions: [
          if (_isLoggingOut)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: logout,
              tooltip: 'Logout',
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
              // Device ID Input
              _buildAnimatedTextField(),
              const SizedBox(height: 32),
              // Control Buttons
              _buildAnimatedCommandButton("OPEN", const Color(0xFFFFA500), Icons.arrow_upward),
              const SizedBox(height: 16),
              _buildAnimatedCommandButton("STOP", Colors.grey, Icons.stop),
              const SizedBox(height: 16),
              _buildAnimatedCommandButton("CLOSE", Colors.redAccent, Icons.arrow_downward),
              const SizedBox(height: 32),
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
                        'Enter your device ID and use the buttons to control your device.',
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
    );
  }

  Widget _buildAnimatedTextField() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 50 * (1 - value)),
            child: child,
          ),
        );
      },
      child: TextField(
        controller: idController,
        decoration: InputDecoration(
          labelText: "Enter Device ID",
          hintText: "Device ID",
          prefixIcon: const Icon(
            Icons.devices,
            color: Color(0xFFFFA500),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: const Color(0xFFFFA500).withOpacity(0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: const Color(0xFFFFA500).withOpacity(0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFFFFA500),
              width: 2,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => saveId(),
      ),
    );
  }

  Widget _buildAnimatedCommandButton(String text, Color color, IconData icon) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.8 + (0.2 * value), child: child),
        );
      },
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        color: color,
        child: InkWell(
          onTap: () => sendCommand(text),
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
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  text,
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

class MqttService {
  final broker = "broker.hivemq.com"; // Public broker
  final int port = 1883; // TCP port
  MqttServerClient? client;

  Future<void> connect() async {
    client = MqttServerClient(
      broker,
      'flutter_${DateTime.now().millisecondsSinceEpoch}',
    );
    client!.port = port;
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;
    client!.onDisconnected = () => print('[MQTT] Disconnected');

    final connMessage = MqttConnectMessage()
        .withClientIdentifier("flutter_controller")
        .startClean();

    client!.connectionMessage = connMessage;

    try {
      await client!.connect();
      print('[MQTT] Connected');
    } catch (e) {
      print('[MQTT] Connection failed: $e');
      client!.disconnect();
    }
  }

  Future<void> send(String deviceId, String command) async {
    if (client == null ||
        client!.connectionStatus?.state != MqttConnectionState.connected) {
      await connect();
    }

    final topic = "shutter/$deviceId/cmd";
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);

    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print('[MQTT] Sent $command to $topic');
  }
}
