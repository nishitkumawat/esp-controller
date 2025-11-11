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
  Map<int, List<dynamic>> _deviceMembers = {};
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
      final userId = await _authService.getUserId();
      if (userId == null) {
        setState(() {
          _userId = null;
          _isAdmin = false;
          _adminDevices = [];
          _pendingRequests = [];
          _deviceMembers = {};
          _isLoading = false;
        });
        return;
      }

      final devicesResponse = await _apiService.getMyDevices(userId: userId);
      final devicesData = devicesResponse['devices'];
      final List<dynamic> devices =
          devicesData is List ? List<dynamic>.from(devicesData) : <dynamic>[];

      final adminDevices = devices.where((device) {
        final role = _asMap(device)['role']?.toString().toLowerCase() ?? '';
        return role == 'admin';
      }).toList();

      final bool isAdmin = adminDevices.isNotEmpty;
      List<dynamic> pendingRequests = [];
      final memberMap = <int, List<dynamic>>{};

      if (isAdmin) {
        try {
          final requestsResponse =
              await _apiService.getPendingAccessRequests(adminUserId: userId);
          final requestsData = requestsResponse['requests'];
          if (requestsData is List) {
            pendingRequests = List<dynamic>.from(requestsData);
          }
        } catch (e) {
          Fluttertoast.showToast(
            msg: 'Failed to load access requests: ${e.toString()}',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
          );
        }

        for (final device in adminDevices) {
          final deviceId = _extractDeviceId(device);
          if (deviceId == null) continue;
          try {
            final membersResponse =
                await _apiService.getDeviceMembers(deviceId: deviceId);
            final membersData = membersResponse['members'];
            memberMap[deviceId] =
                membersData is List ? List<dynamic>.from(membersData) : <dynamic>[];
          } catch (e) {
            Fluttertoast.showToast(
              msg:
                  'Failed to load members for ${_extractDeviceName(device)}: ${e.toString()}',
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.red,
              textColor: Colors.white,
            );
            memberMap[deviceId] = <dynamic>[];
          }
        }
      }

      setState(() {
        _userId = userId;
        _adminDevices = List<dynamic>.from(adminDevices);
        _isAdmin = isAdmin;
        _pendingRequests = pendingRequests;
        _deviceMembers = memberMap;
        _isLoading = false;
      });
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

  Future<void> _rejectRequest(int requestId) async {
    try {
      if (_userId == null) return;
      await _apiService.rejectAccess(
        requestId: requestId,
        adminUserId: _userId!,
      );
      Fluttertoast.showToast(
        msg: 'Request rejected',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      _loadData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to reject: ${e.toString()}',
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
          currentAdminUserId: _userId!,
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

  Future<void> _makeAdmin(int deviceId, int newAdminUserId) async {
    try {
      await _apiService.changeAdmin(
        deviceId: deviceId,
        currentAdminUserId: _userId!,
        newAdminUserId: newAdminUserId,
      );
      Fluttertoast.showToast(
        msg: 'User promoted to admin',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
      _loadData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to make admin: ${e.toString()}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _removeAccess(int deviceId, {int? targetUserId}) async {
    if (_userId == null) return;

    int? userIdToRemove = targetUserId;

    if (userIdToRemove == null) {
      final userIdController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Remove Access',
            style: TextStyle(color: Color(0xFFFFA500)),
          ),
          content: TextField(
            controller: userIdController,
            decoration: const InputDecoration(
              labelText: 'User ID to remove',
              hintText: 'Enter user ID',
            ),
            autofocus: true,
            keyboardType: TextInputType.number,
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
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      userIdToRemove = int.tryParse(userIdController.text.trim());
      if (userIdToRemove == null) {
        Fluttertoast.showToast(
          msg: 'Enter a valid user ID',
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Remove Access',
            style: TextStyle(color: Color(0xFFFFA500)),
          ),
          content: Text('Remove access for user ID $userIdToRemove?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    try {
      await _apiService.removeAccess(
        deviceId: deviceId,
        userId: userIdToRemove,
        adminUserId: _userId!,
      );
      Fluttertoast.showToast(
        msg: 'Access removed',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
      _loadData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to remove access: ${e.toString()}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
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
                        final requestMap = _asMap(request);
                        final int? requestId = _toInt(requestMap['request_id']);
                        final int? deviceId = _toInt(requestMap['device_id']);
                        final int? requesterUserId = _toInt(requestMap['user_id']);
                        final deviceName =
                            requestMap['device_name']?.toString() ?? 'Unknown device';
                        final requesterPhone =
                            requestMap['phone']?.toString() ?? requestMap['phone_number']?.toString();
                        final requesterName = requestMap['name']?.toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            title: Text(
                              requesterName?.isNotEmpty == true
                                  ? requesterName!
                                  : (requesterPhone ?? 'User'),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Device: $deviceName',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                if (requesterPhone != null &&
                                    requesterPhone.isNotEmpty &&
                                    requesterPhone.toLowerCase() != 'null')
                                  Text(
                                    'Phone: $requesterPhone',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                ElevatedButton(
                                  onPressed: requestId == null ? null : () => _approveRequest(requestId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: const Text('Accept', style: TextStyle(fontSize: 12)),
                                ),
                                ElevatedButton(
                                  onPressed: requestId == null ? null : () => _rejectRequest(requestId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                                ),
                                ElevatedButton(
                                  onPressed: (deviceId == null || requesterUserId == null)
                                      ? null
                                      : () => _makeAdmin(deviceId, requesterUserId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFA500),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: const Text('Make Admin', style: TextStyle(fontSize: 12)),
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
                      final int? deviceId = _extractDeviceId(device);
                      if (deviceId == null) {
                        return const SizedBox.shrink();
                      }
                      final deviceMap = _asMap(device);
                      final deviceName =
                          deviceMap['name']?.toString() ?? 'Unnamed Device';
                      final deviceIdentifier =
                          deviceMap['device_id'] ?? deviceMap['id'] ?? 'N/A';
                      final members = _deviceMembers[deviceId] ?? <dynamic>[];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(deviceName),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Device ID: $deviceIdentifier',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ElevatedButton(
                                        onPressed: () => _changeAdmin(deviceId),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFFA500),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Change Admin'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _removeAccess(deviceId),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                        child: const Text('Remove Access'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (members.isNotEmpty) ...[
                                const Text(
                                  'Members',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...members.map<Widget>((memberData) {
                                  final memberMap = _asMap(memberData);
                                  return _buildMemberRow(deviceId, memberMap);
                                }),
                              ] else
                                Text(
                                  'No members linked yet.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
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

  // Helper methods
  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int? _extractDeviceId(dynamic device) {
    final deviceMap = _asMap(device);
    return _toInt(deviceMap['device_id']) ?? _toInt(deviceMap['id']);
  }

  String _extractDeviceName(dynamic device) {
    final deviceMap = _asMap(device);
    return deviceMap['name']?.toString() ?? 'Unnamed Device';
  }

  Widget _buildMemberRow(int deviceId, Map<String, dynamic> member) {
    final userId = _toInt(member['user_id']);
    final phone = member['phone']?.toString() ?? member['phone_number']?.toString() ?? 'N/A';
    final role = member['role']?.toString().toLowerCase() ?? 'member';
    final name = member['name']?.toString();
    final isAdmin = role == 'admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name ?? 'User ID: ${userId ?? 'N/A'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFA500).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFA500),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (userId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'ID: $userId',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
                if (phone != 'N/A' && phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Phone: $phone',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isAdmin && userId != null && _userId != null) ...[
            ElevatedButton(
              onPressed: () => _makeAdmin(deviceId, userId),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFA500),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'Make Admin',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _removeAccessForUser(deviceId, userId),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'Remove',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _removeAccessForUser(int deviceId, int targetUserId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Remove Access',
          style: TextStyle(color: Color(0xFFFFA500)),
        ),
        content: Text('Are you sure you want to remove access for User ID $targetUserId?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true && _userId != null) {
      try {
        await _apiService.removeAccess(
          deviceId: deviceId,
          userId: targetUserId,
          adminUserId: _userId!,
        );
        Fluttertoast.showToast(
          msg: 'Access removed',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
        _loadData();
      } catch (e) {
        Fluttertoast.showToast(
          msg: 'Failed to remove access: ${e.toString()}',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }
}

