import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class AuthService {
  static const _isLoggedInKey = 'isLoggedIn';
  static const _loggedPhoneKey = 'loggedPhone';
  static const _userIdKey = 'user_id';

  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> signup({
    required String phone,
    required String password,
    String? name,
  }) {
    return _api.signup(phone: phone, password: password, name: name);
  }

  Future<Map<String, dynamic>> verifySignupOtp({
    required int userId,
    required String otp,
  }) {
    return _api.verifySignupOtp(userId: userId, otp: otp);
  }

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    final response = await _api.login(phone: phone, password: password);
    if (_isSuccess(response['status'])) {
      final userId = _parseInt(response['user_id']);
      if (userId != null) {
        await _saveSession(userId: userId, phone: phone);
      }
    }
    return response;
  }

  Future<Map<String, dynamic>> forgotPassword({required String phone}) {
    return _api.forgotPasswordSendOtp(phone: phone);
  }

  Future<Map<String, dynamic>> verifyForgotOtp({
    required int userId,
    required String otp,
    required String newPassword,
  }) {
    return _api.verifyForgotOtp(
      userId: userId,
      otp: otp,
      newPassword: newPassword,
    );
  }

  Future<Map<String, dynamic>> tester() {
    return _api.tester();
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<String?> getLoggedInPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_loggedPhoneKey);
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {
      // Ignore network errors during logout; still clear local session.
    } finally {
      await _clearSession();
    }
  }

  Future<void> _saveSession({
    required int userId,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_loggedPhoneKey, phone);
    await prefs.setInt(_userIdKey, userId);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, false);
    await prefs.remove(_loggedPhoneKey);
    await prefs.remove(_userIdKey);
  }

  bool _isSuccess(dynamic status) {
    if (status is bool) {
      return status;
    }
    if (status is num) {
      return status == 1;
    }
    if (status is String) {
      final normalized = status.toLowerCase().trim();
      return [
        'true',
        'success',
        'ok',
        'passed',
        '1',
      ].contains(normalized);
    }
    return false;
  }

  int? _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

