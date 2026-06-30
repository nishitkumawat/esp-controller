import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/mqtt_service_factory.dart';

class MultiStationPage extends StatefulWidget {
  final String deviceCode;
  final String deviceName;
  final int? deviceId;
  final bool isAdmin;

  const MultiStationPage({
    super.key,
    required this.deviceCode,
    required this.deviceName,
    this.deviceId,
    this.isAdmin = false,
  });

  @override
  State<MultiStationPage> createState() => _MultiStationPageState();
}

class _MultiStationPageState extends State<MultiStationPage> {
  late final dynamic _mqttService;

  bool _isLoading = true;
  bool _timeSyncedOnce = false;

  DateTime? _lastLiveMessageTime;
  bool get isDeviceOnline {
    if (_lastLiveMessageTime == null) return false;
    final diff = DateTime.now().difference(_lastLiveMessageTime!).inSeconds;
    return diff < 30; // 30s timeout
  }

  String _deviceTime = '--:--';
  int _deviceUptime = 0;
  int _numStations = 0;
  List<Map<String, dynamic>> _stationStatuses = [];
  List<Map<String, dynamic>> _stationConfigs = [];

  Timer? _countdownTimer;
  StreamSubscription? _mqttSubscription;
  Timer? _statusPollTimer;
  static const int kStationCount = 8;

  static const Color kPrimaryColor = Color(0xFFFF9F43); // Orange
  static const Color kAccentColor = Color(0xFF0055D4); // Blue accent
  static const Color kBgColor = Color(0xFFF8FAFC);
  static const Color kTextColor = Color(0xFF1E293B);
  static const Color kOfflineColor = Color(0xFFE11D48);

  bool _isLoadingStatus = true;
  bool _isLoadingConfig = true;
  bool _isSending = false;

  /// Master mode (from device status / config MQTT)
  Map<String, dynamic> _masterStatus = {};
  Map<String, dynamic> _masterConfig = {};
  int _masterUiTab = 0;

  final Set<int> _combineStationPick = {};
  bool _combineSlotEnabled = true;
  TimeOfDay _combineStart = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _combineEnd = const TimeOfDay(hour: 10, minute: 30);
  final Set<String> _combineDays = {'MON', 'TUE', 'WED', 'THU', 'FRI'};
  int _combineIntervalRunMin = 0;
  int _combineIntervalPauseMin = 5;

  final List<_TrainStepDraft> _trainStepsDraft = [
    _TrainStepDraft(station: 1, runMin: 5, breakMin: 2),
  ];
  bool _trainLoop = false;
  int _trainRelayDelayMs = 2000;
  bool _trainTriggerEnabled = false;
  TimeOfDay _trainTriggerTime = const TimeOfDay(hour: 6, minute: 0);
  final Set<String> _trainTriggerDays = {'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'};

  String get _deviceMasterMode =>
      (_masterStatus['mode'] ?? _masterConfig['mode'] ?? 'off').toString().toLowerCase();

  bool get _individualSchedulesDisabledByMaster =>
      _masterStatus['individual_disabled'] == true || _deviceMasterMode == 'combine' || _deviceMasterMode == 'train';

