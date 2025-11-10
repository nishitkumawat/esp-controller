import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://api.machmate.in/iot';

  Map<String, dynamic> _safeDecode(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'data': decoded};
    } catch (e) {
      return <String, dynamic>{
        'raw_body': body,
        'parse_error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final response = await http.post(
        url,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = _safeDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return data;
      }

      throw Exception(data['message'] ?? 'Request failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final response = await http.get(
        url,
        headers: const {'Content-Type': 'application/json'},
      );

      final data = _safeDecode(response.body);

      if (response.statusCode == 200) {
        return data;
      }

      throw Exception(data['message'] ?? 'Request failed (${response.statusCode})');
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ---------- Auth ----------
  Future<Map<String, dynamic>> signup({
    required String phone,
    required String password,
    String? name,
  }) async {
    final payload = <String, dynamic>{
      'phone': phone,
      'password': password,
    };

    if (name != null && name.trim().isNotEmpty) {
      payload['name'] = name.trim();
    }

    return _post('/signup/', payload);
  }

  Future<Map<String, dynamic>> verifySignupOtp({
    required int userId,
    required String otp,
  }) async {
    return _post('/verify_signup_otp/', {
      'user_id': userId,
      'otp': otp,
    });
  }

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    return _post('/login/', {
      'phone': phone,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> forgotPasswordSendOtp({
    required String phone,
  }) async {
    return _post('/forgot_password_send_otp/', {
      'phone': phone,
    });
  }

  Future<Map<String, dynamic>> verifyForgotOtp({
    required int userId,
    required String otp,
    required String newPassword,
  }) async {
    return _post('/verify_forgot_otp/', {
      'user_id': userId,
      'otp': otp,
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> logout() async {
    return _post('/logout/', {});
  }

  // ---------- Device Management ----------
  Future<Map<String, dynamic>> addDevice({
    required int userId,
    required String deviceCode,
  }) async {
    return _post('/add_device/', {
      'user_id': userId,
      'device_code': deviceCode,
    });
  }

  Future<Map<String, dynamic>> getMyDevices({
    required int userId,
  }) async {
    return _get('/my_devices/?user_id=$userId');
  }

  Future<Map<String, dynamic>> renameDevice({
    required int deviceId,
    required String newName,
  }) async {
    return _post('/rename_device/', {
      'device_id': deviceId,
      'new_name': newName,
    });
  }

  Future<Map<String, dynamic>> changeAdmin({
    required int deviceId,
    required int newAdminUserId,
  }) async {
    return _post('/change_admin/', {
      'device_id': deviceId,
      'new_admin_user_id': newAdminUserId,
    });
  }

  // ---------- Access Requests ----------
  Future<Map<String, dynamic>> sendAccessRequest({
    required int userId,
    required int deviceId,
  }) async {
    return _post('/send_access_request/', {
      'user_id': userId,
      'device_id': deviceId,
    });
  }

  Future<Map<String, dynamic>> getPendingAccessRequests({
    required int adminUserId,
  }) async {
    return _get('/pending_access_requests/?admin_user_id=$adminUserId');
  }

  Future<Map<String, dynamic>> approveAccess({
    required int requestId,
    required int adminUserId,
  }) async {
    return _post('/approve_access/', {
      'request_id': requestId,
      'admin_user_id': adminUserId,
    });
  }

  // ---------- Device Control ----------
  Future<Map<String, dynamic>> controlDevice({
    required int deviceId,
    required String command,
  }) async {
    return _post('/control_device/', {
      'device_id': deviceId,
      'command': command,
    });
  }

  Future<Map<String, dynamic>> tester() async {
    return _get('/tester/');
  }
}

