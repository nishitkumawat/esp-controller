import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://api.machmate.in/iot';

  Map<String, dynamic> _safeDecode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (e) {
      return {'raw_body': body, 'parse_error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = _safeDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) return data;

      throw Exception(data['message'] ?? 'Request failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: const {'Content-Type': 'application/json'},
      );

      final data = _safeDecode(response.body);

      if (response.statusCode == 200) return data;

      throw Exception(data['message'] ?? 'Request failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // ---------- Auth ----------
  Future<Map<String, dynamic>> signup({
    required String phone,
    required String password,
    String? name,
  }) async {
    final payload = {'phone': phone, 'password': password};
    if (name != null && name.trim().isNotEmpty) payload['name'] = name.trim();
    return _post('/signup/', payload);
  }

  Future<Map<String, dynamic>> verifySignupOtp({
    required int userId,
    required String otp,
  }) async =>
      _post('/verify_signup_otp/', {'user_id': userId, 'otp': otp});

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async =>
      _post('/login/', {'phone': phone, 'password': password});

  Future<Map<String, dynamic>> forgotPasswordSendOtp({
    required String phone,
  }) async =>
      _post('/forgot_password_send_otp/', {'phone': phone});

  Future<Map<String, dynamic>> verifyForgotOtp({
    required int userId,
    required String otp,
    required String newPassword,
  }) async =>
      _post('/verify_forgot_otp/', {
        'user_id': userId,
        'otp': otp,
        'new_password': newPassword,
      });

  Future<Map<String, dynamic>> logout() async => _post('/logout/', {});

  // ---------- Devices ----------
  Future<Map<String, dynamic>> addDevice({
    required int userId,
    required String deviceCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/add_device/'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'device_code': deviceCode,
        }),
      );

      // For this endpoint we always return the body, even if status is not 200,
      // so that the UI can interpret custom statuses from the backend.
      return _safeDecode(response.body);
    } catch (e) {
      // Let the UI handle this as a real network error via its catch block.
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> getMyDevices({required int userId}) async =>
      _get('/my_devices/?user_id=$userId');

  Future<Map<String, dynamic>> renameDevice({
    required int deviceId,
    required String newName,
  }) async =>
      _post('/rename_device/', {
        'device_id': deviceId,
        'new_name': newName,
      });

  Future<Map<String, dynamic>> changeAdmin({
    required int deviceId,
    required int currentAdminUserId,
    required int newAdminUserId,
  }) async =>
      _post('/change_admin/', {
        'device_id': deviceId,
        'current_admin_user_id': currentAdminUserId,
        'new_admin_user_id': newAdminUserId,
      });

  Future<Map<String, dynamic>> sendAccessRequest({
    required int userId,
    required int deviceId,
  }) async =>
      _post('/send_access_request/', {
        'user_id': userId,
        'device_id': deviceId,
      });

  Future<Map<String, dynamic>> getPendingAccessRequests({
    required int adminUserId,
  }) async =>
      _get('/pending_access_requests/?admin_user_id=$adminUserId');

  Future<Map<String, dynamic>> approveAccess({
    required int requestId,
    required int adminUserId,
  }) async =>
      _post('/approve_access/', {
        'request_id': requestId,
        'admin_user_id': adminUserId,
      });

  Future<Map<String, dynamic>> rejectAccess({
    required int requestId,
    required int adminUserId,
  }) async =>
      _post('/reject_access/', {
        'request_id': requestId,
        'admin_user_id': adminUserId,
      });

  Future<Map<String, dynamic>> getDeviceMembers({
    required int deviceId,
  }) async =>
      _get('/device_members/?device_id=$deviceId');


  // ---------- ✅ Device Control (Final Fixed Version) ----------
  Future<Map<String, dynamic>> controlDevice({
    required int deviceId,
    required String command,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final int? userId = prefs.getInt("user_id");

    if (userId == null) {
      throw Exception("User not logged in");
    }

    final result = await _post('/control_device/', {
      'user_id': userId,
      'device_id': deviceId,
      'command': command,
    });

    return {
      "status": result["status"] is bool ? result["status"] : result["status"] == "true",
      "message": result["message"] ?? "",
      "device_id": (result["device_id"] is int)
          ? result["device_id"]
          : int.tryParse(result["device_id"].toString()),
    };
  }

  Future<Map<String, dynamic>> tester() async => _get('/tester/');

  Future<Map<String, dynamic>> removeAccess({
    required int deviceId,
    required int userId,
    required int adminUserId,
  }) async =>
      _post('/remove_access/', {
        'device_id': deviceId,
        'user_id': userId,
        'admin_user_id': adminUserId,
      });

  Future<Map<String, dynamic>> deleteDevice({
    required int deviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final int? userId = prefs.getInt("user_id");

    if (userId == null) {
      throw Exception("User not logged in");
    }

    return _post('/delete_device/', {
      'device_id': deviceId,
      'user_id': userId,
    });
  }
}
