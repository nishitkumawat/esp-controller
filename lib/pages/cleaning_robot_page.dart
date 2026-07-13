import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../services/api_service.dart';
import 'home_page.dart';

// ============================================================
//  CleaningRobotPage — for devices where deviceCode[1..2] == 'AA'
//  MQTT topics (match ESP8266 firmware):
//    Publish:  robot/<device_id>/start          → "START_CYCLE"
//    Publish:  robot/<device_id>/stop           → "STOP"
//    Publish:  robot/<device_id>/status/request → "STATUS"
//    Subscribe: robot/<device_id>/status        → state string
// ============================================================

class CleaningRobotPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId;
  final bool isAdmin;

  const CleaningRobotPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
    this.isAdmin = false,
  });

  @override
  State<CleaningRobotPage> createState() => _CleaningRobotPageState();
}

class _CleaningRobotPageState extends State<CleaningRobotPage>
    with SingleTickerProviderStateMixin {
  // ── MQTT ──────────────────────────────────────────────────
  static const String _broker   = 'mqtt.ezrun.in';
  static const int    _port     = 8883;
  static const String _user     = 'nk';
  static const String _pass     = '9898434411';

  // Topics (match updated firmware)
  String get _topicStart     => 'robot/${widget.deviceCode}/start';
  String get _topicStop      => 'robot/${widget.deviceCode}/stop';
  String get _topicStatusReq => 'robot/${widget.deviceCode}/status/request';
  String get _topicStatus    => 'robot/${widget.deviceCode}/status';

  MqttServerClient? _client;
  bool _mqttConnected  = false;
  bool _mqttConnecting = false;

  // ── State ─────────────────────────────────────────────────
  String  _robotStatus = 'UNKNOWN';   // last value from robot/status
  bool    _isSending   = false;
  Timer?  _statusTimeoutTimer;        // if no message → offline
  Timer?  _statusPollTimer;           // poll status periodically
  Timer?  _reconnectTimer;
  StreamSubscription? _mqttSubscription; // manage stream subscription
  bool    _isOnline    = false;       // robot considered online

  // ── Animation ─────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  final ApiService _apiService = ApiService();

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _connectMqtt();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusTimeoutTimer?.cancel();
    _statusPollTimer?.cancel();
    _reconnectTimer?.cancel();
    _mqttSubscription?.cancel();
    _client?.disconnect();
    super.dispose();
  }

  // ── MQTT connect ──────────────────────────────────────────
  Future<void> _connectMqtt() async {
    if (_mqttConnecting) return;
    setState(() => _mqttConnecting = true);

    final clientId = 'robot_app_${DateTime.now().millisecondsSinceEpoch % 999999}';
    _client = MqttServerClient.withPort(_broker, clientId, _port);
    _client!.logging(on: false);
    _client!.secure = true;
    
    // Typecast fix to ensure compatibility with latest mqtt_client changes
    _client!.onBadCertificate = (Object _) => true; 
    _client!.keepAlivePeriod = 60;

    _client!.onConnected    = _onMqttConnected;
    _client!.onDisconnected = _onMqttDisconnected;
    _client!.setProtocolV311();

    final msg = MqttConnectMessage()
        .authenticateAs(_user, _pass)
        .withClientIdentifier(clientId)
        .startClean();
        // Removed .withWillQos(MqttQos.atLeastOnce) without a will topic, as this makes the CONNECT packet malformed 
        // and causes the broker to drop the connection without a CONNACK (NoConnectionException).
    _client!.connectionMessage = msg;

    try {
      await _client!.connect();
    } catch (e) {
      debugPrint('[Robot MQTT] connect error: $e');
      _scheduleReconnect();
    } finally {
      if (mounted) setState(() => _mqttConnecting = false);
    }
  }

  void _onMqttConnected() {
    debugPrint('[Robot MQTT] Connected ✓');
    if (!mounted) return;
    setState(() {
      _mqttConnected  = true;
      _mqttConnecting = false;
    });
    
    debugPrint('[Robot MQTT] Subscribed: $_topicStatus');
    _client!.subscribe(_topicStatus, MqttQos.atLeastOnce);
    
    _mqttSubscription?.cancel();
    _mqttSubscription = _client!.updates!.listen(_onMqttMessage);
    
    // Add 500ms delay to ensure subscription is fully processed by broker
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_mqttConnected) {
        _publishRaw(_topicStatusReq, 'STATUS');
      }
    });
    
    // Poll every 2 seconds — a balance between realtime feel and broker load.
    // Long-term fix: have the ESP firmware auto-publish to robot/<id>/status
    // whenever state changes. Then polling can be reduced to ~15s (heartbeat only).
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_mqttConnected) {
        _publishRaw(_topicStatusReq, 'STATUS');
      }
    });
    
    _startStatusTimeout();
  }

  void _onMqttDisconnected() {
    debugPrint('[Robot MQTT] Disconnected');
    if (!mounted) return;
    setState(() {
      _mqttConnected = false;
      _isOnline      = false;
      _robotStatus   = 'UNKNOWN'; // Prevent stale state on next reconnect
    });
    _statusPollTimer?.cancel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_mqttConnected) _connectMqtt();
    });
  }

  void _onMqttMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (var event in events) {
      final rec = event.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(rec.payload.message);
      final topic = event.topic;
      final isRetained = rec.header!.retain;

      debugPrint('[Robot MQTT] Received:');
      debugPrint('  Topic: $topic');
      debugPrint('  Payload: $payload');
      debugPrint('  Retained: $isRetained');

      if (topic == _topicStatus && mounted) {
        setState(() {
          _robotStatus = payload.trim().toUpperCase();
          // Only mark online for LIVE (non-retained) messages.
          // Retained messages are stale and may come from a device that is
          // currently offline — do NOT use them to set online status.
          if (!isRetained) {
            _isOnline = true;
          }
        });

        // Reset the offline timeout only for live messages
        if (!isRetained) {
          _startStatusTimeout();
        }
      }
    }
  }

  // Mark device offline if no status message arrives within 30 s
  void _startStatusTimeout() {
    _statusTimeoutTimer?.cancel();
    _statusTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _isOnline = false);
    });
  }

  // ── Publish helpers ───────────────────────────────────────
  void _publishRaw(String topic, String payload) {
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    debugPrint('[Robot MQTT] Published:');
    debugPrint('  Topic: $topic');
    debugPrint('  Payload: $payload');
    
    final builder = MqttClientPayloadBuilder()..addString(payload);
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  // ── Commands ──────────────────────────────────────────────
  Future<void> _sendStart() async {
    if (_isSending || !_mqttConnected) return;
    setState(() => _isSending = true);
    try {
      _publishRaw(_topicStart, 'START_CYCLE');
      _toast('Start command sent ✅', Colors.green);
    } catch (e) {
      _toast('Failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendStop() async {
    if (_isSending || !_mqttConnected) return;
    setState(() => _isSending = true);
    try {
      _publishRaw(_topicStop, 'STOP');
      _toast('Stop command sent 🛑', Colors.orange);
    } catch (e) {
      _toast('Failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _requestStatus() {
    if (!_mqttConnected) return;
    _publishRaw(_topicStatusReq, 'STATUS');
    _toast('Status requested', Colors.blueGrey);
  }

  Future<void> _confirmAndDeleteDevice() async {
    if (widget.deviceId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(
          widget.isAdmin
              ? 'You are the admin. Removing will delete the device for all members.'
              : 'Remove this device from your account?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _apiService.deleteDevice(deviceId: widget.deviceId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _toast('Error removing device', Colors.red);
    }
  }

  void _toast(String msg, Color bg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: bg,
      textColor: Colors.white,
      gravity: ToastGravity.BOTTOM,
    );
  }

  // ── Helpers ───────────────────────────────────────────────
  /// Human-readable label + icon for each robot state string
  _StateInfo _stateInfo(String status) {
    switch (status) {
      case 'RUNNING_FORWARD':
        return _StateInfo('Cleaning · Forward', Icons.arrow_forward_rounded,
            const Color(0xFF3B82F6));
      case 'RUNNING_REVERSE':
        return _StateInfo('Cleaning · Reverse', Icons.arrow_back_rounded,
            const Color(0xFF3B82F6));
      case 'RETURNING_TO_DOCK':
        return _StateInfo('Returning to Dock', Icons.home_rounded,
            const Color(0xFF8B5CF6));
      case 'CYCLE_COMPLETED':
        return _StateInfo('Cycle Completed', Icons.check_circle_rounded,
            const Color(0xFF10B981));
      case 'FAULT':
        return _StateInfo('Fault Detected', Icons.warning_rounded,
            const Color(0xFFEF4444));
      case 'STOPPING':
        return _StateInfo('Stopping…', Icons.pause_circle_rounded,
            const Color(0xFFF59E0B));
      case 'IDLE':
        return _StateInfo('Idle · Ready', Icons.radio_button_unchecked,
            const Color(0xFF64748B));
      default:
        return _StateInfo('Unknown', Icons.device_unknown_rounded,
            const Color(0xFF64748B));
    }
  }

  bool get _isRunning =>
      _robotStatus == 'RUNNING_FORWARD' ||
      _robotStatus == 'RUNNING_REVERSE' ||
      _robotStatus == 'RETURNING_TO_DOCK' ||
      _robotStatus == 'STOPPING';

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final si = _stateInfo(_robotStatus);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.deviceName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              widget.deviceCode,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          // MQTT connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _MqttDot(connected: _mqttConnected, connecting: _mqttConnecting),
          ),
          if (widget.deviceId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white54, size: 22),
              onPressed: _confirmAndDeleteDevice,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Online / Offline badge ──────────────────────────
              _OnlineBadge(isOnline: _isOnline),

              const SizedBox(height: 28),

              // ── Central status card ────────────────────────────
              _buildStatusCard(si),

              const SizedBox(height: 32),

              // ── Control buttons ────────────────────────────────
              _buildStartButton(),
              const SizedBox(height: 14),
              _buildStopButton(),

              const SizedBox(height: 28),

              // ── Refresh status ─────────────────────────────────
              _buildRefreshTile(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────

  Widget _buildStatusCard(_StateInfo si) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: si.color.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: si.color.withOpacity(0.12),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          // Pulsing icon ring
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, child) => Transform.scale(
              scale: _isRunning ? _pulseAnimation.value : 1.0,
              child: child,
            ),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: si.color.withOpacity(0.12),
                border: Border.all(color: si.color.withOpacity(0.4), width: 2),
              ),
              child: Icon(si.icon, color: si.color, size: 44),
            ),
          ),

          const SizedBox(height: 20),

          // State label
          Text(
            si.label,
            style: TextStyle(
              color: si.color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            _isOnline ? 'Last update received' : 'No signal from robot',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    final canStart = _mqttConnected && !_isSending && !_isRunning;
    return GestureDetector(
      onTap: canStart ? _sendStart : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 62,
        decoration: BoxDecoration(
          gradient: canStart
              ? const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: canStart ? null : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          boxShadow: canStart
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSending)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white)),
              )
            else
              Icon(Icons.play_arrow_rounded,
                  color: canStart ? Colors.white : Colors.white24, size: 28),
            const SizedBox(width: 10),
            Text(
              'Start Cycle',
              style: TextStyle(
                color: canStart ? Colors.white : Colors.white24,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopButton() {
    final canStop = _mqttConnected && !_isSending && _isRunning;
    return GestureDetector(
      onTap: canStop ? _sendStop : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 62,
        decoration: BoxDecoration(
          gradient: canStop
              ? const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: canStop ? null : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          boxShadow: canStop
              ? [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withOpacity(0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stop_rounded,
                color: canStop ? Colors.white : Colors.white24, size: 28),
            const SizedBox(width: 10),
            Text(
              'Stop',
              style: TextStyle(
                color: canStop ? Colors.white : Colors.white24,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshTile() {
    return GestureDetector(
      onTap: _mqttConnected ? _requestStatus : null,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Icon(Icons.refresh_rounded,
                color: _mqttConnected
                    ? const Color(0xFFF97316)
                    : Colors.white24,
                size: 22),
            const SizedBox(width: 12),
            Text(
              'Refresh Status',
              style: TextStyle(
                color: _mqttConnected ? Colors.white70 : Colors.white24,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small helper widgets ───────────────────────────────────────────────────

class _StateInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _StateInfo(this.label, this.icon, this.color);
}

/// Green dot / amber spinner / red dot based on MQTT connection state
class _MqttDot extends StatelessWidget {
  final bool connected;
  final bool connecting;
  const _MqttDot({required this.connected, required this.connecting});

  @override
  Widget build(BuildContext context) {
    if (connecting) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
        ),
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        boxShadow: [
          BoxShadow(
            color: (connected ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                .withOpacity(0.6),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

/// "Online" / "Offline" pill badge based on whether the robot sends status messages
class _OnlineBadge extends StatelessWidget {
  final bool isOnline;
  const _OnlineBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isOnline
              ? const Color(0xFF10B981).withOpacity(0.12)
              : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isOnline
                ? const Color(0xFF10B981).withOpacity(0.4)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline
                    ? const Color(0xFF10B981)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isOnline ? 'Robot Online' : 'Robot Offline',
              style: TextStyle(
                color: isOnline
                    ? const Color(0xFF10B981)
                    : const Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
