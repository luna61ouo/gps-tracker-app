import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'encryption.dart';

const String kRelayUrlKey = 'relay_url';
const String kTokenKey = 'relay_token';
const String kServerPubKeyKey = 'server_pub_key';
const String kBgIntervalKey = 'bg_interval';
const String kConfirmModeKey = 'confirm_mode';
const String kHistoryGranularityKey = 'history_granularity';
const String kHistoryRetentionKey = 'history_retention';
const String kTrackingEnabledKey = 'tracking_enabled';
const String kFgServiceModeKey = 'fg_service_mode';
const String kTimezoneOffsetKey = 'timezone_offset_minutes';
const int kTimezoneAuto = -99999; // sentinel: use system timezone
const int kFgIntervalSeconds = 5;
const int kDefaultBgIntervalSeconds = 60;
const String kDefaultConfirmMode = 'auto';
const int kDefaultHistoryGranularitySeconds = 600; // 10 minutes
const int kDefaultHistoryRetentionHours = 168;    // 1 week
const String _channelId = 'location_tracking_channel';
const String _requestChannelId = 'location_request_channel';

// Module-level WebSocket — persists across GPS updates within the same isolate
WebSocketChannel? _wsChannel;
StreamSubscription? _wsListenSub;
bool _pendingLocationRequest = false;

// Outgoing queue — retains up to _kMaxQueueSize encrypted payloads when offline
final List<Map<String, String>> _sendQueue = [];
const int _kMaxQueueSize = 20;

// Timestamp of the last successful send (UTC ISO-8601), persists across ticks
String? _lastSentAt;

// Delivery confirmation tracking
DateTime? _lastSendTime;      // wall-clock time of last send
String? _lastConfirmedAt;     // ISO-8601 UTC when bridge confirmed receipt
int _unconfirmedCount = 0;    // consecutive sends without confirmation

// Motion detection
bool _hasMovedSinceLastFix = true; // true so first fix always happens
double? _baselineMagnitude;
StreamSubscription? _accelSub;

// Interval control
bool _useFgInterval = false;
int _bgInterval = kDefaultBgIntervalSeconds;
bool _serviceRunning = false;

// Confirm mode and history tracking
String _confirmMode = kDefaultConfirmMode;
int _historyGranularitySeconds = kDefaultHistoryGranularitySeconds;
int _historyRetentionHours = kDefaultHistoryRetentionHours;
DateTime? _lastHistorySave;

// Last known position — used when stationary to avoid GPS acquisition but still report
Position? _lastKnownPosition;

// Timestamp of the last actual GPS acquisition (not just a heartbeat send)
String? _lastGpsTimestamp;

// iOS location stream subscription
StreamSubscription<Position>? _iosLocationSub;
DateTime? _lastIosReport;
Timer? _iosHeartbeat;

/// Returns current UTC time as ISO-8601 truncated to 1 decimal place (tenths of a second).
/// e.g. "2026-03-27T10:23:45.1Z" instead of "2026-03-27T10:23:45.123456Z"
String _nowIso() {
  final s = DateTime.now().toUtc().toIso8601String();
  final dot = s.indexOf('.');
  if (dot == -1) return s;
  return '${s.substring(0, dot + 2)}Z';
}

Future<void> initializeService() async {
  try {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
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
        autoStart: true,
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
  } catch (e) {
    debugPrint('initializeService error: $e');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Start motion detection via accelerometer.
/// Sets _hasMovedSinceLastFix = true whenever significant movement is detected.
void _startMotionDetection() {
  _accelSub?.cancel();
  try {
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final mag = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z);
      if (_baselineMagnitude == null) {
        _baselineMagnitude = mag;
      } else if ((mag - _baselineMagnitude!).abs() > 0.5) {
        _hasMovedSinceLastFix = true;
        _baselineMagnitude = mag;
      }
    });
  } catch (_) {
    // Sensor unavailable — always assume moved so GPS is never skipped
    _hasMovedSinceLastFix = true;
  }
}

