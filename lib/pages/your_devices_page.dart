import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/mqtt_service.dart';
import 'device_control_page.dart';
import 'solar_cleaner_page.dart';
import 'wash_control_page.dart';

class YourDevicesPage extends StatefulWidget {
  const YourDevicesPage({super.key});

  @override
  State<YourDevicesPage> createState() => _YourDevicesPageState();
}

class _YourDevicesPageState extends State<YourDevicesPage> with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final MqttService _mqttService = MqttService();
  List<dynamic> _devices = [];
  bool _isLoading = true;
  int? _userId;
  bool _autoOpenedSingleDevice = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  bool get wantKeepAlive => true;

  // Refresh when page becomes visible
  void refresh() {
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      _userId = await _authService.getUserId();
      if (_userId == null) {
        Fluttertoast.showToast(
          msg: 'User not logged in',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        return;
      }

      final response = await _apiService.getMyDevices(userId: _userId!);
      final devices = response['devices'] ?? [];

      if (!_autoOpenedSingleDevice && mounted && devices.length == 1) {
        _autoOpenedSingleDevice = true;
        setState(() {
          _devices = devices;
          _isLoading = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || devices.isEmpty) return;
          await _openDevice(devices.first, fromAutoOpen: true);
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
        });
      } else {
        setState(() {
          _devices = devices;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(
        msg: 'Network Error',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  Future<void> _openDevice(dynamic device, {bool fromAutoOpen = false}) async {
    final deviceName = device['name'] ?? 'Unnamed Device';
    final deviceCode = device['device_code'] ?? '';
    final dynamic rawDeviceId = device['device_id'] ?? device['id'];
    final int? deviceId = rawDeviceId is int
        ? rawDeviceId
        : int.tryParse(rawDeviceId?.toString() ?? '');
    final role = device['role'] ?? 'Member';
    final isAdmin = role == 'Admin' || role == 'admin';

    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) {
          // Check device type based on 2nd and 3rd characters
          // xxSM... -> Shutter Motor
          // xxCS... -> Solar Cleaner
          // xxOC... -> Solar Wash Control (New)
          bool isSolarCleaner = false;
          bool isWashControl = false;
          
          if (deviceCode.length >= 3) {
            final type = deviceCode.substring(1, 3).toUpperCase();
            if (type == 'CS') {
              isSolarCleaner = true;
            } else if (type == 'OC') {
              isWashControl = true;
            }
          }

          if (isSolarCleaner) {
            return SolarCleanerPage(
              deviceCode: deviceCode,
              deviceName: deviceName,
              deviceId: deviceId,
              isAdmin: isAdmin,
              skipInitialLoading: fromAutoOpen,
            );
          } else if (isWashControl) {
            return WashControlPage(
              deviceCode: deviceCode,
              deviceName: deviceName,
              deviceId: deviceId,
              isAdmin: isAdmin,
            ); 
          } else {
            return DeviceControlPage(
              deviceCode: deviceCode,
              deviceName: deviceName,
              deviceId: deviceId,
              isAdmin: isAdmin,
            );
          }
        },
      ),
    );
    if (deleted == true) {
      await _loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Your Devices',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3E50),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
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
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.devices_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No devices found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add a device to get started',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDevices,
                  color: const Color(0xFFFFA500),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final deviceName = device['name'] ?? 'Unnamed Device';
                      final deviceCode = device['device_code'] ?? '';
                      final dynamic rawDeviceId = device['device_id'] ?? device['id'];
                      final int? deviceId = rawDeviceId is int
                          ? rawDeviceId
                          : int.tryParse(rawDeviceId?.toString() ?? '');
                      final role = device['role'] ?? 'Member';
                      final isAdmin = role == 'Admin' || role == 'admin';

                      return InkWell(
                        onTap: () async {
                          await _openDevice(device);
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.black.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFA500).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.devices_outlined,
                                  color: Color(0xFFFFA500),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      deviceName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2C3E50),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      deviceCode,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isAdmin
                                            ? const Color(0xFFFFA500).withOpacity(0.14)
                                            : Colors.black.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isAdmin
                                              ? const Color(0xFFFFA500)
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade600,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

