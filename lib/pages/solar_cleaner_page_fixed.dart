import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import '../services/mqtt_service_factory.dart';
import '../services/api_service.dart';
import '../widgets/weather_background.dart';
import '../widgets/solar_house_illustration.dart';
import '../widgets/power_circle_display.dart';

class SolarCleanerPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId;
  final bool isAdmin;

  const SolarCleanerPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
    this.isAdmin = false,
  });

  @override
  State<SolarCleanerPage> createState() => _SolarCleanerPageState();
}

class _SolarCleanerPageState extends State<SolarCleanerPage>
    with SingleTickerProviderStateMixin {
  late final dynamic _mqttService;
  final ApiService _apiService = ApiService();
  
  // Real-time Data
  bool _isSending = false;
  StreamSubscription? _subscription;
  
  Map<String, dynamic>? _lastWashBefore;
  Map<String, dynamic>? _lastWashAfter;
  
  // Location & Temperature (from backend)
  Map<String, dynamic>? _locationData;
  double _currentPower = 0.0;
  int _weatherCode = 0;
  
  // Timer Settings
  final TextEditingController _timerController = TextEditingController(text: "24");

  // Chart Data
  List<dynamic> _chartData = [];
  bool _isLoadingStats = false;
  String _selectedPeriod = 'day'; // 'day', 'month', 'year'

  @override
  void initState() {
    super.initState();
    _mqttService = MqttServiceFactory.getMqttService(widget.deviceCode);
    _setupMqtt();
    _fetchStats();
  }

  Future<void> _setupMqtt() async {
    final prefix = "solar/${widget.deviceCode}/data";
    final topicBefore = "$prefix/before_wash";
    final topicAfter = "$prefix/after_wash";

    try {
      if (!_mqttService.isConnected) {
        await _mqttService.connect();
      }
      await _mqttService.subscribe(topicBefore);
      await _mqttService.subscribe(topicAfter);
    } catch (e) {
      print("Error subscribing: $e");
    }

    _subscription = _mqttService.updates.listen((Map<String, String> event) {
      if (!mounted) return;
      final topic = event['topic'];
      final message = event['message'];
      
      if (topic == null || message == null) return;
      
      try {
        if (topic == topicBefore || topic == topicAfter || topic.contains('hourly')) {
          _fetchStats();
        }
      } catch (e) {
        print("Error parsing MQTT: $e");
      }
    });
  }

  // ... [rest of the methods remain the same] ...

  Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    int index = value.toInt();
    if (index < 0 || index >= _chartData.length) return const SizedBox.shrink();
    
    final data = _chartData[index];
    String label = data['time']?.toString() ?? '';
    
    // Skip some labels if there are too many data points
    final interval = _getLabelInterval();
    if (index % interval.ceil() != 0 && index != _chartData.length - 1) {
      return const SizedBox.shrink();
    }
    
    // For the last data point, show the label if it's the only one visible
    if (index == _chartData.length - 1 && _chartData.length > 1) {
      final prevIndex = (index - interval).clamp(0, _chartData.length - 1);
      if ((index - prevIndex) < interval / 2) {
        return const SizedBox.shrink();
      }
    }
    
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.grey),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildParamCard(String title, Map<String, dynamic>? data, Color color) {
    if (data == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
        ),
        // ... rest of the widget
      );
    }
    // ... rest of the method
    return Container(); // Placeholder
  }
  
  Widget _row(String k, String v, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(
          child: Text(k, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2C3E50))),
      ],
    );
  }
}
