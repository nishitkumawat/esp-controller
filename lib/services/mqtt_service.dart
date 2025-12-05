import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService instance = MqttService._internal();
  MqttService._internal();
  factory MqttService() => instance;

  // EMQX MQTT Broker with TLS
  final String broker = "r11ab6d2.ala.asia-southeast1.emqxsl.com";
  final int port = 8883;
  final String mqttUser = "nk";
  final String mqttPass = "9898434411";

  MqttServerClient? _client;
  bool _isConnecting = false;

  Future<void> connect() async {
    if (_isConnecting) return;
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    _isConnecting = true;
    print("[MQTT] Connecting via TCP/TLS (port $port)...");

    try {
      final clientId = "app_${DateTime.now().millisecondsSinceEpoch % 999999}";

      // Create client
      _client = MqttServerClient.withPort(broker, clientId, port);
      _client!.logging(on: false);
      _client!.secure = true;
      _client!.onBadCertificate = (dynamic certificate) => true;

      _client!.onConnected = () {
        print("[MQTT] Connected ✓");
        _isConnecting = false;
      };

      _client!.onDisconnected = () {
        print("[MQTT] Disconnected");
        _isConnecting = false;
      };

      _client!.setProtocolV311();

      final connMessage = MqttConnectMessage()
          .authenticateAs(mqttUser, mqttPass)
          .withClientIdentifier(clientId)
          .keepAliveFor(60)
          .withWillTopic('willtopic')
          .withWillMessage('Will message')
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      print("[MQTT] Attempting connection to $broker:$port");
      await _client!.connect();
      print("[MQTT] Connection successful!");
    } catch (e) {
      print("[MQTT] Connection ERROR: $e");
      _isConnecting = false;
      _client?.disconnect();
      _client = null;
      rethrow;
    }
  }

  Future<void> send(String deviceCode, String command) async {
    // Map UI commands to Arduino commands
    String actualCommand;
    if (command == "OPEN") {
      actualCommand = "OPEN";
    } else if (command == "CLOSE") {
      actualCommand = "CLOSE";
    } else {
      actualCommand = "STOP";
    }

    print(
      "[MQTT] Sending command: UI='$command' → ESP32='$actualCommand' to device: $deviceCode",
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

      final topic = "shutter/$deviceCode/cmd";

      // Send only the actual command (NO STOP prefix needed!)
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

  void disconnect() {
    _client?.disconnect();
    _client = null;
    _isConnecting = false;
    print("[MQTT] Disconnected manually");
  }

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  bool get isConnecting => _isConnecting;
}
