import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

class AccountPage extends StatefulWidget {
  AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<dynamic> _pendingRequests = [];
  List<dynamic> _adminDevices = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _userId = await _authService.getUserId();
      if (_userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get user's devices to check if they are admin
      final devicesResponse = await _apiService.getMyDevices(userId: _userId!);
      final devices = devicesResponse['devices'] ?? [];
      
      _adminDevices = devices.where((device) {
        final role = device['role'] ?? '';
        return role == 'Admin' || role == 'admin';
      }).toList();

      _isAdmin = _adminDevices.isNotEmpty;

      // If admin, load pending requests
      if (_isAdmin) {
        final requestsResponse = await _apiService.getPendingAccessRequests(
          adminUserId: _userId!,
        );
        setState(() {
          _pendingRequests = requestsResponse['requests'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(
        msg: 'Failed to load data: ${e.toString()}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _approveRequest(int requestId) async {
    try {
      if (_userId == null) return;

      await _apiService.approveAccess(
        requestId: requestId,
        adminUserId: _userId!,
      );
      Fluttertoast.showToast(
        msg: 'Access approved',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
      _loadData(); // Refresh
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to approve: ${e.toString()}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _changeAdmin(int deviceId) async {
    // Show dialog to enter new admin user ID
    final newAdminIdController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Change Admin',
          style: TextStyle(color: Color(0xFFFFA500)),
        ),
        content: TextField(
          controller: newAdminIdController,
          decoration: const InputDecoration(
            labelText: 'New Admin User ID',
            hintText: 'Enter user ID',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFA500),
              foregroundColor: Colors.white,
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (result == true && newAdminIdController.text.isNotEmpty) {
      final newAdminId = int.tryParse(newAdminIdController.text.trim());
      if (newAdminId == null) {
        Fluttertoast.showToast(
          msg: 'Enter a valid user ID',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }
      try {
        await _apiService.changeAdmin(
          deviceId: deviceId,
          newAdminUserId: newAdminId,
        );
        Fluttertoast.showToast(
          msg: 'Admin changed successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        _loadData(); // Refresh
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Failed to change admin: ${e.toString()}',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(color: Color(0xFFFFA500)),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFA500),
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Account',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFFFA500),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA500)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // User Info Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFA500).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Color(0xFFFFA500),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'User Account',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'User ID: ${_userId ?? "N/A"}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Admin Section
                  if (_isAdmin) ...[
                    const Text(
                      'Admin Features',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Pending Requests
                    if (_pendingRequests.isNotEmpty) ...[
                      const Text(
                        'Pending Access Requests',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._pendingRequests.map((request) {
                        final dynamic rawRequestId = request['request_id'];
                        final int? requestId = rawRequestId is int
                            ? rawRequestId
                            : int.tryParse(rawRequestId?.toString() ?? '');
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Device: ${request['device_name'] ?? 'Unknown'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'User: ${request['user_id'] ?? 'N/A'}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: requestId == null
                                      ? null
                                      : () => _approveRequest(requestId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                    // Change Admin Section
                    const Text(
                      'Change Admin',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._adminDevices.map((device) {
                      final dynamic rawDeviceId = device['device_id'] ?? device['id'];
                      final int? deviceId = rawDeviceId is int
                          ? rawDeviceId
                          : int.tryParse(rawDeviceId?.toString() ?? '');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(device['name'] ?? 'Unnamed Device'),
                          subtitle: Text('Device ID: ${device['device_id'] ?? 'N/A'}'),
                          trailing: ElevatedButton(
                            onPressed: deviceId == null
                                ? null
                                : () => _changeAdmin(deviceId),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFA500),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Change Admin'),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                  // Logout Button
                  ElevatedButton(
                    onPressed: _logout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

