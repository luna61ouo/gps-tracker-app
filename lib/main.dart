import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/settings_screen.dart';
import 'services/background_service.dart';

const String kRelayUrlListKey = 'relay_url_list';
const String kDefaultRelayUrl = 'wss://your-relay.example.com/relay';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const GpsTrackerApp());
}

class GpsTrackerApp extends StatelessWidget {
  const GpsTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenClaw GPS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TrackingHomePage(),
    );
  }
}

class TrackingHomePage extends StatefulWidget {
  const TrackingHomePage({super.key});

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage> {
  bool _isTracking = false;
  double? _lastLat;
  double? _lastLng;
  String? _lastTimestamp;
  String? _lastError;
  String? _postError;
  StreamSubscription? _locationSub;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    _listenToLocationUpdates();
    _ensureDefaultRelay();
  }

  Future<void> _ensureDefaultRelay() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getStringList(kRelayUrlListKey) == null) {
      await prefs.setStringList(kRelayUrlListKey, [kDefaultRelayUrl]);
      await prefs.setString(kRelayUrlKey, kDefaultRelayUrl);
    }
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await FlutterBackgroundService().isRunning();
    if (mounted) setState(() => _isTracking = isRunning);
  }

  void _listenToLocationUpdates() {
    _locationSub =
        FlutterBackgroundService().on('locationUpdate').listen((event) {
      if (event == null || !mounted) return;
      setState(() {
        if (event['success'] == true) {
          _lastLat = (event['lat'] as num).toDouble();
          _lastLng = (event['lng'] as num).toDouble();
          _lastTimestamp = event['timestamp'] as String?;
          _lastError = null;
          _postError = event['postError'] as String?;
        } else {
          _lastError = event['error'] as String?;
        }
      });
    });
  }

  Future<bool> _requestPermissions() async {
    await Permission.notification.request();
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      return false;
    }
    final bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      final result = await Permission.locationAlways.request();
      if (!result.isGranted) {
        return perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always;
      }
    }
    return true;
  }

  Future<void> _toggleTracking() async {
    final service = FlutterBackgroundService();
    if (_isTracking) {
      service.invoke('stopService');
      setState(() => _isTracking = false);
      return;
    }
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要背景定位權限\n請至設定開啟「永遠允許」定位'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    await service.startService();
    setState(() => _isTracking = true);
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('關於 OpenClaw GPS'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'OpenClaw GPS 是專為 OpenClaw AI 助理設計的背景定位工具。',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 12),
              Text('運作方式：'),
              SizedBox(height: 6),
              Text('1. 手機每 30 秒取得一次 GPS 座標'),
              Text('2. 座標經過端對端加密（X25519 + AES-256-GCM）'),
              Text('3. 透過中繼伺服器傳送給你的電腦'),
              Text('4. OpenClaw 可以詢問你目前的位置'),
              SizedBox(height: 12),
              Text('設定方式：'),
              SizedBox(height: 6),
              Text('在 OpenClaw 中安裝 gps-bridge，它會提供你 Token 和公鑰，輸入到本 App 的設定中即可完成配對。'),
              SizedBox(height: 12),
              Text(
                '資料安全：伺服器只轉送加密資料，無法讀取你的位置。',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.satellite_alt, size: 20),
            SizedBox(width: 8),
            Text('OpenClaw GPS'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '說明',
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 可收合的 GPS 狀態
          _GpsStatusTile(
            isTracking: _isTracking,
            lat: _lastLat,
            lng: _lastLng,
            timestamp: _lastTimestamp,
            gpsError: _lastError,
            postError: _postError,
          ),

          // 中心圓形追蹤按鈕
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TrackingButton(
                    isTracking: _isTracking,
                    onTap: _toggleTracking,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '每 30 秒自動更新 GPS\n端對端加密傳送給 OpenClaw',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 可收合的 GPS 狀態卡片
// ---------------------------------------------------------------------------

class _GpsStatusTile extends StatelessWidget {
  const _GpsStatusTile({
    required this.isTracking,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.gpsError,
    required this.postError,
  });

  final bool isTracking;
  final double? lat;
  final double? lng;
  final String? timestamp;
  final String? gpsError;
  final String? postError;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: 1,
      child: ExpansionTile(
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isTracking ? Colors.green : Colors.grey,
            boxShadow: isTracking
                ? [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
        ),
        title: Text(
          isTracking ? '追蹤中' : '已停止',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isTracking ? Colors.green : Colors.grey,
          ),
        ),
        subtitle: lat != null
            ? Text(
                '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12),
              )
            : const Text('尚無定位資料', style: TextStyle(fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                if (gpsError != null)
                  _InfoRow(
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      label: 'GPS 錯誤',
                      value: gpsError!)
                else if (lat != null && lng != null) ...[
                  _InfoRow(
                      icon: Icons.my_location,
                      label: '緯度',
                      value: lat!.toStringAsFixed(6)),
                  const SizedBox(height: 4),
                  _InfoRow(
                      icon: Icons.my_location,
                      label: '經度',
                      value: lng!.toStringAsFixed(6)),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                        icon: Icons.access_time,
                        label: '更新時間',
                        value: timestamp!),
                  ],
                  const SizedBox(height: 4),
                  if (postError != null)
                    _InfoRow(
                        icon: Icons.cloud_off,
                        iconColor: Colors.orange,
                        label: '傳送狀態',
                        value: postError!)
                  else
                    const _InfoRow(
                        icon: Icons.cloud_done,
                        iconColor: Colors.green,
                        label: '傳送狀態',
                        value: '成功'),
                ] else
                  const Text('尚無定位資料，請按下方按鈕開始追蹤',
                      style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 圓形追蹤按鈕
// ---------------------------------------------------------------------------

class _TrackingButton extends StatelessWidget {
  const _TrackingButton({required this.isTracking, required this.onTap});

  final bool isTracking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isTracking ? Colors.red : Colors.green,
          boxShadow: [
            BoxShadow(
              color: (isTracking ? Colors.red : Colors.green)
                  .withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isTracking ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 56,
              color: Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              isTracking ? '停止追蹤' : '開始追蹤',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 共用 Widget
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: iconColor ?? Colors.blue),
        const SizedBox(width: 6),
        Text('$label：', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