/// Recursively schedules the next GPS report after the current interval elapses.
void _scheduleNext(ServiceInstance service) {
  if (!_serviceRunning) return;
  final interval = _useFgInterval ? kFgIntervalSeconds : _bgInterval;
  Future.delayed(Duration(seconds: interval), () async {
    if (!_serviceRunning) return;
    await _trackAndReport(service);
    _scheduleNext(service);
  });
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // Guard: if the user never enabled tracking (e.g. autoStart on boot before setup),
  // stop immediately rather than running an unconfigured service.
  final trackingEnabled = prefs.getBool(kTrackingEnabledKey) ?? false;
  if (!trackingEnabled) {
    service.stopSelf();
    return;
  }

  _serviceRunning = true;
  _hasMovedSinceLastFix = true;

  _bgInterval = prefs.getInt(kBgIntervalKey) ?? kDefaultBgIntervalSeconds;
  _confirmMode = prefs.getString(kConfirmModeKey) ?? kDefaultConfirmMode;
  _historyGranularitySeconds = prefs.getInt(kHistoryGranularityKey) ?? kDefaultHistoryGranularitySeconds;
  _historyRetentionHours = prefs.getInt(kHistoryRetentionKey) ?? kDefaultHistoryRetentionHours;

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    _wsListenSub?.cancel();
    _wsListenSub = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _accelSub?.cancel();
    _accelSub = null;
    _iosLocationSub?.cancel();
    _iosLocationSub = null;
    _iosHeartbeat?.cancel();
    _iosHeartbeat = null;
    _pendingLocationRequest = false;
    _serviceRunning = false;
    service.stopSelf();
  });

  // Sent by main UI when app goes foreground / background
  service.on('setUpdateInterval').listen((event) {
    if (event == null) return;
    _useFgInterval = event['foreground'] == true;
    if (event['interval'] != null) {
      _bgInterval = event['interval'] as int;
    }
  });

  // Sent by settings screen when user changes confirm mode or history settings
  service.on('updateSettings').listen((event) {
    if (event == null) return;
    if (event['confirmMode'] != null) {
      final newMode = event['confirmMode'] as String;
      if (newMode != _confirmMode && newMode != 'auto') {
        // Closing channel when switching away from auto (stop pushing)
        _wsChannel?.sink.close();
        _wsChannel = null;
      }
      _confirmMode = newMode;
    }
    if (event['historyGranularity'] != null) {
      _historyGranularitySeconds = event['historyGranularity'] as int;
      _lastHistorySave = null; // reset so next tick re-evaluates
    }
    if (event['historyRetention'] != null) {
      _historyRetentionHours = event['historyRetention'] as int;
    }
    if (event['bgInterval'] != null) {
      _bgInterval = event['bgInterval'] as int;
      // Restart iOS heartbeat with new interval
      if (Platform.isIOS && _iosHeartbeat != null) {
        _iosHeartbeat!.cancel();
        _iosHeartbeat = Timer.periodic(
          Duration(seconds: _bgInterval),
          (_) async {
            if (!_serviceRunning || _lastKnownPosition == null) return;
            final now = DateTime.now();
            if (_lastIosReport != null &&
                now.difference(_lastIosReport!).inSeconds < _bgInterval) {
              return;
            }
            _lastIosReport = now;
            await _trackAndReport(service);
          },
        );
      }
    }
    // Immediately push updated settings to bridge
    _pushSettingsToBridge(service);
  });

  // User approved a location request (ask mode)
  service.on('approveRequest').listen((event) {
    _pendingLocationRequest = true;
    // Trigger an immediate GPS send
    _trackAndReport(service);
  });

  _startMotionDetection();

  if (Platform.isIOS) {
    // iOS: use location stream to keep app alive in background.
    // Future.delayed timers get suspended by iOS when backgrounded,
    // but the location stream keeps the background session active
    // so a periodic timer can still fire as a heartbeat.
    _lastIosReport = DateTime.now();
    _iosLocationSub = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      ),
    ).listen((position) async {
      final now = DateTime.now();
      final interval = _useFgInterval ? kFgIntervalSeconds : _bgInterval;
      if (_lastIosReport != null &&
          now.difference(_lastIosReport!).inSeconds < interval) {
        return; // throttle to configured interval
      }
      _lastIosReport = now;
      _lastKnownPosition = position;
      _lastGpsTimestamp = _nowIso();
      _hasMovedSinceLastFix = true;
      await _trackAndReport(service);
    });

    // Heartbeat: when stationary, CoreLocation stops firing events.
    // This timer re-sends the last known position so bridge knows
    // the phone is still alive. Runs every bgInterval; if iOS defers
    // the timer, it catches up on the next CPU wake.
    _iosHeartbeat?.cancel();
    _iosHeartbeat = Timer.periodic(
      Duration(seconds: _bgInterval),
      (_) async {
        if (!_serviceRunning || _lastKnownPosition == null) return;
        final now = DateTime.now();
        if (_lastIosReport != null &&
            now.difference(_lastIosReport!).inSeconds < _bgInterval) {
          return; // location stream already reported recently
        }
        _lastIosReport = now;
        // Reuse last known position (no new GPS), still send to bridge
        await _trackAndReport(service);
      },
    );
  } else {
    // Android: use timer-based scheduling with foreground service
    await _trackAndReport(service);
    _scheduleNext(service);
  }
}

