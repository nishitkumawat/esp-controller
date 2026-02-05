import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'api_service.dart';

class HiveMqttService {
  static final HiveMqttService instance = HiveMqttService._internal();

  HiveMqttService._internal();

  factory HiveMqttService() => instance;
  
  final String broker = "broker.hivemq.com";
  final int port = 1883;

  MqttServerClient? client;
  bool _isConnecting = false;

  Future<void> connect() async {
    if (_isConnecting ||
        (client != null &&
            client!.connectionStatus?.state == MqttConnectionState.connected)) {
      return;
    }

    _isConnecting = true;
    final String clientId = "mm_${DateTime.now().millisecondsSinceEpoch % 999999}";

    client = MqttServerClient(broker, clientId);
    client!.port = port;
    client!.keepAlivePeriod = 20;
    client!.autoReconnect = true;
    client!.resubscribeOnAutoReconnect = true;
    client!.logging(on: false);

    client!.onDisconnected = () {
      print("[HiveMQ] Disconnected");
      _isConnecting = false;
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atMostOnce)
        .keepAliveFor(20)
        .startClean();

    client!.connectionMessage = connMessage;

    try {
      await client!.connect();
      print("[HiveMQ] Connected ✅");
    } catch (e) {
      print("[HiveMQ] Connection failed: $e ❌");
      client!.disconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> send(String deviceCode, String command) async {
    try {
      if (client == null ||
          client!.connectionStatus?.state != MqttConnectionState.connected) {
        await connect();
      }

      if (client == null ||
          client!.connectionStatus?.state != MqttConnectionState.connected) {
        print("[HiveMQ] Still not connected, aborting send ❌");
        return;
      }

      String topicPrefix = "shutter";
      if (deviceCode.length > 3) {
        final type = deviceCode.substring(1, 3).toUpperCase();
        
        // Check if we need to consult the API for an override
        String toConsider = type;
        try {
          final apiRes = await ApiService().getDeviceType(deviceCode: deviceCode);
          if (apiRes['status'] == true && apiRes['to_consider'] != null) {
            toConsider = apiRes['to_consider'].toString().toUpperCase();
            print("[HiveMQ] Device $deviceCode override fetched: $toConsider");
          }
        } catch (e) {
          print("[HiveMQ] Failed to fetch device override, using prefix: $e");
        }

        if (type == "CS" || type == "OC" || toConsider == "CS" || toConsider == "OC") {
          topicPrefix = "solar";
        }
      }

      final topic = "$topicPrefix/$deviceCode/cmd";

      // Send STOP first
      final stopPayload = MqttClientPayloadBuilder()..addString("STOP");
      client!.publishMessage(topic, MqttQos.atLeastOnce, stopPayload.payload!);
      print('[HiveMQ] Sent "STOP" → $topic ✅');

      // Small delay before sending the actual command
      await Future.delayed(const Duration(milliseconds: 80));

      // Send the actual command
      final cmdPayload = MqttClientPayloadBuilder()..addString(command);
      client!.publishMessage(topic, MqttQos.atLeastOnce, cmdPayload.payload!);
      print('[HiveMQ] Sent "$command" → $topic ✅');

    } catch (e) {
      print("[HiveMQ] Error sending: $e ❌");
      rethrow;
    }
  }

  void disconnect() {
    client?.disconnect();
    client = null;
    print("[HiveMQ] Disconnected manually");
  }

  bool get isConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;
  bool get isConnecting => _isConnecting;
}
