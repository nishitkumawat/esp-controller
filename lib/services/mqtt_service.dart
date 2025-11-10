import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  // TODO: Update MQTT broker details
  final String broker = "broker.hivemq.com"; // Public broker - update if needed
  final int port = 1883; // TCP port
  MqttServerClient? client;
  bool _isConnecting = false;

  Future<void> connect() async {
    if (_isConnecting || 
        (client != null && 
         client!.connectionStatus?.state == MqttConnectionState.connected)) {
      return;
    }

    _isConnecting = true;
    client = MqttServerClient(
      broker,
      'flutter_${DateTime.now().millisecondsSinceEpoch}',
    );
    client!.port = port;
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;
    client!.onDisconnected = () {
      print('[MQTT] Disconnected');
      _isConnecting = false;
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier("flutter_controller")
        .startClean();

    client!.connectionMessage = connMessage;

    try {
      await client!.connect();
      print('[MQTT] Connected');
      _isConnecting = false;
    } catch (e) {
      print('[MQTT] Connection failed: $e');
      client!.disconnect();
      _isConnecting = false;
      rethrow;
    }
  }

  Future<void> send(String deviceCode, String command) async {
    try {
      if (client == null ||
          client!.connectionStatus?.state != MqttConnectionState.connected) {
        await connect();
      }

      final topic = "shutter/$deviceCode/cmd";
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);

      client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('[MQTT] Sent $command to $topic');
    } catch (e) {
      print('[MQTT] Error sending command: $e');
      rethrow;
    }
  }

  void disconnect() {
    client?.disconnect();
    client = null;
  }
}