/// Returns the existing WebSocket channel, or creates a new one.
/// Returns null if relay URL or token are not configured.
Future<WebSocketChannel?> _getChannel(ServiceInstance service) async {
  if (_wsChannel != null) return _wsChannel;

  final prefs = await SharedPreferences.getInstance();
  final relayUrl = prefs.getString(kRelayUrlKey) ?? '';
  final token = prefs.getString(kTokenKey) ?? '';
  if (relayUrl.isEmpty || token.isEmpty) return null;

  final base = relayUrl.endsWith('/')
      ? relayUrl.substring(0, relayUrl.length - 1)
      : relayUrl;
  final wsUrl = '$base/ws/$token';
  _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

  // Listen for incoming messages from bridge
  _wsListenSub?.cancel();
  _wsListenSub = _wsChannel!.stream.listen(
    (message) {
      try {
        final data = jsonDecode(message as String);
        final type = data['type'] as String?;
        if (type == 'location_stored') {
          // Silent delivery confirmation — bridge received and stored data
          _lastConfirmedAt = _nowIso();
          _unconfirmedCount = 0;
          service.invoke('deliveryConfirmed', {
            'confirmedAt': _lastConfirmedAt,
          });
        } else if (type == 'location_accessed') {
          // OpenClaw actually queried the location — notify user
          _showLocalNotification('OpenClaw 已提取位置', '你的位置已被查詢');
        } else if (type == 'location_request') {
          _pendingLocationRequest = true;
          _showLocalNotification(
            'OpenClaw 想要提取你的位置',
            '打開 App 以接受或拒絕',
          );
          // Notify UI about the request
          service.invoke('locationRequest', {'pending': true});
        }
      } catch (_) {
        // Not a control message, ignore (could be encrypted GPS from another peer)
      }
    },
    onError: (_) {
      _wsChannel = null;
      _wsListenSub = null;
    },
    onDone: () {
      _wsChannel = null;
      _wsListenSub = null;
    },
  );

  // Push current settings to bridge on connect so it always has fresh state
  try {
    _wsChannel!.sink.add(jsonEncode({
      'type': 'settings_update',
      'confirm_mode': _confirmMode,
      'update_interval_seconds': _bgInterval,
      'history_granularity_seconds': _historyGranularitySeconds,
      'retention_hours': _historyRetentionHours,
    }));
  } catch (_) {}

  return _wsChannel;
}

