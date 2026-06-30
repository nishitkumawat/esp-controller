import 'package:shared_preferences/shared_preferences.dart';

class RainSkipSettings {
  final bool enabled;
  final double lat;
  final double lon;
  final int threshold; // mm

  const RainSkipSettings({
    this.enabled = false,
    this.lat = 0.0,
    this.lon = 0.0,
    this.threshold = 3,
  });

  RainSkipSettings copyWith({
    bool? enabled,
    double? lat,
    double? lon,
    int? threshold,
  }) {
    return RainSkipSettings(
      enabled: enabled ?? this.enabled,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      threshold: threshold ?? this.threshold,
    );
  }
}

class RainSkipService {
  static final RainSkipService _instance = RainSkipService._internal();
  factory RainSkipService() => _instance;
  RainSkipService._internal();

  static const String _keyEnabled = 'rain_skip_enabled';
  static const String _keyLat = 'rain_skip_lat';
  static const String _keyLon = 'rain_skip_lon';
  static const String _keyThreshold = 'rain_skip_threshold';

  Future<RainSkipSettings> load(String deviceCode) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '${deviceCode}_';
    return RainSkipSettings(
      enabled: prefs.getBool('$prefix$_keyEnabled') ?? false,
      lat: prefs.getDouble('$prefix$_keyLat') ?? 0.0,
      lon: prefs.getDouble('$prefix$_keyLon') ?? 0.0,
      threshold: prefs.getInt('$prefix$_keyThreshold') ?? 3,
    );
  }

  Future<void> save(String deviceCode, RainSkipSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '${deviceCode}_';
    await prefs.setBool('$prefix$_keyEnabled', settings.enabled);
    await prefs.setDouble('$prefix$_keyLat', settings.lat);
    await prefs.setDouble('$prefix$_keyLon', settings.lon);
    await prefs.setInt('$prefix$_keyThreshold', settings.threshold);
  }
}
