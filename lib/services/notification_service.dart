import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationType {
  washStarted,
  washCompleted,
  washSkippedRain,
  deviceOffline,
  rainSmartSkipEnabled,
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String description;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'title': title,
        'description': description,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'isRead': isRead,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      type: NotificationType.values[json['type'] as int],
      title: json['title'],
      description: json['description'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      isRead: json['isRead'] ?? false,
    );
  }

  static String iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.washStarted:
        return '🚿';
      case NotificationType.washCompleted:
        return '✅';
      case NotificationType.washSkippedRain:
        return '🌧️';
      case NotificationType.deviceOffline:
        return '📵';
      case NotificationType.rainSmartSkipEnabled:
        return '☔';
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _prefKey = 'ezrun_notifications';
  static const int _maxNotifications = 100;

  List<AppNotification> _notifications = [];
  bool _loaded = false;
  final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await _initLocalNotifications();
    await loadNotifications();
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initSettings = InitializationSettings(
      android: initAndroid,
      iOS: initIOS,
    );
    await _localNotifs.initialize(settings: initSettings);

    await _localNotifs
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _notifications = list
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        // Newest first
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      _loaded = true;
    } catch (e) {
      _notifications = [];
      _loaded = true;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _notifications.map((n) => n.toJson()).toList();
    await prefs.setString(_prefKey, jsonEncode(list));
  }

  Future<AppNotification> addNotification({
    required NotificationType type,
    required String title,
    required String description,
  }) async {
    await _ensureLoaded();

    final notif = AppNotification(
      id: '${DateTime.now().millisecondsSinceEpoch}_${type.index}',
      type: type,
      title: title,
      description: description,
      timestamp: DateTime.now(),
      isRead: false,
    );

    _notifications.insert(0, notif);

    // Keep max
    if (_notifications.length > _maxNotifications) {
      _notifications = _notifications.take(_maxNotifications).toList();
    }

    await _save();
    
    // Show system notification
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'ezrun_channel_id',
      'EZrun Notifications',
      channelDescription: 'Notifications for wash events and device status',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    await _localNotifs.show(
      id: notif.timestamp.millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: description,
      notificationDetails: details,
    );

    return notif;
  }

  Future<void> markAllRead() async {
    await _ensureLoaded();
    for (final n in _notifications) {
      n.isRead = true;
    }
    await _save();
  }

  Future<void> markRead(String id) async {
    await _ensureLoaded();
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notifications[idx].isRead = true;
      await _save();
    }
  }

  Future<void> clearAll() async {
    _notifications.clear();
    await _save();
  }

  /// Parse an MQTT event payload and create the appropriate notification.
  /// Returns null if the event is unknown or unhandled.
  Future<AppNotification?> handleMqttEvent(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    final source = data['source']?.toString() ?? '';
    final durationSec = data['duration_sec'] as int? ?? 0;

    switch (type) {
      case 'WASH_STARTED':
        String desc;
        if (source == 'MANUAL') {
          desc = 'Manual wash started';
        } else if (source == 'SCHEDULE') {
          final mins = durationSec ~/ 60;
          desc = 'Wash started for $mins minute${mins != 1 ? 's' : ''} by schedule';
        } else if (source == 'INTERVAL') {
          final mins = durationSec ~/ 60;
          desc = 'Wash started for $mins minute${mins != 1 ? 's' : ''} by interval';
        } else {
          desc = 'Wash has started';
        }
        return addNotification(
          type: NotificationType.washStarted,
          title: 'Wash Started',
          description: desc,
        );

      case 'WASH_COMPLETED':
        return addNotification(
          type: NotificationType.washCompleted,
          title: 'Wash Completed',
          description: 'Solar panel wash completed successfully',
        );

      case 'WASH_SKIPPED_RAIN':
        return addNotification(
          type: NotificationType.washSkippedRain,
          title: 'Wash Skipped — Rain Detected',
          description: 'Automatic wash was skipped due to recent rainfall',
        );

      default:
        return null;
    }
  }
}
