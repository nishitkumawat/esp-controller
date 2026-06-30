import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  final NotificationService _svc = NotificationService();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const Color kPrimary = Color(0xFF102A43);
  static const Color kAccent = Color(0xFFFF9F43);
  static const Color kBg = Color(0xFFF0F4F8);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _svc.markAllRead().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.washStarted:
        return Icons.water_drop_rounded;
      case NotificationType.washCompleted:
        return Icons.check_circle_rounded;
      case NotificationType.washSkippedRain:
        return Icons.cloud_rounded;
      case NotificationType.deviceOffline:
        return Icons.signal_wifi_off_rounded;
      case NotificationType.rainSmartSkipEnabled:
        return Icons.umbrella_rounded;
    }
  }

  Color _colorFor(NotificationType type) {
    switch (type) {
      case NotificationType.washStarted:
        return const Color(0xFF3498DB);
      case NotificationType.washCompleted:
        return const Color(0xFF27AE60);
      case NotificationType.washSkippedRain:
        return const Color(0xFF9B59B6);
      case NotificationType.deviceOffline:
        return const Color(0xFFE74C3C);
      case NotificationType.rainSmartSkipEnabled:
        return kAccent;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications',
            style: TextStyle(fontWeight: FontWeight.bold, color: kPrimary)),
        content: const Text('This will permanently delete all notifications.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear All',
                  style: TextStyle(color: Color(0xFFE74C3C)))),
        ],
      ),
    );
    if (ok == true) {
      await _svc.clearAll();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _svc.notifications;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: kPrimary, size: 20),
                  ),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        color: kPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (notifications.isNotEmpty)
                    TextButton(
                      onPressed: _clearAll,
                      child: const Text('Clear All',
                          style: TextStyle(
                              color: Color(0xFFE74C3C),
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),

            // List
            Expanded(
              child: notifications.isEmpty
                  ? FadeTransition(
                      opacity: _fadeAnim,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: kAccent.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_none_rounded,
                                  color: kAccent, size: 40),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'No Notifications Yet',
                              style: TextStyle(
                                color: kPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Wash events will appear here in real-time',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : FadeTransition(
                      opacity: _fadeAnim,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: notifications.length,
                        itemBuilder: (ctx, i) {
                          return _buildNotifCard(notifications[i], i);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotifCard(AppNotification notif, int index) {
    final color = _colorFor(notif.type);
    final icon = _iconFor(notif.type);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + index * 50),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - val)),
          child: Opacity(opacity: val, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          _timeAgo(notif.timestamp),
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notif.description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