/// Show a local notification to the user.
Future<void> _showLocalNotification(String title, String body) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.show(
    999, // notification ID for bridge messages
    title,
    body,
    NotificationDetails(
      iOS: const DarwinNotificationDetails(),
      android: AndroidNotificationDetails(
        _requestChannelId,
        'OpenClaw 通知',
        channelDescription: 'OpenClaw 位置請求通知',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

/// Push current settings to bridge via WebSocket (plaintext, no encryption needed).
/// Bridge uses this to know the phone's confirm mode without waiting for GPS data.
Future<void> _pushSettingsToBridge(ServiceInstance service) async {
  final channel = await _getChannel(service);
  if (channel == null) return;
  try {
    channel.sink.add(jsonEncode({
      'type': 'settings_update',
      'confirm_mode': _confirmMode,
      'update_interval_seconds': _bgInterval,
      'history_granularity_seconds': _historyGranularitySeconds,
      'retention_hours': _historyRetentionHours,
    }));
  } catch (_) {
    // Best-effort; will be sent again on next settings change or GPS tick
  }
}

/// Get a GPS fix with accuracy better than [thresholdMeters].
/// Retries up to [maxAttempts] times before accepting whatever it has.
Future<Position> _getAccuratePosition({
  double thresholdMeters = 50.0,
  int maxAttempts = 3,
}) async {
  Position? best;
  for (int i = 0; i < maxAttempts; i++) {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    if (best == null || pos.accuracy < best.accuracy) {
      best = pos;
    }
    if (best.accuracy <= thresholdMeters) break;
  }
  return best!;
}

Future<void> _trackAndReport(ServiceInstance service) async {
  // When stationary in background mode, skip GPS acquisition but reuse last known position
  final bool skipGps = !_useFgInterval && !_hasMovedSinceLastFix;
  if (skipGps && _lastKnownPosition == null) return; // no data yet, nothing to send
  _hasMovedSinceLastFix = false;

  try {
    final Position position;
    if (skipGps) {
      position = _lastKnownPosition!;
    } else {
      position = await _getAccuratePosition();
      _lastKnownPosition = position;
      _lastGpsTimestamp = _nowIso();
    }

    // timestamp = when GPS was actually acquired (not current time when stationary)
    final timestamp = _lastGpsTimestamp ?? _nowIso();
    final prefs = await SharedPreferences.getInstance();
    final serverPubKey = prefs.getString(kServerPubKeyKey) ?? '';

    String? sendError;
    if (_confirmMode == 'auto') {
      if (serverPubKey.isNotEmpty) {
        // Determine whether to save this reading as a history record
        bool saveHistory = false;
        if (_historyGranularitySeconds > 0) {
          final now = DateTime.now();
          if (_lastHistorySave == null ||
              now.difference(_lastHistorySave!).inSeconds >= _historyGranularitySeconds) {
            saveHistory = true;
            _lastHistorySave = now;
          }
        }

        try {
          final encrypted = await encryptGpsPayload(
            lat: position.latitude,
            lng: position.longitude,
            timestamp: timestamp,
            serverPubKeyB64: serverPubKey,
            extraFields: {
              'save_history': saveHistory,
              'retention_hours': _historyRetentionHours,
              'history_granularity_seconds': _historyGranularitySeconds,
              'update_interval_seconds': _bgInterval,
              'confirm_mode': _confirmMode,
            },
          );
          // Queue the payload; drop oldest if over limit
          _sendQueue.add(encrypted);
          if (_sendQueue.length > _kMaxQueueSize) {
            _sendQueue.removeAt(0);
          }

          final channel = await _getChannel(service);
          if (channel != null) {
            // Flush all queued payloads in order
            final batch = List<Map<String, String>>.from(_sendQueue);
            for (final item in batch) {
              channel.sink.add(jsonEncode(item));
            }
            _sendQueue.clear();
            _lastSentAt = _nowIso();
            _lastSendTime = DateTime.now();
            _unconfirmedCount++;
          } else {
            sendError = '未設定 Relay URL 或 Token（暫存 ${_sendQueue.length} 筆）';
          }
        } catch (e) {
          _wsChannel = null; // 重置，下次重新連線
          sendError = '傳送失敗，已暫存 ${_sendQueue.length} 筆';
        }
      } else {
        sendError = '未設定伺服器公鑰';
      }
    } else if (_confirmMode == 'ask') {
      if (_pendingLocationRequest && serverPubKey.isNotEmpty) {
        // User approved or request came in — send location once
        _pendingLocationRequest = false;
        try {
          final encrypted = await encryptGpsPayload(
            lat: position.latitude,
            lng: position.longitude,
            timestamp: timestamp,
            serverPubKeyB64: serverPubKey,
            extraFields: {
              'save_history': false,
              'retention_hours': _historyRetentionHours,
              'history_granularity_seconds': _historyGranularitySeconds,
              'update_interval_seconds': _bgInterval,
              'confirm_mode': _confirmMode,
            },
          );
          final channel = await _getChannel(service);
          if (channel != null) {
            channel.sink.add(jsonEncode(encrypted));
            _lastSentAt = _nowIso();
            _lastSendTime = DateTime.now();
            _unconfirmedCount++;
          } else {
            sendError = '未連線至 Relay';
          }
        } catch (e) {
          _wsChannel = null;
          sendError = '傳送失敗';
        }
      } else {
        sendError = '詢問模式：等待 OpenClaw 請求';
      }
    } else {
      // deny
      sendError = '拒絕模式：不傳送位置';
    }

    // Check if sends are going unconfirmed (bridge may not be running)
    final bool unconfirmed = _unconfirmedCount >= 3 &&
        _lastSendTime != null &&
        DateTime.now().difference(_lastSendTime!).inSeconds > 30;

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        final String notifTitle;
        final String notifContent;
        if (_confirmMode == 'ask') {
          notifTitle = 'GPS 定位中・等待確認';
          notifContent = '位置僅本機記錄，不主動傳送';
        } else if (_confirmMode == 'deny') {
          notifTitle = 'GPS 定位中・已暫停傳送';
          notifContent = '位置僅本機記錄，不主動傳送';
        } else {
          notifTitle = sendError == null
              ? (unconfirmed ? 'GPS 追蹤中・未確認送達' : 'GPS 追蹤中・自動傳送')
              : 'GPS 追蹤中・傳送中斷';
          notifContent =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
        service.setForegroundNotificationInfo(
          title: notifTitle,
          content: notifContent,
        );
      }
    }

    service.invoke('locationUpdate', {
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': timestamp,
      'postError': sendError,
      'sentAt': _lastSentAt,
      'confirmedAt': _lastConfirmedAt,
      'unconfirmed': unconfirmed,
      'success': true,
    });
  } catch (e) {
    service.invoke('locationUpdate', {
      'success': false,
      'error': e.toString(),
    });
  }
}
