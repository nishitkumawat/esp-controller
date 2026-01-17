import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import '../services/mqtt_service_factory.dart';
import '../services/api_service.dart';
import '../widgets/weather_background.dart';
import '../widgets/solar_house_illustration.dart';
import '../widgets/power_circle_display.dart';
import 'home_page.dart';
import 'alerts_page.dart';

class SolarCleanerPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId;
  final bool isAdmin;
  final bool skipInitialLoading;

  const SolarCleanerPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
    this.isAdmin = false,
    this.skipInitialLoading = false,
  });

  @override
  State<SolarCleanerPage> createState() => _SolarCleanerPageState();
}

class _SolarCleanerPageState extends State<SolarCleanerPage>
    with SingleTickerProviderStateMixin {
  late final dynamic _mqttService;
  final ApiService _apiService = ApiService();
  late String _deviceName;
  
  // Real-time Data
  bool _isSending = false;
  StreamSubscription? _subscription;
  
  Map<String, dynamic>? _lastWashBefore;
  Map<String, dynamic>? _lastWashAfter;
  
  // Location & Temperature (from backend)
  Map<String, dynamic>? _locationData; // {city: "...", state: "...", temperature: ..., lat: ..., lon: ..., weather_code: ...}
  double _currentPower = 0.0;
  int _weatherCode = 0; // Default to clear sky
  
  // Timer Settings
  final TextEditingController _timerController = TextEditingController(text: "24");

  // Chart Data
  List<dynamic> _chartData = [];
  bool _isLoadingStats = false;
  bool _isFirstLoad = true;
  String _selectedPeriod = 'day'; // 'day', 'month', 'year'
  DateTime _selectedDay = DateTime.now();
  DateTime _selectedMonthYear = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedYear = DateTime(DateTime.now().year);
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    _deviceName = widget.deviceName;
    _mqttService = MqttServiceFactory.getMqttService(widget.deviceCode);
    if (widget.skipInitialLoading) {
      _isFirstLoad = false;
    }
    _loadInitialData();
  }

  void _goToHomeTab(int index) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
      (route) => false,
    );
  }

  void _openCupertinoYearPicker({
    required String title,
    required int initialYear,
    required ValueChanged<int> onDone,
  }) {
    final int currentYear = DateTime.now().year;
    final int startYear = 2000;
    final years = List<int>.generate(
      (currentYear - startYear) + 1,
      (i) => startYear + i,
    );
    int tempYear = initialYear.clamp(startYear, currentYear);
    final int initialIndex = years.indexOf(tempYear);
    final controller = FixedExtentScrollController(initialItem: initialIndex < 0 ? 0 : initialIndex);

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return Container(
          height: 340,
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
                    ),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onDone(tempYear);
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 36,
                    onSelectedItemChanged: (index) {
                      if (index < 0 || index >= years.length) return;
                      tempYear = years[index];
                    },
                    children: years
                        .map(
                          (y) => Center(
                            child: Text(
                              y.toString(),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _promptRenameDevice() async {
    if (!widget.isAdmin) return;
    if (widget.deviceId == null) {
      Fluttertoast.showToast(msg: 'Device id not available');
      return;
    }

    final controller = TextEditingController(text: _deviceName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit device name'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Device name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || newName == _deviceName) return;

    try {
      final response = await _apiService.renameDevice(
        deviceId: widget.deviceId!,
        newName: newName,
      );
      final ok = response['status'] == true || response['success'] == true;
      if (ok) {
        if (!mounted) return;
        setState(() {
          _deviceName = newName;
        });
      }
      Fluttertoast.showToast(
        msg: response['message']?.toString() ?? (ok ? 'Device name updated' : 'Failed to update name'),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to update name');
    }
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final height = MediaQuery.of(context).size.height;
        return SizedBox(
          height: height * 0.52,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_none_rounded),
                      title: const Text('Alerts'),
                      subtitle: const Text('Coming soon'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(this.context).push(
                          MaterialPageRoute(builder: (_) => const AlertsPage()),
                        );
                      },
                    ),
                    if (widget.isAdmin)
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('Edit device name'),
                        subtitle: Text(_deviceName),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _promptRenameDevice();
                        },
                      ),
                    if (widget.deviceId != null)
                      ListTile(
                        leading: const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('Delete device', style: TextStyle(color: Colors.red)),
                        subtitle: const Text('Remove this device from your account'),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _confirmAndDeleteDevice();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadInitialData() async {
    // Start both fetching stats and setting up MQTT
    // We want to show the loading screen until data is fetched OR 5 seconds pass
    try {
      await Future.any([
        Future.wait([
          _setupMqtt(),
          _fetchStats(),
        ]),
        Future.delayed(const Duration(seconds: 5)),
      ]);
    } catch (e) {
      print("Error during initial load: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isFirstLoad = false;
        });
      }
    }
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
             // Refresh stats from Backend (includes location and temperature)
             _fetchStats();
         }
      } catch (e) {
        print("Error parsing MQTT: $e");
      }
    });
  }




  Future<void> _fetchStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    try {
      // Get the latest solar data for the center circle
      final latestData = await _apiService.getLatestSolarData(
        deviceCode: widget.deviceCode,
      );
      
      // Get the historical data for the chart
      final res = await _apiService.getSolarStats(
        deviceCode: widget.deviceCode, 
        period: _selectedPeriod
      );
      
      if (mounted) {
        setState(() {
          // Update chart data
          _chartData = res['data'] ?? [];
          final wash = res['wash'] ?? {};
          _lastWashBefore = wash['before'];
          _lastWashAfter = wash['after'];
          _locationData = res['location']; // {city, state, lat, lon, temperature, weather_code}
          
          // Update current power from the latest data
          if (latestData.isNotEmpty) {
            _currentPower = (latestData['power'] ?? 0).toDouble();
          } else if (res['current_power'] != null) {
            // Fallback to the old way if latest data is not available
            _currentPower = (res['current_power'] ?? 0).toDouble();
          }
          
          _weatherCode = _locationData?['weather_code'] ?? 0;
        });
      }
    } catch (e) {
      print("Error fetching stats: $e");
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Error updating data: ${e.toString()}",
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timerController.dispose();
    super.dispose();
  }

  Future<void> _sendWashCommand() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      await _mqttService.send(widget.deviceCode, "WASH_NOW");
      Fluttertoast.showToast(msg: "WASH Command Sent ✅", backgroundColor: Colors.green, textColor: Colors.white);
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed: $e", backgroundColor: Colors.red, textColor: Colors.white);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendStopCommand() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      await _mqttService.send(widget.deviceCode, "WASH_STOP");
      Fluttertoast.showToast(
        msg: "STOP Command Sent 🛑",
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed: $e",
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _setTimer() async {
     try {
       int hours = int.parse(_timerController.text);
       if (hours <= 0) throw Exception("Invalid hours");
       await _mqttService.send(widget.deviceCode, "SET_INTERVAL hours $hours");
       Fluttertoast.showToast(msg: "Timer Set to $hours hrs ", backgroundColor: Colors.green, textColor: Colors.white);
     } catch (e) {
       Fluttertoast.showToast(msg: "Invalid Input: $e");
     }
  }
  
  Future<void> _confirmAndDeleteDevice() async {
     if (widget.deviceId == null) return;
      final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Device'),
          content: const Text('Are you sure you want to remove this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.deleteDevice(deviceId: widget.deviceId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      Fluttertoast.showToast(msg: "Error removing device");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstLoad) {
      return _buildFirstLoadScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A3A5C),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'EZrun',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3A5C).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _deviceName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.deviceCode,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Devices'),
                onTap: () => _goToHomeTab(0),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Add device'),
                onTap: () => _goToHomeTab(1),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Account'),
                onTap: () => _goToHomeTab(2),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _deviceName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.deviceCode,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: WeatherBackground(
        weatherCode: _weatherCode,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Weather Hero Section
              _buildWeatherHeroSection(),
              
              // White content section
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatTile(
                              title: 'Yield',
                              primary: '${_getTodayEnergy().toStringAsFixed(1)} W',
                              secondary: 'Today',
                              icon: Icons.solar_power_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatTile(
                              title: 'Power',
                              primary: '${_currentPower.toStringAsFixed(1)} W',
                              secondary: 'Now',
                              icon: Icons.bolt_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildStatTile(
                        title: 'Weather',
                        primary: _locationData != null && _locationData!['temperature'] != null
                            ? '${_locationData!['temperature']}°C'
                            : '--',
                        secondary: _locationData != null && _locationData!['city'] != null
                            ? '${_locationData!['city']}, ${_locationData!['state']}'
                            : 'Location',
                        icon: Icons.cloud_outlined,
                      ),
                      const SizedBox(height: 20),
                      // Controls
                      _buildControlsSection(),
                      const SizedBox(height: 24),
                      
                      // Hourly Power Chart
                      _buildGraphSection(),
                      const SizedBox(height: 24),
                      
                      // Wash Details
                      const Text("Last Wash Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2C3E50))),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildParamCard("Before Wash", _lastWashBefore, const Color(0xFF5DADE2))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildParamCard("After Wash", _lastWashAfter, const Color(0xFF27AE60))),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String title,
    required String primary,
    required String secondary,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF1E88E5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  primary,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2C3E50),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  secondary,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _getTodayEnergy() {
    if (_selectedPeriod != 'day' || _chartData.isEmpty) return 0.0;
    double total = 0.0;
    for (var item in _chartData) {
      total += (item['power'] ?? 0).toDouble();
    }
    return total;
  }

  String _getWeatherDescription() {
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 19;
    final timeOfDay = isNight ? "Night" : (hour < 12 ? "Morning" : (hour < 17 ? "Afternoon" : "Evening"));

    if (_weatherCode == 0) {
      return isNight ? "Clear $timeOfDay" : "Sunny $timeOfDay";
    } else if (_weatherCode <= 3) {
      return "Partly Cloudy $timeOfDay";
    } else if (_weatherCode <= 48) {
      return "Cloudy $timeOfDay";
    } else if (_weatherCode >= 51 && _weatherCode <= 67) {
      return "Rainy $timeOfDay";
    } else if (_weatherCode >= 71 && _weatherCode <= 77) {
      return "Snowy $timeOfDay";
    } else if (_weatherCode >= 80) {
      return "Stormy $timeOfDay";
    }
    return "$timeOfDay Sky";
  }

  Widget _buildWeatherHeroSection() {
    // Determine if it's night for text color
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 19;
    final textColor = isNight ? Colors.white : Colors.black87;
    final subtextColor = isNight ? Colors.white70 : Colors.black54;
    
    return SizedBox(
      height: 650, // Increased height to prevent overlap
      child: Stack(
        children: [
          // Production Today - top-left
          Positioned(
            top: 110,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Production Today",
                  style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  "${_getTodayEnergy().toStringAsFixed(1)} W",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Weather Description badge - top-right
          Positioned(
            top: 110,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _weatherCode <= 2 ? Icons.wb_sunny : (_weatherCode <= 3 ? Icons.wb_cloudy : Icons.cloud),
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getWeatherDescription(),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),

          // Location badge - below production
          Positioned(
            top: 155,
            left: 16,
            child: (_locationData != null && _locationData!['city'] != "Unknown")
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        "${_locationData!['city']}, ${_locationData!['state']}",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
          ),

          // Temperature badge - top-right below weather
          if (_locationData != null && _locationData!['temperature'] != null)
            Positioned(
              top: 155,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.thermostat, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      "${_locationData!['temperature']}°C",
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // Power Circle in Center
          Positioned(
            top: 220,
            left: 0,
            right: 0,
            child: PowerCircleDisplay(
              power: _currentPower,
            ),
          ),

          // Solar House Illustration at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SolarHouseIllustration(
              currentPower: _currentPower,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildControlsSection() {
    return Column(
      children: [
        // Wash Buttons
        Row(
           children: [
             Expanded(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: const Color(0xFF1E88E5),
                   foregroundColor: Colors.white,
                   padding: const EdgeInsets.symmetric(vertical: 18),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   elevation: 3,
                   shadowColor: const Color(0xFF1E88E5).withOpacity(0.3),
                 ),
                 onPressed: _isSending ? null : _sendWashCommand,
                 icon: _isSending 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cleaning_services, size: 22), 
                 label: const Text("START WASH", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
               ),
             ),
             const SizedBox(width: 12),
             Expanded(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.white,
                   foregroundColor: const Color(0xFFE74C3C),
                   padding: const EdgeInsets.symmetric(vertical: 18),
                   side: BorderSide(color: const Color(0xFFE74C3C).withOpacity(0.3), width: 1.5),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   elevation: 2,
                   shadowColor: Colors.black.withOpacity(0.1),
                 ),
                 onPressed: _isSending ? null : _sendStopCommand,
                 icon: const Icon(Icons.stop_circle_outlined, size: 22),
                 label: const Text("STOP", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
               ),
             ),
           ],
        ),
        const SizedBox(height: 16),
        // Timer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.schedule, color: Color(0xFF1E88E5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _timerController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "Interval (hours)",
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              TextButton(
                onPressed: _setTimer,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5).withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("SET", style: TextStyle(color: Color(0xFF1E88E5), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildGraphSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.show_chart_rounded,
                    color: Color(0xFF1E88E5),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Power generation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _openGraphPicker,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getGraphRangeLabel(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2C3E50),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade700),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildPeriodPills(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 240,
              child: _isLoadingStats
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF1E88E5)),
                    )
                  : _chartData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.insights_outlined, size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 10),
                              Text(
                                'No data',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : _buildScrollableChart(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _segmentBtn(String label, String val) {
     bool selected = _selectedPeriod == val;
     return Expanded(
       child: GestureDetector(
         onTap: () {
            setState(() => _selectedPeriod = val);
            _touchedIndex = null;
            _fetchStats();
         },
         child: AnimatedContainer(
           duration: const Duration(milliseconds: 250),
           padding: const EdgeInsets.symmetric(vertical: 12),
           decoration: BoxDecoration(
             color: selected ? Colors.white : Colors.transparent,
             borderRadius: BorderRadius.circular(10),
             boxShadow: selected ? [
               BoxShadow(
                 color: const Color(0xFF1E88E5).withOpacity(0.15),
                 blurRadius: 8,
                 offset: const Offset(0, 2),
               )
             ] : [],
           ),
           child: Text(
             label,
             textAlign: TextAlign.center,
             style: TextStyle(
               fontWeight: selected ? FontWeight.bold : FontWeight.w500,
               color: selected ? const Color(0xFF1E88E5) : Colors.grey.shade600,
               fontSize: 14,
           )),
         ),
       ),
     );
  }

  Widget _buildPeriodPills() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill('Day', 'day'),
          _pill('Month', 'month'),
          _pill('Year', 'year'),
        ],
      ),
    );
  }

  Widget _pill(String label, String val) {
    final selected = _selectedPeriod == val;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPeriod = val;
          _touchedIndex = null;
        });
        _fetchStats();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1E88E5).withOpacity(0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: selected ? const Color(0xFF1E88E5) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  String _getGraphRangeLabel() {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (_selectedPeriod == 'day') {
      return '${_selectedDay.day} ${months[_selectedDay.month - 1]} ${_selectedDay.year}';
    }
    if (_selectedPeriod == 'month') {
      return '${months[_selectedMonthYear.month - 1]} ${_selectedMonthYear.year}';
    }
    return '${_selectedYear.year}';
  }

  void _openGraphPicker() {
    if (_selectedPeriod == 'day') {
      _openCupertinoDatePicker(
        title: _getGraphRangeLabel(),
        mode: CupertinoDatePickerMode.date,
        initialDateTime: _selectedDay,
        onDone: (value) {
          setState(() {
            _selectedDay = value;
            _touchedIndex = null;
          });
          _fetchStats();
        },
      );
      return;
    }

    if (_selectedPeriod == 'month') {
      _openCupertinoDatePicker(
        title: _getGraphRangeLabel(),
        mode: CupertinoDatePickerMode.monthYear,
        initialDateTime: _selectedMonthYear,
        onDone: (value) {
          setState(() {
            _selectedMonthYear = DateTime(value.year, value.month);
            _touchedIndex = null;
          });
          _fetchStats();
        },
      );
      return;
    }

    _openCupertinoYearPicker(
      title: _getGraphRangeLabel(),
      initialYear: _selectedYear.year,
      onDone: (year) {
        setState(() {
          _selectedYear = DateTime(year);
          _touchedIndex = null;
        });
        _fetchStats();
      },
    );
  }

  void _openCupertinoDatePicker({
    required String title,
    required CupertinoDatePickerMode mode,
    required DateTime initialDateTime,
    required ValueChanged<DateTime> onDone,
  }) {
    DateTime tempValue = initialDateTime;

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return Container(
          height: 340,
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
                    ),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onDone(tempValue);
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: mode,
                    initialDateTime: initialDateTime,
                    maximumDate: DateTime.now(),
                    onDateTimeChanged: (v) {
                      tempValue = v;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildScrollableChart() {
    // Calculate required width based on data points to prevent congestion
    // e.g., 50 logical pixels per bar/point. Minimum width of screen width.
    double itemWidth = 50.0;
    if (_selectedPeriod == 'year') itemWidth = 60.0; // Wider bars for months
    
    double requiredWidth = _chartData.length * itemWidth;
    // Ensure it fills screen at least
    double screenWidth = MediaQuery.of(context).size.width - 64; // minus padding
    if (requiredWidth < screenWidth) requiredWidth = screenWidth;
  
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: requiredWidth,
        child: Padding(
          padding: const EdgeInsets.only(right: 16.0, bottom: 8.0, top: 10.0),
          child: _selectedPeriod == 'day' ? _buildLineChart() : _buildBarChart(),
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    if (_chartData.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(color: Colors.grey)));
    }

    List<FlSpot> spots = [];
    for (int i = 0; i < _chartData.length; i++) {
      final data = _chartData[i];
      double y = (data['power'] is num) ? (data['power'] as num).toDouble() : 0.0;
      spots.add(FlSpot(i.toDouble(), y));
    }
    
    // Calculate max Y value with some padding
    double maxY = spots.isNotEmpty ? 
        (spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.1) : 100;
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true, 
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? (maxY / 5) : 20, // Dynamic interval based on data
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.1), 
            strokeWidth: 1
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, 
              getTitlesWidget: _bottomTitleWidgets, 
              reservedSize: 30, 
              interval: _getLabelInterval()
            )
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, 
              reservedSize: 40, 
              interval: maxY > 0 ? (maxY / 5) : 20,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: Text(
                  "${value.toInt()}", 
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.right,
                ),
              )
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_chartData.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            gradient: const LinearGradient(
              colors: [
                Color(0xFF58B7FF),
                Color(0xFF1E88E5),
              ],
            ),
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, barData) {
                return _touchedIndex != null && spot.x.toInt() == _touchedIndex;
              },
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 7,
                  color: Colors.white,
                  strokeWidth: 3,
                  strokeColor: const Color(0xFF9DD6FF),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true, 
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF58B7FF).withOpacity(0.55),
                  const Color(0xFF58B7FF).withOpacity(0.05),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            if (!mounted) return;
            if (response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) {
              setState(() {
                _touchedIndex = null;
              });
              return;
            }
            final idx = response.lineBarSpots!.first.spotIndex;
            setState(() {
              _touchedIndex = idx;
            });
          },
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((_) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: const Color(0xFF0F2D52).withOpacity(0.35),
                  strokeWidth: 1,
                ),
                FlDotData(show: false),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: const Color(0xFF0F2D52),
            tooltipRoundedRadius: 28,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            tooltipMargin: 18,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.spotIndex;
                if (index < 0 || index >= _chartData.length) return null;
                
                final data = _chartData[index];
                final time = data['time']?.toString() ?? '';
                final power = spot.y.toStringAsFixed(0);
                
                return LineTooltipItem(
                  '$time   $power W',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }).whereType<LineTooltipItem>().toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    if (_chartData.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(color: Colors.grey)));
    }

    List<BarChartGroupData> bars = [];
    double maxY = 0;
    
    for (int i = 0; i < _chartData.length; i++) {
      final data = _chartData[i];
      double y = (data['power'] is num) ? (data['power'] as num).toDouble() : 0.0;
      if (y > maxY) maxY = y;
      
      bars.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: y,
            color: const Color(0xFF1E88E5),
            width: _selectedPeriod == 'year' ? 30 : 20, // Wider bars for year view
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxY > 0 ? maxY * 1.1 : 100,
              color: Colors.grey.withOpacity(0.05),
            ),
          ),
        ],
        showingTooltipIndicators: [0],
      ));
    }
    
    // Add some padding to the max Y value
    maxY = maxY * 1.2;
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? (maxY / 5) : 20,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: _bottomTitleWidgets,
              reservedSize: 30,
              interval: _getLabelInterval(),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY > 0 ? (maxY / 5) : 20,
              getTitlesWidget: (value, meta) {
                if (value <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Text(
                    "${value.toInt()}",
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: bars,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: const Color(0xFF0F2D52),
            tooltipRoundedRadius: 28,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final index = group.x.toInt();
              if (index < 0 || index >= _chartData.length) return null;
              
              final data = _chartData[index];
              final time = data['time']?.toString() ?? '';
              final power = rod.toY.toStringAsFixed(1);
              
              return BarTooltipItem(
                '$time   ${power.toString()} W',
                const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
              );
            },
          ),
        ),
      ),
    );
  }
  
  // Helper method to determine label interval based on data density
  double _getLabelInterval() {
    if (_chartData.length <= 12) return 1; // Show all for year view
    if (_chartData.length <= 24) return 2; // Every 2nd for day view
    return _chartData.length / 12; // For month view, show ~12 labels
  }

  Widget _buildFirstLoadScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF1A3A5C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Solar Icon with a subtle animation or just a nice look
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.solar_power_outlined,
                size: 80,
                color: Color(0xFF58B7FF),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Gathering Solar Data...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: const LinearProgressIndicator(
                  backgroundColor: Color(0xFF102A43),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF58B7FF)),
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.insights_outlined, size: 32, color: color.withOpacity(0.5)),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              "No Data",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  title.contains("Before") ? Icons.power_outlined : Icons.check_circle_outline,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _row("Voltage", "${data['voltage']} V", Icons.bolt),
          const SizedBox(height: 8),
          _row("Current", "${data['current']} A", Icons.electric_bolt),
          const SizedBox(height: 8),
          _row("Power", "${data['power']} W", Icons.flash_on),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  data['timestamp'] != null 
                    ? data['timestamp'].toString().split('T').join(' ').substring(0, 16)
                    : '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
