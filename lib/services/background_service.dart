import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'encryption.dart';

const String kRelayUrlKey = 'relay_url';
const String kTokenKey = 'relay_token';
const String kServerPubKeyKey = 'server_pub_key';
const String _channelId = 'location_tracking_channel';

// Module-level WebSocket — persists across GPS updates within the same isolate
WebSocketChannel? _wsChannel;

Future<void> initializeService() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'GPS 追蹤服務',
          description: '背景 GPS 定位追蹤通知',
          importance: Importance.low,
        ),
      );

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _channelId,
      initialNotificationTitle: 'GPS 追蹤服務',
      initialNotificationContent: '正在追蹤位置...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    _wsChannel?.sink.close();
    _wsChannel = null;
    service.stopSelf();
  });

  await _trackAndReport(service);

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await _trackAndReport(service);
  });
}

/// Returns the existing WebSocket channel, or creates a new one.
/// Returns null if relay URL or token are not configured.
Future<WebSocketChannel?> _getChannel() async {
  if (_wsChannel != null) return _wsChannel;

  final prefs = await SharedPreferences.getInstance();
  final relayUrl = prefs.getString(kRelayUrlKey) ?? '';
  final token = prefs.getString(kTokenKey) ?? '';
  if (relayUrl.isEmpty || token.isEmpty) return null;

  final base = relayUrl.endsWith('/') ? relayUrl.substring(0, relayUrl.length - 1) : relayUrl;
  final wsUrl = '$base/ws/$token';
  _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
  return _wsChannel;
}

Future<void> _trackAndReport(ServiceInstance service) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    final timestamp = DateTime.now().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    final serverPubKey = prefs.getString(kServerPubKeyKey) ?? '';

    String? sendError;
    if (serverPubKey.isNotEmpty) {
      try {
        final encrypted = await encryptGpsPayload(
          lat: position.latitude,
          lng: position.longitude,
          timestamp: timestamp,
          serverPubKeyB64: serverPubKey,
        );
        final channel = await _getChannel();
        if (channel != null) {
          channel.sink.add(jsonEncode(encrypted));
        } else {
          sendError = '未設定 Relay URL 或 Token';
        }
      } catch (e) {
        _wsChannel = null; // 重置，下次重新連線
        sendError = '傳送失敗: $e';
      }
    } else {
      sendError = '未設定伺服器公鑰';
    }

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'GPS 追蹤中',
          content:
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
        );
      }
    }

    service.invoke('locationUpdate', {
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': timestamp,
      'postError': sendError,
      'success': true,
    });
  } catch (e) {
    service.invoke('locationUpdate', {
      'success': false,
      'error': e.toString(),
    });
  }
}
