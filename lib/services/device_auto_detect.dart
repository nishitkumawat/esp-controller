import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:http/http.dart' as http;

class DeviceAutoDetect {
  final Connectivity _connectivity = Connectivity();

  void startListener(Function(Map<String, dynamic>) onDeviceDetected) {
    _connectivity.onConnectivityChanged.listen((status) async {
      if (status == ConnectivityResult.wifi) {
        String? ssid;
        try {
          ssid = await WiFiForIoTPlugin.getSSID();
        } catch (e) {
          print("DeviceAutoDetect: failed to get SSID: $e");
        }
        print("DeviceAutoDetect: connected to SSID: $ssid");

        if (ssid != null && ssid.startsWith("Shutter")) {
          print("DeviceAutoDetect: Shutter AP detected, fetching device-info...");

          try {
            final res = await http
                .get(Uri.parse("http://192.168.4.1/device-info"))
                .timeout(Duration(seconds: 5));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body) as Map<String, dynamic>;
              onDeviceDetected(data);
            } else {
              print("DeviceAutoDetect: device-info responded ${res.statusCode}");
            }
          } catch (e) {
            print("DeviceAutoDetect: error fetching device-info: $e");
          }
        }
      }
    });
  }
}
