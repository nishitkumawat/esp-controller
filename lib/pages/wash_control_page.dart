import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/mqtt_service_factory.dart';
import '../services/api_service.dart';
import 'home_page.dart';

class WashControlPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId;
  final bool isAdmin;

  const WashControlPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
    this.isAdmin = false,
  });

  @override
  State<WashControlPage> createState() => _WashControlPageState();
}

class _WashControlPageState extends State<WashControlPage> with SingleTickerProviderStateMixin {
  late final dynamic _mqttService; // Using dynamic to call custom publish method if not in base class yet
  final ApiService _apiService = ApiService();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  
  // State
  bool _isSending = false;
  bool _isWashing = false;
  int _remainingSec = 0;
  Timer? _countdownTimer;

  // Manual Wash
  final int _defaultManualDurationSec = 300; // 5 mins

  // Scheduling Mode
  String _selectedMode = 'WEEKLY'; // 'WEEKLY' or 'INTERVAL'
  
  // Weekly Mode State
  TimeOfDay _selectedTime = const TimeOfDay(hour: 6, minute: 0);
  final List<String> _weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  final List<String> _weekDayKeys = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  final Set<String> _selectedDays = {};
  int _weeklyDurationMinutes = 5;

  // Interval Mode State
  String _selectedIntervalLabel = 'Every 24 hours';
  int _customIntervalHours = 24;
  int _intervalDurationMinutes = 5;

  final Map<String, int> _intervalOptions = {
    'Every 12 hours': 12,
    'Every 24 hours': 24,
    'Every 30 hours': 30,
    'Custom': -1,
  };

  @override
  void initState() {
    super.initState();
    _mqttService = MqttServiceFactory.getMqttService(widget.deviceCode);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
    
    _subscribeToStatus();
  }

  void _subscribeToStatus() {
    final statusTopic = 'solar/${widget.deviceCode}/wash/status';
    _mqttService.subscribe(statusTopic);
    _mqttService.updates.listen((event) {
      if (event['topic'] == statusTopic) {
        _handleStatusUpdate(event['message']);
      }
    });
  }

  void _handleStatusUpdate(String? message) {
    if (message == null) return;
    try {
      final data = jsonDecode(message);
      final state = data['state'];
      if (state == 'RUNNING') {
        setState(() {
          _isWashing = true;
          _remainingSec = data['remaining_sec'] ?? 0;
        });
        _startLocalTimer();
      } else {
        setState(() {
          _isWashing = false;
          _remainingSec = 0;
          _countdownTimer?.cancel();
        });
      }
    } catch (e) {
      print("Error parsing status: $e");
    }
  }