  @override
  void initState() {
    super.initState();
    _mqttService = MqttServiceFactory.getMqttService(widget.deviceCode);
    _initAsync();

    // Local countdown timer for remaining_sec
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      bool needsUpdate = false;
      for (var s in _stationStatuses) {
        if (s['running'] == true && (s['rem'] ?? 0) > 0) {
          s['rem'] = (s['rem'] ?? 0) - 1;
          needsUpdate = true;
        }
      }
      if (needsUpdate && mounted) {
        setState(() {});
      }
    });

    // Request status periodically if no live messages
    _statusPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isDeviceOnline) {
        _mqttService.publish('atp/${widget.deviceCode}/status/get', '');
      }
    });
  }

  Future<void> _initAsync() async {
    _mqttSubscription?.cancel();
    _mqttSubscription = _mqttService.updates.listen((event) {
      final topic = event['topic'];
      final message = event['message'];
      final isRetained = event['retained'] == 'true';
      print('📩 Received topic: $topic');
      print("📥 MQTT INCOMING");
      print("   Topic: $topic");
      print("   Message: $message");
      print("   Retained: $isRetained");
      print("   ----------------------");
      
      if (topic == 'atp/${widget.deviceCode}/status') {
        _handleStatusUpdate(message, isRetained);
      } else if (topic == 'atp/${widget.deviceCode}/config') {
        _handleConfigUpdate(message);
      }
    });

    await _mqttService.subscribe('atp/${widget.deviceCode}/status');
    await _mqttService.subscribe('atp/${widget.deviceCode}/config');

    _manualRefresh();

    // Set timeout for loading states
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
          _isLoadingConfig = false;
        });
      }
    });
  }

  Future<void> _manualRefresh() async {
    // Request status multiple times to ensure receipt
    for (int i = 0; i < 3; i++) {
      _mqttService.publish('atp/${widget.deviceCode}/status/get', '');
      await Future.delayed(const Duration(milliseconds: 300));
    }
    // Request updated config to refresh UI
    Future.delayed(const Duration(milliseconds: 500), () async {
      for (int i = 0; i < 5; i++) {
        try {
          await _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
          await Future.delayed(Duration(milliseconds: 300));
        } catch (e) {
          print('❌ Config request failed: $e');
        }
      }
    });
    _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
  }

  void _handleStatusUpdate(String message, bool isRetained) {
    if (message == null) return;
    try {
      final data = jsonDecode(message);
      setState(() {
        _isLoadingStatus = false;
        
        // Only update last live message time for non-retained messages
        if (!isRetained) {
          _lastLiveMessageTime = DateTime.now();
        }
        
        if (data['time'] != null) _deviceTime = data['time'];
        if (data['uptime'] != null) _deviceUptime = data['uptime'];
        
        // Update motor statuses from new ATP format
        if (data['motors'] != null) {
          _stationStatuses = List<Map<String, dynamic>>.from(data['motors']);
          _numStations = _stationStatuses.length;
        }
        if (data['master'] != null) {
          _masterStatus = Map<String, dynamic>.from(data['master'] as Map);
          final m = (_masterStatus['mode'] ?? 'off').toString().toLowerCase();
          if (m == 'combine') {
            _masterUiTab = 1;
          } else if (m == 'train') {
            _masterUiTab = 2;
          } else {
            _masterUiTab = 0;
          }
        }

        if (!_timeSyncedOnce && isDeviceOnline) {
          _sendTimeSync();
          _timeSyncedOnce = true;
        }
      });
    } catch (e) {
      print("Error parsing status JSON: $e");
    }
  }

  void _handleConfigUpdate(String message) {
    try {
      final data = jsonDecode(message);
      setState(() {
        _isLoadingConfig = false;
        if (data['motors'] != null) {
          _stationConfigs = List<Map<String, dynamic>>.from(data['motors']);
        }
        if (data['master'] != null) {
          _masterConfig = Map<String, dynamic>.from(data['master'] as Map);
          _applyMasterConfigToDraft();
        }
      });
    } catch (e) {
      print("Error parsing config JSON: $e");
    }
  }

  void _sendTimeSync() {
    int epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _mqttService.publish(
      'atp/${widget.deviceCode}/time/sync',
      jsonEncode({"epoch": epoch}),
    );
  }

  void _applyMasterConfigToDraft() {
    final comb = _masterConfig['combine'];
    if (comb is Map) {
      final mask = (comb['station_mask'] as num?)?.toInt() ?? 0;
      _combineStationPick.clear();
      for (int i = 0; i < kStationCount; i++) {
        if (((mask >> i) & 1) == 1) _combineStationPick.add(i + 1);
      }
      final slots = comb['schedule'] ?? comb['slots'];
      if (slots is List && slots.isNotEmpty && slots.first is Map) {
        final s0 = Map<String, dynamic>.from(slots.first as Map);
        _combineSlotEnabled = s0['enabled'] == true;
        final days = (s0['days'] as num?)?.toInt() ?? 0;
        _combineDays.clear();
        const dn = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
        for (int i = 0; i < 7; i++) {
          if (((days >> i) & 1) == 1) _combineDays.add(dn[i]);
        }
        final st = (s0['start'] ?? '10:00').toString();
        final en = (s0['end'] ?? '10:30').toString();
        _parseTimeTo(st, (h, m) => _combineStart = TimeOfDay(hour: h, minute: m));
        _parseTimeTo(en, (h, m) => _combineEnd = TimeOfDay(hour: h, minute: m));
        final ir = (s0['interval_run_sec'] as num?)?.toInt() ?? 0;
        final ip = (s0['interval_pause_sec'] as num?)?.toInt() ?? 0;
        _combineIntervalRunMin = ir ~/ 60;
        _combineIntervalPauseMin = ip ~/ 60;
      }
    }
    final tr = _masterConfig['train'];
    if (tr is Map) {
      _trainLoop = tr['loop'] == true;
      _trainRelayDelayMs = (tr['relay_delay_ms'] as num?)?.toInt() ?? 2000;
      final trig = tr['trigger'];
      if (trig is Map) {
        _trainTriggerEnabled = trig['enabled'] == true;
        final td = (trig['days'] as num?)?.toInt() ?? 0;
        _trainTriggerDays.clear();
        const dn = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
        for (int i = 0; i < 7; i++) {
          if (((td >> i) & 1) == 1) _trainTriggerDays.add(dn[i]);
        }
        final tt = (trig['time'] ?? '06:00').toString();
        _parseTimeTo(tt, (h, m) => _trainTriggerTime = TimeOfDay(hour: h, minute: m));
      }
      final steps = tr['steps'];
      if (steps is List && steps.isNotEmpty) {
        _trainStepsDraft.clear();
        for (final e in steps) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final st = (m['station'] as num?)?.toInt() ?? 1;
          final runS = (m['run_sec'] as num?)?.toInt() ?? 300;
          final brkS = (m['break_sec'] as num?)?.toInt() ?? 0;
          _trainStepsDraft.add(_TrainStepDraft(
            station: st.clamp(1, kStationCount),
            runMin: (runS / 60).ceil().clamp(1, 120),
            breakMin: (brkS / 60).ceil().clamp(0, 120),
          ));
        }
      }
      if (_trainStepsDraft.isEmpty) {
        _trainStepsDraft.add(_TrainStepDraft(station: 1, runMin: 5, breakMin: 2));
      }
    }
  }

  void _parseTimeTo(String s, void Function(int h, int m) set) {
    final p = s.split(':');
    if (p.length >= 2) {
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      set(h.clamp(0, 23), m.clamp(0, 59));
    }
  }

  int _daysSetToBitmask(Set<String> days) {
    int b = 0;
    for (final d in days) {
      switch (d) {
        case 'SUN':
          b |= 1 << 0;
          break;
        case 'MON':
          b |= 1 << 1;
          break;
        case 'TUE':
          b |= 1 << 2;
          break;
        case 'WED':
          b |= 1 << 3;
          break;
        case 'THU':
          b |= 1 << 4;
          break;
        case 'FRI':
          b |= 1 << 5;
          break;
        case 'SAT':
          b |= 1 << 6;
          break;
      }
    }
    return b;
  }

  Future<void> _publishMasterMode(String mode) async {
    await _mqttService.publish(
      'atp/${widget.deviceCode}/master/mode',
      jsonEncode({'mode': mode}),
      retain: true,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
      _mqttService.publish('atp/${widget.deviceCode}/status/get', '');
    });
  }

  Future<void> _publishCombineConfig() async {
    int mask = 0;
    for (final n in _combineStationPick) {
      if (n >= 1 && n <= kStationCount) mask |= 1 << (n - 1);
    }
    final sh = _combineStart.hour.toString().padLeft(2, '0');
    final sm = _combineStart.minute.toString().padLeft(2, '0');
    final eh = _combineEnd.hour.toString().padLeft(2, '0');
    final em = _combineEnd.minute.toString().padLeft(2, '0');
    final payload = {
      'station_mask': mask,
      'slots': [
        {
          'enabled': _combineSlotEnabled,
          'days': _daysSetToBitmask(_combineDays),
          'start': '$sh:$sm',
          'end': '$eh:$em',
          'interval_run_sec': _combineIntervalRunMin * 60,
          'interval_pause_sec': _combineIntervalPauseMin * 60,
        }
      ]
    };
    await _mqttService.publish(
      'atp/${widget.deviceCode}/master/combine/config',
      jsonEncode(payload),
      retain: true,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
    });
    Fluttertoast.showToast(msg: 'Combine schedule sent to controller');
  }

  Future<void> _publishTrainConfig() async {
    final steps = _trainStepsDraft
        .map((e) => {
              'station': e.station,
              'run_sec': e.runMin * 60,
              'break_sec': e.breakMin * 60,
            })
        .toList();
    final th = _trainTriggerTime.hour.toString().padLeft(2, '0');
    final tm = _trainTriggerTime.minute.toString().padLeft(2, '0');
    final payload = {
      'relay_delay_ms': _trainRelayDelayMs.clamp(500, 30000),
      'loop': _trainLoop,
      'trigger': {
        'enabled': _trainTriggerEnabled,
        'days': _daysSetToBitmask(_trainTriggerDays),
        'time': '$th:$tm',
      },
      'steps': steps,
    };
    await _mqttService.publish(
      'atp/${widget.deviceCode}/master/train/config',
      jsonEncode(payload),
      retain: true,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
    });
    Fluttertoast.showToast(msg: 'Train sequence sent to controller');
  }

  Future<void> _masterEmergencyStop() async {
    await _mqttService.publish('atp/${widget.deviceCode}/master/emergency', '{}', retain: false);
    Future.delayed(const Duration(milliseconds: 300), () {
      _mqttService.publish('atp/${widget.deviceCode}/status/get', '');
    });
    Fluttertoast.showToast(msg: 'Emergency stop sent', backgroundColor: Colors.red);
  }

  Future<void> _trainStartNow() async {
    await _mqttService.publish('atp/${widget.deviceCode}/master/train/start', '{}', retain: false);
    Fluttertoast.showToast(msg: 'Train sequence start requested');
  }

  Future<void> _trainStopSequence() async {
    await _mqttService.publish('atp/${widget.deviceCode}/master/train/stop', '{}', retain: false);
    Fluttertoast.showToast(msg: 'Train sequence stop requested');
  }

  Future<void> _confirmEnableMasterMode(Future<void> Function() onOk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable master mode?'),
        content: const Text(
          'Enabling Combine or Train mode disables per-station automatic schedules on the controller until you return to Normal. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) await onOk();
  }

  Future<void> _onPickMasterTab(int tab) async {
    if (tab == _masterUiTab) return;
    if (tab == 0) {
      setState(() => _masterUiTab = 0);
      await _publishMasterMode('off');
      return;
    }
    await _confirmEnableMasterMode(() async {
      setState(() => _masterUiTab = tab);
      if (tab == 1) {
        await _publishMasterMode('combine');
      } else {
        await _publishMasterMode('train');
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _mqttSubscription?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  // MQTT Actions
  void _startMotor(int motorId, int durationSec) {
    _mqttService.publish(
      'atp/${widget.deviceCode}/motor/control',
      jsonEncode({
        "id": motorId,
        "action": "START"
      }),
    );
  }

  void _stopMotor(int motorId) {
    _mqttService.publish(
      'atp/${widget.deviceCode}/motor/control',
      jsonEncode({
        "id": motorId,
        "action": "STOP"
      }),
    );
  }

  void _stopAllMotors() {
    for (int i = 0; i < kStationCount; i++) {
      _stopMotor(i);
    }
  }

  void _saveScheduleSlot(int motorId, int slot, String time, List<String> days, int durationSec, bool enabled) async {
    try {
      print('🔄 Saving schedule for motor $motorId, slot $slot');
      
      // Convert days list to bitmask (Monday=1, Tuesday=2, etc.)
      int daysBitmask = 0;
      for (String day in days) {
        switch (day) {
          case 'SUN': daysBitmask |= (1 << 0); break;
          case 'MON': daysBitmask |= (1 << 1); break;
          case 'TUE': daysBitmask |= (1 << 2); break;
          case 'WED': daysBitmask |= (1 << 3); break;
          case 'THU': daysBitmask |= (1 << 4); break;
          case 'FRI': daysBitmask |= (1 << 5); break;
          case 'SAT': daysBitmask |= (1 << 6); break;
        }
      }
      
      await _mqttService.publish(
        'atp/${widget.deviceCode}/motor/schedule',
        jsonEncode({
          "id": motorId,
          "sch": slot,
          "time": time,
          "days": daysBitmask,
          "dur": durationSec,
          "enabled": enabled
        }),
        retain: true,
      );
      
      print('✅ Schedule saved successfully');
      
      // Request updated config to refresh UI
      Future.delayed(const Duration(milliseconds: 500), () {
        _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
      });
      
      // Show success feedback
      Fluttertoast.showToast(
        msg: "Schedule saved successfully ✅",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
      
    } catch (e) {
      print('❌ Error saving schedule: $e');
      Fluttertoast.showToast(
        msg: "Failed to save schedule ❌",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  void _clearScheduleSlot(int motorId, int slot) async {
    try {
      print('🔄 Clearing schedule for motor $motorId, slot $slot');
      
      await _mqttService.publish(
        'atp/${widget.deviceCode}/motor/schedule',
        jsonEncode({
          "id": motorId,
          "sch": slot,
          "time": "06:00",
          "days": 0,
          "dur": 300,
          "enabled": false
        }),
        retain: true,
      );
      
      print('✅ Schedule cleared successfully');
      
      // Request updated config to refresh UI
      _mqttService.publish('atp/${widget.deviceCode}/config/get', '');
      
      // Show success feedback
      Fluttertoast.showToast(
        msg: "Schedule cleared successfully ✅",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      
    } catch (e) {
      print('❌ Error clearing schedule: $e');
      Fluttertoast.showToast(
        msg: "Failed to clear schedule ❌",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _daysBitmaskToString(int days) {
    List<String> dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    List<String> activeDays = [];
    for (int i = 0; i < 7; i++) {
      if ((days >> i) & 1 == 1) {
        activeDays.add(dayNames[i]);
      }
    }
    return activeDays.join(', ');
  }

  // --- UI Builders ---

  Widget _buildMasterControlPanel(bool isDark) {
    final modeLabel = _deviceMasterMode == 'combine'
        ? 'Combine (group run)'
        : _deviceMasterMode == 'train'
            ? 'Train (sequence)'
            : 'Normal';
    final trainActive = _masterStatus['train_active'] == true;
    final phaseRem = (_masterStatus['train_phase_rem_s'] as num?)?.toInt() ?? 0;
    final trainStep = (_masterStatus['train_step'] as num?)?.toInt() ?? 0;
    const dayPick = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF152A3D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.hub_rounded, color: kAccentColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Master control',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : kTextColor,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: isDeviceOnline ? _masterEmergencyStop : null,
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 20),
                  label: const Text('E‑STOP', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Device mode: $modeLabel',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : kTextColor.withOpacity(0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trainActive) ...[
              const SizedBox(height: 6),
              Text(
                'Train running — step ${trainStep + 1} • phase ${(_masterStatus['train_phase'] ?? '-')} • ~${_formatTime(phaseRem)} left',
                style: TextStyle(fontSize: 11, color: kPrimaryColor, fontWeight: FontWeight.w700),
              ),
            ],
            if (_individualSchedulesDisabledByMaster) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Individual schedules are disabled because Master mode is active. Return to Normal to use per-station timers.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: isDark ? Colors.amber.shade100 : Colors.brown.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text('Operating mode', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.grey.shade600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Normal'),
                  selected: _masterUiTab == 0,
                  onSelected: (_) => _onPickMasterTab(0),
                  selectedColor: kPrimaryColor.withOpacity(0.35),
                ),
                ChoiceChip(
                  label: const Text('Combine'),
                  selected: _masterUiTab == 1,
                  onSelected: (_) => _onPickMasterTab(1),
                  selectedColor: kAccentColor.withOpacity(0.35),
                ),
                ChoiceChip(
                  label: const Text('Train'),
                  selected: _masterUiTab == 2,
                  onSelected: (_) => _onPickMasterTab(2),
                  selectedColor: kAccentColor.withOpacity(0.35),
                ),
              ],
            ),
            if (_masterUiTab == 1) ...[
              const SizedBox(height: 16),
              Text('Stations in group', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.grey.shade600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(kStationCount, (i) {
                  final n = i + 1;
                  final sel = _combineStationPick.contains(n);
                  return FilterChip(
                    label: Text('S$n'),
                    selected: sel,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _combineStationPick.add(n);
                        } else {
                          _combineStationPick.remove(n);
                        }
                      });
                    },
                    selectedColor: kPrimaryColor.withOpacity(0.35),
                  );
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable this group schedule'),
                value: _combineSlotEnabled,
                onChanged: (v) => setState(() => _combineSlotEnabled = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Window start'),
                trailing: Text(_combineStart.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _combineStart);
                  if (t != null) setState(() => _combineStart = t);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Window end'),
                trailing: Text(_combineEnd.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _combineEnd);
                  if (t != null) setState(() => _combineEnd = t);
                },
              ),
              Text('Repeat days', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.grey.shade600)),
              Wrap(
                spacing: 4,
                children: dayPick.map((d) {
                  final on = _combineDays.contains(d);
                  return FilterChip(
                    label: Text(d, style: const TextStyle(fontSize: 10)),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _combineDays.add(d);
                      } else {
                        _combineDays.remove(d);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text('Inside window: 0 run / 0 pause = all stations on continuously', style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.grey)),
              Row(
                children: [
                  Expanded(
                    child: Text('Run segment (min)', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : kTextColor)),
                  ),
                  Text('$_combineIntervalRunMin'),
                ],
              ),
              Slider(
                value: _combineIntervalRunMin.toDouble().clamp(0, 120),
                min: 0,
                max: 120,
                divisions: 120,
                label: '$_combineIntervalRunMin min',
                onChanged: (v) => setState(() => _combineIntervalRunMin = v.round()),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('Pause segment (min)', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : kTextColor)),
                  ),
                  Text('$_combineIntervalPauseMin'),
                ],
              ),
              Slider(
                value: _combineIntervalPauseMin.toDouble().clamp(0, 120),
                min: 0,
                max: 120,
                divisions: 120,
                label: '$_combineIntervalPauseMin min',
                onChanged: (v) => setState(() => _combineIntervalPauseMin = v.round()),
              ),
              FilledButton.icon(
                onPressed: isDeviceOnline ? _publishCombineConfig : null,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save combine schedule'),
              ),
            ],
            if (_masterUiTab == 2) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sequence (${_trainStepsDraft.length} steps)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : kTextColor),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _trainStepsDraft.add(_TrainStepDraft(station: 1, runMin: 5, breakMin: 2));
                      });
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldI, newI) {
                  setState(() {
                    if (newI > oldI) newI -= 1;
                    final it = _trainStepsDraft.removeAt(oldI);
                    _trainStepsDraft.insert(newI, it);
                  });
                },
                children: [
                  for (int i = 0; i < _trainStepsDraft.length; i++)
                    Card(
                      key: ValueKey('tr_$i'),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.drag_handle),
                                Text('Step ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: _trainStepsDraft.length <= 1
                                      ? null
                                      : () => setState(() => _trainStepsDraft.removeAt(i)),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('Station'),
                                const SizedBox(width: 12),
                                DropdownButton<int>(
                                  value: _trainStepsDraft[i].station.clamp(1, kStationCount),
                                  items: List.generate(
                                    kStationCount,
                                    (j) => DropdownMenuItem(value: j + 1, child: Text('S${j + 1}')),
                                  ),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _trainStepsDraft[i].station = v);
                                    }
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Run (min) ${_trainStepsDraft[i].runMin}', style: const TextStyle(fontSize: 11)),
                                      Slider(
                                        value: _trainStepsDraft[i].runMin.toDouble().clamp(1, 120),
                                        min: 1,
                                        max: 60,
                                        divisions: 59,
                                        onChanged: (v) => setState(() => _trainStepsDraft[i].runMin = v.round()),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Break (min) ${_trainStepsDraft[i].breakMin}', style: const TextStyle(fontSize: 11)),
                                      Slider(
                                        value: _trainStepsDraft[i].breakMin.toDouble().clamp(0, 60),
                                        min: 0,
                                        max: 30,
                                        divisions: 30,
                                        onChanged: (v) => setState(() => _trainStepsDraft[i].breakMin = v.round()),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Loop sequence'),
                value: _trainLoop,
                onChanged: (v) => setState(() => _trainLoop = v),
              ),
              Text('Relay gap (ms) $_trainRelayDelayMs', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : kTextColor)),
              Slider(
                value: _trainRelayDelayMs.toDouble().clamp(500, 10000),
                min: 500,
                max: 10000,
                divisions: 19,
                onChanged: (v) => setState(() => _trainRelayDelayMs = v.round()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily auto-start (at time below)'),
                value: _trainTriggerEnabled,
                onChanged: (v) => setState(() => _trainTriggerEnabled = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Trigger time'),
                trailing: Text(_trainTriggerTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _trainTriggerTime);
                  if (t != null) setState(() => _trainTriggerTime = t);
                },
              ),
              Wrap(
                spacing: 4,
                children: dayPick.map((d) {
                  final on = _trainTriggerDays.contains(d);
                  return FilterChip(
                    label: Text(d, style: const TextStyle(fontSize: 10)),
                    selected: on,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _trainTriggerDays.add(d);
                      } else {
                        _trainTriggerDays.remove(d);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                'Est. cycle ≈ ${_trainStepsDraft.fold<int>(0, (a, s) => a + s.runMin + s.breakMin)} min (plus relay gaps)',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: isDeviceOnline ? _publishTrainConfig : null,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save train sequence'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isDeviceOnline ? _trainStartNow : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start now'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isDeviceOnline ? _trainStopSequence : null,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color statusColor = isDeviceOnline ? const Color(0xFF27AE60) : kOfflineColor;
    final String statusText = isDeviceOnline ? "ONLINE" : "OFFLINE";

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1929) : kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(isDark, statusColor, statusText),
            Expanded(
              child: (_isLoadingStatus || !isDeviceOnline)
                  ? _buildSkeletonLoading()
                  : RefreshIndicator(
                      onRefresh: _manualRefresh,
                      color: kPrimaryColor,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeroMonitor(isDark),
                            const SizedBox(height: 20),
                            _buildMasterControlPanel(isDark),
                            const SizedBox(height: 24),
                            Text(
                              "Station Controls",
                              style: TextStyle(
                                color: isDark ? Colors.white70 : kTextColor.withOpacity(0.7),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildStationsGrid(isDark),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
            ),
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
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: isDark ? Colors.white : kPrimaryColor,
              size: 20,
            ),
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
            icon: Icon(Icons.refresh_rounded, color: isDark ? Colors.white70 : kPrimaryColor),
            onPressed: _manualRefresh,
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: 5,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            height: 180,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
          );
        }
        return Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  Widget _buildHeroMonitor(bool isDark) {
    final runningStations = _stationStatuses.where((s) => s['running'] == true).toList();
    final bool anyRunning = runningStations.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: anyRunning 
            ? [kPrimaryColor, const Color(0xFFE65100)] // Orange to Deep Orange
            : [const Color(0xFF64748B), const Color(0xFF475569)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (anyRunning ? kPrimaryColor : Colors.grey).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "SYSTEM MONITOR",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    anyRunning ? "STATIONS ACTIVE" : "SYSTEM STANDBY",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (anyRunning)
                GestureDetector(
                  onTap: _stopAllMotors,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.stop_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 4),
                        Text(
                          "STOP ALL",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (!anyRunning)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent.shade400, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "All systems clear. Waiting for command.",
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: runningStations.map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Text(
                          "${s['id'] + 1}",
                          style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatTime(s['rem'] ?? 0),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStationsGrid(bool isDark) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: kStationCount,
      itemBuilder: (context, index) {
        return _buildStationCard(index, isDark);
      },
    );
  }

  Widget _buildStationCard(int index, bool isDark) {
    final status = _stationStatuses.firstWhere((s) => s['id'] == index, orElse: () => {'id': index, 'running': false, 'rem': 0});
    final bool isRunning = status['running'] == true;
    final int remainingSec = status['rem'] ?? 0;
    final config = _stationConfigs.firstWhere((c) => c['id'] == index, orElse: () => {});
    final List<dynamic> schedules = config['schedule'] ?? [];
    final activeSchedules = schedules.where((s) => s['enabled'] == true).toList().take(2).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning 
            ? kPrimaryColor.withOpacity(0.5) 
            : (isDark ? Colors.white10 : Colors.grey.shade100),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isRunning ? 0.1 : 0.02),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isRunning ? kPrimaryColor.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.settings_input_component_rounded,
                        color: isRunning ? kPrimaryColor : (isDark ? Colors.white24 : Colors.grey.shade400),
                        size: 20,
                      ),
                      Positioned(
                        top: 1,
                        right: 1,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isRunning ? kPrimaryColor : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    "STATION ${index + 1}",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isDark ? Colors.white : kTextColor,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _showScheduleBottomSheet(index, context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Icons.edit_calendar_rounded,
                      size: 18,
                      color: isDark ? Colors.white60 : kAccentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isRunning ? kPrimaryColor.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isRunning ? "Running" : "Idle",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isRunning ? kPrimaryColor : (isDark ? Colors.white54 : Colors.grey.shade600),
                ),
              ),
            ),
            
            if (isRunning && remainingSec > 0) ...[
              const SizedBox(height: 8),
              Text(
                "${(remainingSec ~/ 60)}:${(remainingSec % 60).toString().padLeft(2, '0')}",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isRunning ? kPrimaryColor : (isDark ? Colors.white70 : Colors.grey.shade700),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (activeSchedules.isEmpty)
              Text(
                "No active schedules",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ...activeSchedules.map((schedule) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      "${schedule['time'] ?? '--:--'} • ${(schedule['dur'] ?? 0) ~/ 60}m",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white70 : kTextColor.withOpacity(0.8),
                      ),
                    ),
                  )),
            
            const Spacer(),
            
            // Action button
            Container(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: isRunning 
                  ? () => _stopMotor(index)
                  : () => _startMotor(index, 300),
                icon: Icon(
                  isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  isRunning ? "STOP" : "START",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red : kPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                  minimumSize: const Size(0, 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Schedules & Intervals",
              style: TextStyle(
                color: isDark ? Colors.white70 : kTextColor.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            IconButton(
              onPressed: () => _mqttService.publish('atp/${widget.deviceCode}/config/get', ''),
              icon: Icon(Icons.refresh, color: kPrimaryColor),
              tooltip: 'Refresh schedules',
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...List.generate(_numStations, (motorIndex) {
          final config = _stationConfigs.firstWhere((c) => c['id'] == motorIndex, orElse: () => {});
          final List<dynamic> schedules = config['schedule'] ?? [];
          final activeSchedules = schedules.where((s) => s['enabled'] == true).toList();
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "MOTOR ${motorIndex + 1}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${activeSchedules.length} Active",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                if (activeSchedules.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    "No schedules configured",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  ...activeSchedules.map((schedule) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: kPrimaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                schedule['time'] ?? '06:00',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    "${(schedule['dur'] ?? 300) ~/ 60}min",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (schedule['days'] != null && schedule['days'] > 0) ...[
                                    Icon(Icons.schedule, size: 12, color: isDark ? Colors.white54 : Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      _daysBitmaskToString(schedule['days']),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white54 : Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  
  void _showScheduleBottomSheet(int stationId, BuildContext context) {
    if (_individualSchedulesDisabledByMaster) {
      Fluttertoast.showToast(
        msg: 'Turn off Master mode (Normal) to edit individual schedules.',
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _ScheduleBottomSheet(
          stationId: stationId,
          configs: _stationConfigs.firstWhere((c) => c['id'] == stationId, orElse: () => {})['schedule'] ?? [],
          onSaveSlot: (slot, time, days, durationSec, enabled) {
            Navigator.pop(ctx); // Close bottom sheet first
            _saveScheduleSlot(stationId, slot, time, days, durationSec, enabled);
            // Show message suggesting to reopen to see changes
            Future.delayed(const Duration(milliseconds: 1500), () {
              Fluttertoast.showToast(
                msg: "Reopen station to see updated schedules ⏰",
                toastLength: Toast.LENGTH_LONG,
                gravity: ToastGravity.BOTTOM,
                backgroundColor: Colors.blue,
                textColor: Colors.white,
              );
            });
          },
          onClearSlot: (slot) {
            _clearScheduleSlot(stationId, slot);
            Navigator.pop(ctx);
          },
        );
      },
    );
  }
}

class _TrainStepDraft {
  int station;
  int runMin;
  int breakMin;

  _TrainStepDraft({
    required this.station,
    required this.runMin,
    required this.breakMin,
  });
}

class _ScheduleBottomSheet extends StatefulWidget {
  final int stationId;
  final List<dynamic> configs;
  final Function(int slot, String time, List<String> days, int durationSec, bool enabled) onSaveSlot;
  final Function(int slot) onClearSlot;

  const _ScheduleBottomSheet({
    required this.stationId,
    required this.configs,
    required this.onSaveSlot,
    required this.onClearSlot,
  });

  static const Color kPrimaryColor = Color(0xFFFF9F43); // Orange
  static const Color kBgColor = Color(0xFFF8FAFC);
  static const Color kTextColor = Color(0xFF1E293B);

  @override
  State<_ScheduleBottomSheet> createState() => _ScheduleBottomSheetState();
}

class _ScheduleBottomSheetState extends State<_ScheduleBottomSheet> {
  late List<Map<String, dynamic>> slots;

  @override
  void initState() {
    super.initState();
    slots = List.generate(4, (index) {
      final existing = widget.configs.firstWhere((c) => c['slot'] == index, orElse: () => null);
      if (existing != null) {
        final int dayMask = existing['days'] ?? 0;
        final List<String> parsedDays = [];
        const dayNames = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
        for (int i = 0; i < 7; i++) {
          if (((dayMask >> i) & 1) == 1) {
            parsedDays.add(dayNames[i]);
          }
        }
        return {
          "slot": index,
          "time": existing['time'] ?? "06:00",
          "days": parsedDays,
          "duration_sec": existing['dur'] ?? 300,
          "enabled": existing['enabled'] == true,
        };
      }
      return {
        "slot": index,
        "time": "06:00",
        "days": <String>[],
        "duration_sec": 300,
        "enabled": false,
      };
    });
  }

  Future<void> _pickTime(int index) async {
    final current = slots[index]['time'].split(':');
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: _ScheduleBottomSheet.kPrimaryColor, onPrimary: Colors.white, onSurface: const Color(0xFF1E293B)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        slots[index]['time'] = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  void _toggleDay(int index, String day) {
    setState(() {
      final days = slots[index]['days'] as List<String>;
      if (days.contains(day)) {
        days.remove(day);
      } else {
        days.add(day);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double height = MediaQuery.of(context).size.height;

    return Container(
      height: height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "STATION ${widget.stationId + 1}",
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const Text(
                      "Scheduling",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              itemCount: 4,
              itemBuilder: (context, index) {
                final slot = slots[index];
                return _buildSlotCard(index, slot, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(int index, Map<String, dynamic> slot, bool isDark) {
    final bool isEnabled = slot['enabled'];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isEnabled ? _ScheduleBottomSheet.kPrimaryColor.withOpacity(0.2) : Colors.transparent),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: isEnabled ? Colors.green : Colors.grey, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "SLOT ${index + 1}",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: isEnabled,
                  activeColor: _ScheduleBottomSheet.kPrimaryColor,
                  onChanged: (v) => setState(() => slot['enabled'] = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _pickTime(index),
                        child: _buildInputBox(
                          label: "START TIME",
                          value: slot['time'],
                          icon: Icons.access_time_filled_rounded,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInputBox(
                        label: "DURATION",
                        value: "${slot['duration_sec'] ~/ 60} MIN",
                        icon: Icons.timer_rounded,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  "ADJUST DURATION",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _ScheduleBottomSheet.kPrimaryColor,
                    thumbColor: _ScheduleBottomSheet.kPrimaryColor,
                    overlayColor: _ScheduleBottomSheet.kPrimaryColor.withOpacity(0.2),
                  ),
                  child: Slider(
                    value: (slot['duration_sec'] ~/ 60).toDouble().clamp(1, 60),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    onChanged: (v) => setState(() => slot['duration_sec'] = v.toInt() * 60),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "ACTIVE DAYS",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map((day) {
                    final isSelected = (slot['days'] as List<String>).contains(day);
                    return GestureDetector(
                      onTap: () => _toggleDay(index, day),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? _ScheduleBottomSheet.kPrimaryColor : (isDark ? Colors.white10 : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.2)),
                        ),
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black87),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => widget.onClearSlot(index),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("CLEAR SLOT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => widget.onSaveSlot(index, slot['time'], slot['days'], slot['duration_sec'], slot['enabled']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ScheduleBottomSheet.kPrimaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text("SAVE CHANGES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBox({required String label, required String value, required IconData icon, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: _ScheduleBottomSheet.kPrimaryColor, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}
