import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/background_service.dart';

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
      title: 'GPS Tracker',
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

  final _relayUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _pubKeyController = TextEditingController();
  StreamSubscription? _locationSub;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _checkServiceStatus();
    _listenToLocationUpdates();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _relayUrlController.text = prefs.getString(kRelayUrlKey) ?? '';
      _tokenController.text = prefs.getString(kTokenKey) ?? '';
      _pubKeyController.text = prefs.getString(kServerPubKeyKey) ?? '';
    });
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

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kRelayUrlKey, _relayUrlController.text.trim());
    await prefs.setString(kTokenKey, _tokenController.text.trim());
    await prefs.setString(kServerPubKeyKey, _pubKeyController.text.trim());
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

    await _saveSettings();
    await service.startService();
    setState(() => _isTracking = true);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _relayUrlController.dispose();
    _tokenController.dispose();
    _pubKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS 背景定位'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(
                isTracking: _isTracking,
                lat: _lastLat,
                lng: _lastLng,
                timestamp: _lastTimestamp,
                gpsError: _lastError,
                postError: _postError,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _relayUrlController,
                decoration: const InputDecoration(
                  labelText: 'Relay URL',
                  hintText: 'wss://example.com/relay',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => _saveSettings(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Token（配對碼）',
                  hintText: '由 OpenClaw 提供',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                onChanged: (_) => _saveSettings(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pubKeyController,
                decoration: const InputDecoration(
                  labelText: '伺服器公鑰',
                  hintText: '由 OpenClaw 提供（Base64）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                maxLines: 2,
                onChanged: (_) => _saveSettings(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _toggleTracking,
                icon: Icon(_isTracking ? Icons.stop_circle : Icons.play_circle),
                label: Text(
                  _isTracking ? '停止追蹤' : '開始追蹤',
                  style: const TextStyle(fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _isTracking ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '每 30 秒自動取得一次 GPS 並透過加密 WebSocket 傳送',
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
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
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
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 12,
                  height: 12,
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
                const SizedBox(width: 10),
                Text(
                  'GPS 狀態：${isTracking ? '追蹤中' : '已停止'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (gpsError != null)
              _InfoRow(
                icon: Icons.error_outline,
                iconColor: Colors.red,
                label: 'GPS 錯誤',
                value: gpsError!,
              )
            else if (lat != null && lng != null) ...[
              _InfoRow(
                icon: Icons.my_location,
                label: '緯度',
                value: lat!.toStringAsFixed(6),
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.my_location,
                label: '經度',
                value: lng!.toStringAsFixed(6),
              ),
              if (timestamp != null) ...[
                const SizedBox(height: 6),
                _InfoRow(
                  icon: Icons.access_time,
                  label: '更新時間',
                  value: timestamp!,
                ),
              ],
              const SizedBox(height: 6),
              if (postError != null)
                _InfoRow(
                  icon: Icons.cloud_off,
                  iconColor: Colors.orange,
                  label: '傳送狀態',
                  value: postError!,
                )
              else
                const _InfoRow(
                  icon: Icons.cloud_done,
                  iconColor: Colors.green,
                  label: '傳送狀態',
                  value: '成功',
                ),
            ] else
              const Text(
                '尚無定位資料，請按「開始追蹤」',
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

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
        Icon(icon, size: 16, color: iconColor ?? Colors.blue),
        const SizedBox(width: 8),
        Text('$label：', style: const TextStyle(fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