  void _startLocalTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSec > 0) {
        setState(() {
          _remainingSec--;
        });
      } else {
        timer.cancel();
        setState(() => _isWashing = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleManualWash() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      final topic = 'solar/${widget.deviceCode}/wash/manual';
      String payload;
      
      if (_isWashing) {
        // Stop
        payload = jsonEncode({"action": "STOP"});
      } else {
        // Start
        payload = jsonEncode({
          "action": "START",
          "duration_sec": _defaultManualDurationSec
        });
        // Optimistic UI update
        setState(() {
          _isWashing = true;
          _remainingSec = _defaultManualDurationSec;
        });
        _startLocalTimer();
      }

      await _mqttService.publish(topic, payload);
      Fluttertoast.showToast(msg: _isWashing ? "Stopping Wash..." : "Starting Wash...");

    } catch (e) {
      Fluttertoast.showToast(msg: "Failed: $e");
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _saveSchedule() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      if (_selectedMode == 'WEEKLY') {
        final topic = 'solar/${widget.deviceCode}/wash/schedule/weekly';
        
        // Convert TimeOfDay to HH:MM string
        final hour = _selectedTime.hour.toString().padLeft(2, '0');
        final minute = _selectedTime.minute.toString().padLeft(2, '0');
        
        final payload = jsonEncode({
          "mode": "WEEKLY",
          "time": "$hour:$minute",
          "days": _selectedDays.toList(),
          "duration_sec": _weeklyDurationMinutes * 60
        });

        await _mqttService.publish(topic, payload, retain: true);
        Fluttertoast.showToast(msg: "Weekly schedule saved ✅");
        
      } else {
        final topic = 'solar/${widget.deviceCode}/wash/schedule/interval';
        
        int hours = _selectedIntervalLabel == 'Custom' 
            ? _customIntervalHours 
            : _intervalOptions[_selectedIntervalLabel]!;

        final payload = jsonEncode({
          "mode": "INTERVAL",
          "interval_hours": hours,
          "duration_sec": _intervalDurationMinutes * 60
        });

        await _mqttService.publish(topic, payload, retain: true);
        Fluttertoast.showToast(msg: "Interval schedule saved ✅");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Save failed: $e");
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _goToHomeTab(int index) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
      (route) => false,
    );
  }

  Future<void> _confirmAndDeleteDevice() async {
      // Reuse logic from DeviceControlPage
      if (widget.deviceId == null) return;
      
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Remove Device'),
            content: Text(
              widget.isAdmin
                  ? 'Delete this device? This action cannot be undone.'
                  : 'Remove this device from your account?',
            ),
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
        Fluttertoast.showToast(msg: 'Device removed');
        if (mounted) Navigator.of(context).pop(true);
      } catch (e) {
        Fluttertoast.showToast(msg: 'Error: $e');
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: Text(widget.deviceName),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
               _subscribeToStatus();
               Fluttertoast.showToast(msg: "Refreshed status");
            },
          ),
          if (widget.deviceId != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _confirmAndDeleteDevice,
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDeviceHeader(),
              const SizedBox(height: 20),
              
              // Manual Wash Card
              _buildManualWashCard(),
              const SizedBox(height: 20),
              
              // Schedule Card
              _buildScheduleCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: const Text('Back to Home'),
              onTap: () => Navigator.pop(context),
            ),
            // ... (Simple navigation drawer)
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFA500).withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.water_drop, color: Color(0xFFFFA500), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deviceName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2C3E50)),
                ),
                Text(
                  widget.deviceCode,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualWashCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Manual Wash",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _handleManualWash,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isWashing ? Colors.red.shade100 : Colors.blue.shade50,
                  border: Border.all(
                    color: _isWashing ? Colors.red : Colors.blue,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isWashing ? Colors.red : Colors.blue).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isWashing ? Icons.stop : Icons.play_arrow,
                        size: 40,
                        color: _isWashing ? Colors.red : Colors.blue,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isWashing ? "STOP" : "START",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isWashing ? Colors.red : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isWashing)
              Text(
                "Time Remaining: ${_formatDuration(_remainingSec)}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              )
            else
              Text(
                "Last Clean: Unknown", // Could be fetched from backend if needed
                style: TextStyle(color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }
  
  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Widget _buildScheduleCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Automatic Wash Schedule",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // Mode Selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'WEEKLY', label: Text('Weekly')),
                ButtonSegment(value: 'INTERVAL', label: Text('Interval')),
              ],
              selected: {_selectedMode},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedMode = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 20),
            
            if (_selectedMode == 'WEEKLY')
              _buildWeeklySettings()
            else
              _buildIntervalSettings(),
              
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveSchedule,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C3E50),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                "SAVE TIMER",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySettings() {
    return Column(
      children: [
        // Time Picker
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: _selectedTime,
            );
            if (picked != null && picked != _selectedTime) {
              setState(() => _selectedTime = picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Wash Time:"),
                Text(
                  _selectedTime.format(context),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Days
        Wrap(
          spacing: 8,
          children: List.generate(_weekDays.length, (index) {
            final dayKey = _weekDayKeys[index];
            final isSelected = _selectedDays.contains(dayKey);
            return FilterChip(
              label: Text(_weekDays[index]),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _selectedDays.add(dayKey);
                  } else {
                    _selectedDays.remove(dayKey);
                  }
                });
              },
              checkmarkColor: Colors.white,
              selectedColor: const Color(0xFFFFA500),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        
        // Duration
        _buildDurationInput(
          label: "Duration (min)", 
          value: _weeklyDurationMinutes, 
          onChanged: (v) => setState(() => _weeklyDurationMinutes = v),
        ),
      ],
    );
  }

  Widget _buildIntervalSettings() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: 'Repeat Every',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          value: _selectedIntervalLabel,
          items: _intervalOptions.keys.map((String key) {
            return DropdownMenuItem<String>(
              value: key,
              child: Text(key),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedIntervalLabel = newValue!;
            });
          },
        ),
        if (_selectedIntervalLabel == 'Custom') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _customIntervalHours.toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Hours',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (val) {
              setState(() {
                _customIntervalHours = int.tryParse(val) ?? 24;
              });
            },
          ),
        ],
        const SizedBox(height: 16),
        _buildDurationInput(
          label: "Duration (min)", 
          value: _intervalDurationMinutes, 
          onChanged: (v) => setState(() => _intervalDurationMinutes = v),
        ),
      ],
    );
  }

  Widget _buildDurationInput({
    required String label,
    required int value,
    required ValueChanged<int> onChanged
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            Text(
              "$value",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}
