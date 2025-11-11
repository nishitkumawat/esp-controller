import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final String broker = "broker.hivemq.com";
  final int port = 1883;

  MqttServerClient? client;
  bool _isConnecting = false;

  Future<void> connect() async {
    // Prevent reconnect loops
    if (_isConnecting ||
        (client != null &&
            client!.connectionStatus?.state == MqttConnectionState.connected)) {
      return;
    }

    _isConnecting = true;

    // ✅ Keep clientId short (< 23 chars) for HiveMQ
    final String clientId =
        "mm_${DateTime.now().millisecondsSinceEpoch % 999999}";

    client = MqttServerClient(broker, clientId);
    client!.port = port;
    client!.keepAlivePeriod = 20;
    client!.autoReconnect = true; // ✅ auto-reconnect enabled
    client!.resubscribeOnAutoReconnect = true;
    client!.logging(on: false);

    client!.onDisconnected = () {
      print("[MQTT] Disconnected");
      _isConnecting = false;
    };

    // ✅ Correct Connect Message (VERY IMPORTANT!)
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atMostOnce)
        .keepAliveFor(20)
        .startClean();

    client!.connectionMessage = connMessage;

    try {
      await client!.connect();
      print("[MQTT] Connected ✅");
    } catch (e) {
      print("[MQTT] Connection failed: $e ❌");
      client!.disconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> send(String deviceCode, String command) async {
    try {
      // Ensure MQTT connected
      if (client == null ||
          client!.connectionStatus?.state != MqttConnectionState.connected) {
        await connect();
      }

      final topic = "shutter/$deviceCode/cmd";

      // ✅ Always send STOP first
          {
        final stopPayload = MqttClientPayloadBuilder()..addString("STOP");
        client!.publishMessage(topic, MqttQos.atLeastOnce, stopPayload.payload!);
        print('[MQTT] Sent "STOP" → $topic ✅');
      }

      // Small delay so Arduino executes STOP before next command
      await Future.delayed(const Duration(milliseconds: 180));

      // ✅ Then send requested command (OPEN / CLOSE / STOP)
          {
        final cmdPayload = MqttClientPayloadBuilder()..addString(command);
        client!.publishMessage(topic, MqttQos.atLeastOnce, cmdPayload.payload!);
        print('[MQTT] Sent "$command" → $topic ✅');
      }

    } catch (e) {
      print("[MQTT] Error sending: $e ❌");
    }
  }

  void disconnect() {
    client?.disconnect();
    client = null;
    print("[MQTT] Disconnected manually");
  }
}

