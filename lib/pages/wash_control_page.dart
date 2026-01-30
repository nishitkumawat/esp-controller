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
  late final dynamic _mqttService;
  final ApiService _apiService = ApiService();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  
  // State
  bool _isSending = false;
  bool _isLoadingConfig = true;
  bool _isLoadingStatus = true;
  
  // Device Status (from MQTT)
  bool _isOnline = false; // "online" field
  bool _isWifiConnected = false;
  bool _isMqttConnected = false; // Derived or explicit
  String _washState = 'IDLE'; // IDLE, RUNNING
  int _remainingSec = 0;
  Timer? _countdownTimer;
  StreamSubscription? _mqttSubscription;

  // Manual Wash
  final int _defaultManualDurationSec = 300; // 5 mins

  // Scheduling Content
  String _selectedMode = 'WEEKLY'; // 'WEEKLY' or 'INTERVAL'
  
  // Weekly Mode Inputs
  TimeOfDay _selectedTime = const TimeOfDay(hour: 6, minute: 0);
  final List<String> _weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  final List<String> _weekDayKeys = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  final Set<String> _selectedDays = {};
  int _weeklyDurationMinutes = 5;

  // Interval Mode Inputs
  String _selectedIntervalLabel = 'Every 24 hours';
  int _customIntervalHours = 24;
  int _intervalDurationMinutes = 5;

  final Map<String, int> _intervalOptions = {
    'Every 12 hours': 12,
    'Every 24 hours': 24,
    'Every 30 hours': 30,
    'Custom': -1,
  };
  
  // Active Configuration (from MQTT)
  Map<String, dynamic>? _activeConfig;

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
    
    _initAsync();
  }
  
  Future<void> _initAsync() async {
     await _subscribeToTopics();
     await _requestInitialData();
  }
  
  Future<void> _subscribeToTopics() async {
    // CRITICAL: Set up stream listener FIRST, before calling subscribe()
    // This ensures we don't miss any retained messages
    _mqttSubscription?.cancel();
    
    _mqttSubscription = _mqttService.updates.listen((event) {
      final topic = event['topic'];
      final message = event['message'];
      print('📩 Received topic: $topic');
      
      if (topic == 'solar/${widget.deviceCode}/wash/status') {
        _handleStatusUpdate(message);
      } else if (topic == 'solar/${widget.deviceCode}/wash/config') {
        _handleConfigUpdate(message);
      }
    });
    
    // NOW subscribe to topics (this may trigger MQTT connect)
    // We await this to ensure subscriptions are active before requesting data
    await _mqttService.subscribe('solar/${widget.deviceCode}/wash/status');
    await _mqttService.subscribe('solar/${widget.deviceCode}/wash/config');
  }

  Future<void> _requestInitialData() async {
    // At this point, we are guaranteed to be connected or have tried to connect
    // because _subscribeToTopics awaits subscription.
    
    print('🔄 Requesting initial data...');
    
    // Small delay to ensure broker processed subscriptions
    await Future.delayed(const Duration(milliseconds: 200));

    // Publish get commands
    _mqttService.publish('solar/${widget.deviceCode}/wash/status/get', '');
    _mqttService.publish('solar/${widget.deviceCode}/wash/config/get', '');
    
    // Set timeout for loading states
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isLoadingConfig = false;
          _isLoadingStatus = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _countdownTimer?.cancel();
    _mqttSubscription?.cancel();
    super.dispose();
  }

  void _handleStatusUpdate(String? message) {
    if (message == null) return;
    try {
      final data = jsonDecode(message);
      // Expected: { "wifi": true, "mqtt": true, "wash_state": "IDLE"|"RUNNING", "remaining_sec": 120 }
      
      setState(() {
        _isLoadingStatus = false; // Data received
        _isWifiConnected = data['wifi'] ?? false;
        _isMqttConnected = true; // If we received this over MQTT, obviously MQTT is connected
        _washState = data['wash_state'] ?? 'IDLE'; // FIX: firmware sends 'wash_state', not 'state'
        
        // Determine overall "Online" status
        _isOnline = true;
        
        // Sync time whenever we get a status update (implies connection)
        _sendTimeSync();

        if (_washState == 'RUNNING') {
          _remainingSec = data['remaining_sec'] ?? 0;
          _startLocalTimer();
        } else {
          _remainingSec = 0;
          _countdownTimer?.cancel();
        }
      });
    } catch (e) {
      print("Error parsing status: $e");
    }
  }

  void _sendTimeSync() {
    // Send current epoch time to ESP32 to set its internal clock (Offline support)
    // We send seconds since epoch
    int epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _mqttService.publish('solar/${widget.deviceCode}/time/sync', jsonEncode({"epoch": epoch}));
    print("Sent Time Sync: $epoch");
  }

  void _handleConfigUpdate(String? message) {
    if (message == null) return;
    
    try {
      print("📥 CONFIG RECEIVED (retain): $message");
      final data = jsonDecode(message);
      if (data == null) return;

      setState(() {
        _isLoadingConfig = false; // Data received
        _activeConfig = data;
        final mode = data['mode'];

        // 🔥 RESET BOTH FIRST (VERY IMPORTANT)
        _selectedDays.clear();
        _selectedIntervalLabel = 'Every 24 hours';
        _customIntervalHours = 24;

        if (mode == 'WEEKLY') {
          _selectedMode = 'WEEKLY';

          final w = data['weekly'];
          if (w != null) {
            final timeStr = w['time'] ?? "06:00";
            try {
              final parts = timeStr.split(':');
              _selectedTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            } catch (_) {
              _selectedTime = const TimeOfDay(hour: 6, minute: 0);
            }

            for (final d in (w['days'] ?? [])) {
              _selectedDays.add(d.toString());
            }

            _weeklyDurationMinutes = (w['duration_sec'] ?? 300) ~/ 60;
          }
        }
        else if (mode == 'INTERVAL') {
          _selectedMode = 'INTERVAL';

          final i = data['interval'];
          if (i != null) {
            final hrs = i['hours'] ?? 24;

            if (_intervalOptions.containsValue(hrs)) {
              _selectedIntervalLabel =
                  _intervalOptions.keys.firstWhere((k) => _intervalOptions[k] == hrs);
            } else {
              _selectedIntervalLabel = 'Custom';
              _customIntervalHours = hrs;
            }

            _intervalDurationMinutes = (i['duration_sec'] ?? 300) ~/ 60;
          }
        }
      });
    } catch (e) {
      print("❌ Error parsing config: $e");
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
      }
    });
  }

  Future<void> _handleManualWash() async {
    if (_isSending || !_isOnline) return;
    setState(() => _isSending = true);

    try {
      final topic = 'solar/${widget.deviceCode}/wash/manual';
      String payload;
      
      if (_washState == 'RUNNING') {
        payload = jsonEncode({"action": "STOP"});
        // Optimistic
        setState(() => _washState = 'IDLE');
      } else {
        // Manual wash is now INDEFINITE (duration_sec: 0)
        payload = jsonEncode({
          "action": "START",
          "duration_sec": 0
        });
        setState(() {
          _washState = 'RUNNING';
          _remainingSec = 0; // Indefinite
        });
        _startLocalTimer();
      }

      await _mqttService.publish(topic, payload);
      Fluttertoast.showToast(msg: _washState == 'RUNNING' ? "Starting Wash..." : "Stopping Wash...");

    } catch (e) {
      Fluttertoast.showToast(msg: "Failed: $e");
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _saveSchedule() async {
    if (_isSending || !_isOnline) return;
    setState(() => _isSending = true);

    try {
      if (_selectedMode == 'WEEKLY') {
        final topic = 'solar/${widget.deviceCode}/wash/schedule/weekly';
        
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
        
        // Ensure time is synced when saving schedule
        _sendTimeSync();
        
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
      
      // Refresh config after save
      await Future.delayed(const Duration(seconds: 1));
      _mqttService.publish('solar/${widget.deviceCode}/wash/config/get', '');
      
    } catch (e) {
      Fluttertoast.showToast(msg: "Save failed: $e");
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _confirmAndDeleteDevice() async {
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

  // Theme Colors
  static const Color kPrimaryColor = Color(0xFF102A43); // Deep Blue
  static const Color kAccentColor = Color(0xFFFF9F43);  // Soft Orange
  static const Color kBackgroundColor = Color(0xFFF0F4F8); // Light Grey
  static const Color kCardColor = Colors.white;
  static const Color kTextColor = Color(0xFF334E68); // Dark Slate
  static const Color kOfflineColor = Color(0xFFBCCCDC);

  @override
  Widget build(BuildContext context) {
    // Determine theme brightness for potential dark mode adjustments (system preference)
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Status Logic
    final bool isOnline = _isOnline; // Using class state
    final Color statusColor = isOnline ? const Color(0xFF27AE60) : kOfflineColor;
    final String statusText = isOnline ? "ONLINE" : "OFFLINE";

    // Main Scaffold
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1929) : kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(isDark, statusColor, statusText),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Wash in Progress (Conditional)
                    if (_washState == 'RUNNING') ...[
                      _buildWashInProgressCard(isDark),
                      const SizedBox(height: 20),
                    ],

                    // 2. Instant Manual Wash
                    _buildManualWashSection(isDark, !isOnline),
                     const SizedBox(height: 20),

                    // 3. Wash Configuration
                    _buildConfigurationSection(isDark, !isOnline),
                    const SizedBox(height: 20),

                    // 4. Active Config Summary
                    if (_activeConfig != null)
                      _buildActiveConfigSummary(isDark),
                      
                    const SizedBox(height: 40), // Bottom padding
                  ],
                ),
              ),
            ),
            // Bottom Action Bar for Save & Sync (Sticky at bottom or part of scroll? 
            // User requested "Save & Sync button at the bottom". 
            // Putting it inside the config card or sticky. 
            // Let's keep it integrated in the config section for better context, 
            // or sticky if it acts on the whole page form.
            // The prompt implies it belongs to the Wash Configuration Section.
            // So I will keep it inside _buildConfigurationSection.
          ],
        ),
      ),
    );
  }

  Widget _buildTopAppBar(bool isDark, Color statusColor, String statusText) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : kPrimaryColor, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deviceName.toUpperCase(),
                  style: TextStyle(
                    color: isDark ? Colors.white : kPrimaryColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: statusColor),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.deviceCode,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : kTextColor.withOpacity(0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: isDark ? Colors.white54 : kTextColor),
            onPressed: () {
               _requestInitialData();
               Fluttertoast.showToast(msg: "Refreshing data...");
            },
          ),
          if (widget.deviceId != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
              onPressed: _confirmAndDeleteDevice,
            ),
        ],
      ),
    );
  }

  Widget _buildWashInProgressCard(bool isDark) {
    // Calculate progress (0.0 to 1.0)
    double progress = 0.0;
    bool isIndefinite = false;
    
    // Check if running config has duration
    if (_activeConfig != null && _activeConfig!['wash_state'] == 'RUNNING') {
        // If config/status implies running... actually we use _activeConfig only for schedule config.
        // We rely on _remainingSec.
    }
    
    if (_remainingSec <= 0 && _washState == 'RUNNING') {
        isIndefinite = true;
        progress = 1.0; // Show full bar or indeterminate
    } else if (_remainingSec > 0) {
        // Try to guess max duration? 
        // If it was manual 300s, we don't really know total unless we stored it.
        // But for visual feedback, let's just make it look active.
        // Or if we have a scheduled duration known.
        // For now, simpler:
        // If > 3600 (1 hour), assume error, else calc.
        // Let's just use a relative progress or indeterminate.
        // If we don't know the TOTAL, we can't do accurate progress.
        // But let's assume standard max 5 mins for the visual if unknown.
        int total = 300;
        if (_selectedMode == 'WEEKLY') total = _weeklyDurationMinutes * 60;
        else if (_selectedMode == 'INTERVAL') total = _intervalDurationMinutes * 60;
        
        progress = 1 - (_remainingSec / total);
        progress = progress.clamp(0.0, 1.0);
    }
    
    // Override for indefinite manual
    if (isIndefinite) progress = 0; // Indeterminate loading indicator?

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kAccentColor, kAccentColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kAccentColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "WASH IN PROGRESS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.0,
                ),
              ),
              Icon(Icons.cleaning_services, color: Colors.white.withOpacity(0.8)),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            isIndefinite ? "MANUAL RUN" : _formatDuration(_remainingSec),
            style: TextStyle(
              color: Colors.white,
              fontSize: isIndefinite ? 32 : 42,
              fontWeight: FontWeight.w900,
              fontFamily: isIndefinite ? null : 'monospace', // Monospaced for numbers
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: isIndefinite 
                ? const LinearProgressIndicator(
                    backgroundColor: Colors.white24, 
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                : LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualWashSection(bool isDark, bool isDisabled) {
    final bool isRunning = _washState == 'RUNNING';
    final Color buttonColor = isRunning 
        ? const Color(0xFFE74C3C) // Red for Stop
        : kPrimaryColor; // Blue for Start

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isDisabled ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24), // Reduced padding
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF152A3D) : kCardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              "Instant Manual Wash",
              style: TextStyle(
                color: isDark ? Colors.white70 : kTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: isDisabled ? null : _handleManualWash,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 100, // Reduced from 140
                height: 100, // Reduced from 140
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                  boxShadow: [
                    // Outer glow/shadow
                    BoxShadow(
                      color: buttonColor.withOpacity(isRunning ? 0.4 : 0.2),
                      blurRadius: 24, // Slightly reduced blur
                      spreadRadius: 1,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: buttonColor,
                    width: 3, // Slightly thinner border
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey<bool>(isRunning),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isRunning ? Icons.stop_rounded : Icons.power_settings_new_rounded,
                          size: 34, // Reduced from 48
                          color: buttonColor,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isRunning ? "STOP" : "START",
                          style: TextStyle(
                            color: buttonColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13, // Reduced from 16
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isRunning 
                ? "Tap to stop immediately" 
                : "Tap to start a quick 5 min wash",
              style: TextStyle(
                color: isDark ? Colors.white38 : kTextColor.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationSection(bool isDark, bool isDisabled) {
    return IgnorePointer(
      ignoring: isDisabled,
      child: Opacity(
        opacity: isDisabled ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16), // Reduced padding to prevent overflow
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF152A3D) : kCardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Icon(Icons.tune, color: kAccentColor, size: 20),
                   const SizedBox(width: 10),
                   Text(
                    "Configuration",
                    style: TextStyle(
                      color: isDark ? Colors.white : kPrimaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Show skeleton loading while fetching config
              if (_isLoadingConfig) ...[
                _buildSkeletonLoader(isDark),
              ] else ...[
                // Custom Tab/Segment Selector
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(child: _buildTabButton("Weekly", _selectedMode == 'WEEKLY', isDark)),
                      Expanded(child: _buildTabButton("Interval", _selectedMode == 'INTERVAL', isDark)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),

                AnimatedCrossFade(
                  firstChild: _buildWeeklyContent(isDark),
                  secondChild: _buildIntervalContent(isDark),
                  crossFadeState: _selectedMode == 'WEEKLY' 
                      ? CrossFadeState.showFirst 
                      : CrossFadeState.showSecond,
                  duration: const Duration(milliseconds: 300),
                ),

                const SizedBox(height: 30),
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSending 
                    ? const SizedBox(
                        height: 20, width: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                      )
                    : const Text(
                        "SAVE & SYNC",
                        style: TextStyle(
                          fontSize: 14, 
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                ),
              ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMode = label.toUpperCase();
          
          // Clear the other mode when switching tabs
          if (_selectedMode == 'WEEKLY') {
            _selectedIntervalLabel = 'Every 24 hours';
            _customIntervalHours = 24;
          } else {
            _selectedDays.clear();
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? const Color(0xFF334E68) : Colors.white) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ] : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected 
              ? (isDark ? Colors.white : kPrimaryColor) 
              : (isDark ? Colors.white54 : kTextColor.withOpacity(0.6)),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time Picker
        _buildSectionLabel("START TIME", isDark),
        const SizedBox(height: 10),
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: _selectedTime,
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: kPrimaryColor,
                      onPrimary: Colors.white,
                      onSurface: kPrimaryColor,
                    ),
                  ),
                  child: child!,
                );
              }
            );
            if (picked != null) setState(() => _selectedTime = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedTime.format(context),
                  style: TextStyle(
                    fontSize: 24, 
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : kPrimaryColor,
                  ),
                ),
                Icon(Icons.access_time_rounded, color: kAccentColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Days Selector
        _buildSectionLabel("REPEAT ON", isDark),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            // Use LayoutBuilder to be safe, though resizing circles is primary fix
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_weekDays.length, (index) {
                final key = _weekDayKeys[index];
                final selected = _selectedDays.contains(key);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selected ? _selectedDays.remove(key) : _selectedDays.add(key);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32, // Reduced size to prevent overflow
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? kPrimaryColor : Colors.transparent,
                      border: Border.all(
                        color: selected ? kPrimaryColor : (isDark ? Colors.white24 : Colors.grey.shade300),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _weekDays[index],
                        style: TextStyle(
                          color: selected ? Colors.white : (isDark ? Colors.white54 : kTextColor),
                          fontWeight: FontWeight.w600,
                          fontSize: 11, // Slightly smaller font
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }
        ),
        const SizedBox(height: 24),

        // Duration Slider
        _buildDurationSlider(isDark, _weeklyDurationMinutes, (val) => setState(() => _weeklyDurationMinutes = val)),
      ],
    );
  }

  Widget _buildIntervalContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel("REPEAT FREQUENCY", isDark),
        const SizedBox(height: 10),
        // Custom Card Options for Interval
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _intervalOptions.keys.map((label) {
            final isSelected = _selectedIntervalLabel == label;
            return GestureDetector(
              onTap: () => setState(() => _selectedIntervalLabel = label),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? kPrimaryColor.withOpacity(0.1) : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? kPrimaryColor : (isDark ? Colors.white24 : Colors.grey.shade300),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? kPrimaryColor : (isDark ? Colors.white70 : kTextColor),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        
        if (_selectedIntervalLabel == 'Custom') ...[
           const SizedBox(height: 16),
           TextFormField(
             initialValue: _customIntervalHours.toString(),
             keyboardType: TextInputType.number,
             style: TextStyle(color: isDark ? Colors.white : Colors.black),
             decoration: InputDecoration(
               labelText: "Enter Hours",
               labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
               suffixText: "hrs",
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
               enabledBorder: OutlineInputBorder(
                 borderRadius: BorderRadius.circular(12),
                 borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
               ),
               focusedBorder: OutlineInputBorder(
                 borderRadius: BorderRadius.circular(12),
                 borderSide: const BorderSide(color: kPrimaryColor, width: 2),
               ),
             ),
             onChanged: (val) => setState(() => _customIntervalHours = int.tryParse(val) ?? 24),
           ),
        ],

        const SizedBox(height: 24),
        _buildDurationSlider(isDark, _intervalDurationMinutes, (val) => setState(() => _intervalDurationMinutes = val)),
      ],
    );
  }

  Widget _buildDurationSlider(bool isDark, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionLabel("WASH DURATION", isDark),
            Text(
              "$value min",
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 16,
                color: isDark ? Colors.white : kPrimaryColor
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: kAccentColor,
            inactiveTrackColor: kAccentColor.withOpacity(0.2),
            thumbColor: kAccentColor,
            overlayColor: kAccentColor.withOpacity(0.2),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            onChanged: (val) => onChanged(val.round()),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white54 : Colors.grey.shade600,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildActiveConfigSummary(bool isDark) {
    final cfg = _activeConfig;
    if (cfg == null) return const SizedBox.shrink();

    final mode = cfg['mode'];
    String summary = "";
    int durationSec = 0;

    if (mode == 'WEEKLY') {
      final w = cfg['weekly'];
      if (w != null) {
        final days = (w['days'] as List?)?.join(', ') ?? '';
        summary = "Scheduled weekly on $days at ${w['time']}";
        durationSec = w['duration_sec'] ?? 0;
      }
    } else if (mode == 'INTERVAL') {
      final i = cfg['interval'];
      if (i != null) {
        summary = "Scheduled every ${i['hours']} hours";
        durationSec = i['duration_sec'] ?? 0;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: kPrimaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: kPrimaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "ACTIVE CONFIGURATION",
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$summary\nDuration: ${_formatDuration(durationSec)}",
                  style: const TextStyle(
                    color: kTextColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return "0 sec";
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return "${m}m ${s}s";
    if (m > 0) return "${m} min";
     return "${s} sec";
  }

  Widget _buildSkeletonLoader(bool isDark) {
    return Column(
      children: [
        // Skeleton tabs
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 24),
        // Skeleton content
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 30),
        // Skeleton button
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }
}

