import 'package:mqtt_client/mqtt_client.dart';
import 'hivemq_mqtt_service.dart';
import 'mqtt_service.dart';

class MqttServiceFactory {
  static bool isSEDevice(String deviceId) {
    // Check if device ID matches the SE pattern (2nd and 3rd characters are 'SE')
    return deviceId.length >= 3 && deviceId[1] == 'S' && deviceId[2] == 'M';
  }

  static dynamic getMqttService(String deviceId) {
    if (isSEDevice(deviceId)) {
      print("[MQTT Factory] Using HiveMQ MQTT Service for regular device: $deviceId");
      return HiveMqttService();
    } else {
       print("[MQTT Factory] Using EMQX MQTT Service for SE device: $deviceId");
      return MqttService();
    }
  }
}
