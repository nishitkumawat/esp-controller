import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService instance = MqttService._internal();
  MqttService._internal();
  factory MqttService() => instance;

  // EMQX MQTT Broker with TLS
  final String broker = "mqtt.ezrun.in";
  final int port = 8883;
  final String mqttUser = "nk";
  final String mqttPass = "9898434411";

  MqttServerClient? _client;
  bool _isConnecting = false;
  
  bool _isAutoReconnecting = false;
  Timer? _reconnectTimer;

  // Stream for incoming messages
  final _updatesController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get updates => _updatesController.stream;

  Future<void> connect({bool isAuto = false}) async {
    if (_isConnecting) return;
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    _isConnecting = true;
    if (!isAuto) print("[MQTT] Connecting via TCP/TLS (port $port)...");

    try {
      final clientId = "app_${DateTime.now().millisecondsSinceEpoch % 999999}";

      // Create client
      _client = MqttServerClient.withPort(broker, clientId, port);
      _client!.logging(on: false);
      _client!.secure = true;
      _client!.onBadCertificate = (dynamic certificate) => true;
      _client!.keepAlivePeriod = 60;
      _client!.autoReconnect = true; // Library support, but we add custom too

      _client!.onConnected = () {
        print("[MQTT] Connected ✓");
        _isConnecting = false;
        _isAutoReconnecting = false;
        _reconnectTimer?.cancel();
      };

      _client!.onDisconnected = () {
        print("[MQTT] Disconnected");
        _isConnecting = false;
        _handleAutoReconnect();
      };

      _client!.setProtocolV311();

      final connMessage = MqttConnectMessage()
          .authenticateAs(mqttUser, mqttPass)
          .withClientIdentifier(clientId)
          .withWillTopic('willtopic')
          .withWillMessage('Will message')
          .startClean() // Clean session to ensure no stale state
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      await _client!.connect();
      
      if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
         print("[MQTT] Connection successful!");
         
         // Re-subscribe to essential topics immediately if needed
         // Note: Logic in pages often subscribes. We might need a way to resubscribe.
         // For now, simpler app logic relies on page `init` or re-calling subscribe.
         // Improved approach: Keep a list of subscribed topics and re-sub here.
         
         _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final recMess = c[0].payload as MqttPublishMessage;
          final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          final topic = c[0].topic;
          
          print("[MQTT] Received on $topic: $pt");
          _updatesController.add({'topic': topic, 'message': pt});
        });
      }

    } catch (e) {
      print("[MQTT] Connection ERROR: $e");
      _isConnecting = false;
      _handleAutoReconnect();
    }
  }

  void _handleAutoReconnect() {
    if (_isAutoReconnecting) return;
    _isAutoReconnecting = true;
    print("[MQTT] Connection lost/failed. Auto-reconnecting in 5s...");
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
        _isAutoReconnecting = false; // Reset flag to allow connect() to run
        connect(isAuto: true);
    });
  }
  
  Future<void> send(String deviceCode, String command) async {
    // Map UI commands to Arduino commands
    String actualCommand;
    if (command == "OPEN") {
      actualCommand = "OPEN";
    } else if (command == "CLOSE") {
      actualCommand = "CLOSE";
    } else if (command == "WASH_NOW") {
       actualCommand = "WASH_NOW";
    } else if (command == "WASH_STOP") {
       actualCommand = "WASH_STOP";
    } else {
      actualCommand = "STOP";
    }

    String topicPrefix = "shutter";
    if (deviceCode.length > 3) {
      final type = deviceCode.substring(1, 3).toUpperCase();
      if (type == "CS" || type == "OC") {
        topicPrefix = "solar";
      }
    }

    final topic = "$topicPrefix/$deviceCode/cmd";

    print(
      "[MQTT] Sending command: UI='$command' → ESP32='$actualCommand' to device: $deviceCode (Topic: $topic)",
    );

    try {
      // Ensure connection before sending
      if (_client == null ||
          _client!.connectionStatus?.state != MqttConnectionState.connected) {
        print("[MQTT] Not connected, establishing connection...");
        await connect();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (_client == null ||
          _client!.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception("MQTT connection failed.");
      }

      // Send only the actual command
      final builder = MqttClientPayloadBuilder()..addString(actualCommand);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

      print("[MQTT] Sent: $actualCommand → $topic");
      print("[MQTT] Command sent successfully!");
    } catch (e) {
      print("[MQTT] Send failed: $e");
      _client?.disconnect();
      _client = null;
      throw Exception("Failed to send command: ${e.toString()}");
    }
  }

  Future<void> setPin(String deviceCode, String newPin) async {
    print("[MQTT] Setting PIN for device: $deviceCode");

    try {
      // Ensure connection
      if (_client == null ||
          _client!.connectionStatus?.state != MqttConnectionState.connected) {
        print("[MQTT] Not connected, establishing connection...");
        await connect();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (_client == null ||
          _client!.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception("MQTT connection failed.");
      }

      final topic = "shutter/$deviceCode/password";
      
      final builder = MqttClientPayloadBuilder()..addString(newPin);
      
      // Publish with Retain = true
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: true);

      print("[MQTT] PIN set successfully: $newPin → $topic (Retained)");
    } catch (e) {
      print("[MQTT] Set PIN failed: $e");
      _client?.disconnect();
      _client = null;
        throw Exception("Failed to set PIN: ${e.toString()}");
    }
  }

  Future<void> publish(String topic, String message, {bool retain = false}) async {
    try {
      if (_client == null ||
          _client!.connectionStatus?.state != MqttConnectionState.connected) {
        await connect();
      }

      if (_client != null &&
          _client!.connectionStatus?.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder()..addString(message);
        _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
        print("[MQTT] Published to $topic: $message");
      } else {
        throw Exception("MQTT Client not connected");
      }
    } catch (e) {
      print("[MQTT] Publish failed: $e");
      rethrow;
    }
  }

  Future<void> subscribe(String topic) async {
    // If currently connecting, wait until finished
    int waitLimit = 0;
    while (_isConnecting && waitLimit < 50) { // Max 5s wait
      await Future.delayed(const Duration(milliseconds: 100));
      waitLimit++;
    }

    // If disconnected, try to connect first
    if (_client == null ||
        _client!.connectionStatus?.state != MqttConnectionState.connected) {
        await connect();
        
        // Wait again if connect() started a new connection attempt
        waitLimit = 0;
        while (_isConnecting && waitLimit < 50) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitLimit++;
        }
    }
    
    if (_client != null && _client!.connectionStatus?.state == MqttConnectionState.connected) {
         print("[MQTT] Subscribing to $topic");
        _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _client?.disconnect();
    _client = null;
    _isConnecting = false;
    _isAutoReconnecting = false;
    print("[MQTT] Disconnected manually");
  }

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  bool get isConnecting => _isConnecting;
}