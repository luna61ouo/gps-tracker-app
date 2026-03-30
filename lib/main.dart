import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'l10n/localizations.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/background_service.dart';

const String kRelayUrlListKey = 'relay_url_list';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const GpsTrackerApp());
}

// ---------------------------------------------------------------------------
// Root app — stateful so it can rebuild when language changes
// ---------------------------------------------------------------------------

class GpsTrackerApp extends StatefulWidget {
  const GpsTrackerApp({super.key});

  @override
  State<GpsTrackerApp> createState() => _GpsTrackerAppState();
}

class _GpsTrackerAppState extends State<GpsTrackerApp> {
  @override
  void initState() {
    super.initState();
    appLocale.addListener(_onLocaleChange);
    appTimezone.addListener(_onLocaleChange);
    _loadSavedLanguage();
    _loadSavedTimezone();
  }

  @override
  void dispose() {
    appLocale.removeListener(_onLocaleChange);
    appTimezone.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() => setState(() {});

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(kLanguageKey) ?? 'auto';
    appLocale.value = resolveStrings(lang);
  }

  Future<void> _loadSavedTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(kTimezoneOffsetKey) ?? kTimezoneAuto;
    appTimezone.value = stored == kTimezoneAuto ? null : stored;
  }

  @override
  Widget build(BuildContext context) {
    return AppL10n(
      strings: appLocale.value,
      child: MaterialApp(
        title: appLocale.value.appTitle,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const _AppEntry(),
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(kOnboardingCompleteKey) ?? false;
    if (mounted) setState(() => _onboardingComplete = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingComplete == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingComplete == false) {
      return OnboardingScreen(
        onComplete: () => setState(() => _onboardingComplete = true),
      );
    }
    return const TrackingHomePage();
  }
}

// ---------------------------------------------------------------------------
// Home page
// ---------------------------------------------------------------------------

class TrackingHomePage extends StatefulWidget {
  const TrackingHomePage({super.key});

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage>
    with WidgetsBindingObserver {
  bool _isTracking = false;
  double? _lastLat;
  double? _lastLng;
  String? _lastTimestamp;
  String? _lastError;
  String? _postError;
  StreamSubscription? _locationSub;
  List<_CheckWarning> _warnings = [];
  Timer? _watchdogTimer;
  String? _lastSentAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkServiceStatus();
    _listenToLocationUpdates();
    _listenToLocationRequests();
    _ensureDefaultRelay();
    _runSelfCheck();
    _startWatchdog();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSelfCheck();
    }
    if (!_isTracking) return;
    _notifyServiceInterval(foreground: state == AppLifecycleState.resumed);
  }

  Future<void> _notifyServiceInterval({required bool foreground}) async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt(kBgIntervalKey) ?? kDefaultBgIntervalSeconds;
    FlutterBackgroundService().invoke('setUpdateInterval', {
      'foreground': foreground,
      'interval': interval,
    });
  }

  Future<void> _ensureDefaultRelay() async {
    const oldUrl = 'wss://legacy-relay.example.com/relay';
    final prefs = await SharedPreferences.getInstance();
    var urls = prefs.getStringList(kRelayUrlListKey);

    if (urls == null) {
      await prefs.setStringList(kRelayUrlListKey, [kDefaultRelayUrl]);
      await prefs.setString(kRelayUrlKey, kDefaultRelayUrl);
    } else if (urls.contains(oldUrl)) {
      urls = urls.map((u) => u == oldUrl ? kDefaultRelayUrl : u).toList();
      await prefs.setStringList(kRelayUrlListKey, urls);
      final selected = prefs.getString(kRelayUrlKey);
      if (selected == oldUrl) {
        await prefs.setString(kRelayUrlKey, kDefaultRelayUrl);
      }
    }
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await FlutterBackgroundService().isRunning();
    if (mounted) setState(() => _isTracking = isRunning);
    if (!isRunning) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kTrackingEnabledKey) ?? false) {
        await FlutterBackgroundService().startService();
        if (mounted) setState(() => _isTracking = true);
      }
    }
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
          if (event['sentAt'] != null) {
            _lastSentAt = event['sentAt'] as String;
          }
        } else {
          _lastError = event['error'] as String?;
        }
      });
    });
  }

  void _listenToLocationRequests() {
    FlutterBackgroundService().on('locationRequest').listen((event) {
      if (event == null || !mounted) return;
      if (event['pending'] == true) {
        // Show a dialog asking the user to approve
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('OpenClaw 想要提取你的位置'),
            content: const Text('是否允許傳送目前位置？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('拒絕'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Tell the background service to send location
                  FlutterBackgroundService().invoke('approveRequest');
                },
                child: const Text('接受'),
              ),
            ],
          ),
        );
      }
    });
  }

  Future<void> _runSelfCheck() async {
    final s = AppL10n.of(context);
    final prefs = await SharedPreferences.getInstance();
    final List<_CheckWarning> warnings = [];

    final locPerm = await Geolocator.checkPermission();
    if (locPerm == LocationPermission.denied ||
        locPerm == LocationPermission.deniedForever ||
        locPerm == LocationPermission.unableToDetermine) {
      warnings.add(_CheckWarning(
        icon: Icons.location_off,
        color: Colors.red,
        message: s.warnNoLocationPerm,
        actionLabel: s.btnGoSettings,
        onAction: openAppSettings,
      ));
    } else if (locPerm == LocationPermission.whileInUse) {
      warnings.add(_CheckWarning(
        icon: Icons.location_on,
        color: Colors.orange,
        message: s.warnLocationWhileInUse,
        actionLabel: s.btnGoSettings,
        onAction: openAppSettings,
      ));
    }
    // locPerm == LocationPermission.always → no warning

    final pubKey = prefs.getString(kServerPubKeyKey) ?? '';
    if (pubKey.isEmpty) {
      warnings.add(_CheckWarning(
        icon: Icons.vpn_key_off,
        color: Colors.orange,
        message: s.warnNoPubKey,
        actionLabel: s.btnGoSettings,
        onAction: _goToSettings,
      ));
    }

    final relayUrl = prefs.getString(kRelayUrlKey) ?? '';
    if (relayUrl.isEmpty) {
      warnings.add(_CheckWarning(
        icon: Icons.cloud_off,
        color: Colors.orange,
        message: s.warnNoRelay,
        actionLabel: s.btnGoSettings,
        onAction: _goToSettings,
      ));
    }

    final token = prefs.getString(kTokenKey) ?? '';
    if (token.isEmpty) {
      warnings.add(_CheckWarning(
        icon: Icons.key_off,
        color: Colors.orange,
        message: s.warnNoToken,
        actionLabel: s.btnGoSettings,
        onAction: _goToSettings,
      ));
    }

    if (mounted) setState(() => _warnings = warnings);
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final prefs = await SharedPreferences.getInstance();
      final shouldTrack = prefs.getBool(kTrackingEnabledKey) ?? false;
      if (!shouldTrack) return;
      final isRunning = await FlutterBackgroundService().isRunning();
      if (!isRunning && mounted) {
        await FlutterBackgroundService().startService();
        setState(() => _isTracking = true);
      }
    });
  }

  Future<void> _goToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _runSelfCheck();
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
    final s = AppL10n.of(context);
    final service = FlutterBackgroundService();
    if (_isTracking) {
      service.invoke('stopService');
      setState(() => _isTracking = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kTrackingEnabledKey, false);
      return;
    }
    // Check pairing info before starting
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(kTokenKey) ?? '';
    final pubKey = prefs.getString(kServerPubKeyKey) ?? '';
    if (token.isEmpty || pubKey.isEmpty) {
      if (mounted) {
        final missing = <String>[];
        if (token.isEmpty) missing.add(s.labelToken);
        if (pubKey.isEmpty) missing.add(s.labelPubKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.warnMissingPairing}${missing.join("、")}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: s.btnGoSettings,
              onPressed: _goToSettings,
            ),
          ),
        );
      }
      return;
    }
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.warnNeedBgPerm),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    await prefs.setBool(kTrackingEnabledKey, true);
    await service.startService();
    setState(() => _isTracking = true);
  }

  void _showHelpDialog() {
    final s = AppL10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Text(s.helpTitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.helpIntro,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Text(s.helpHowTitle),
              const SizedBox(height: 6),
              Text(s.helpHow1),
              Text(s.helpHow2),
              Text(s.helpHow3),
              Text(s.helpHow4),
              const SizedBox(height: 12),
              Text(s.helpModeTitle),
              const SizedBox(height: 6),
              Text(s.helpModeAuto),
              Text(s.helpModeAsk),
              Text(s.helpModeDeny),
              const SizedBox(height: 12),
              Text(s.helpHistoryTitle),
              const SizedBox(height: 6),
              Text(s.helpHistoryDesc),
              const SizedBox(height: 12),
              Text(s.helpSetupTitle),
              const SizedBox(height: 6),
              Text(s.helpSetupDesc),
              const SizedBox(height: 12),
              Text(
                s.helpPrivacy,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnGotIt),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.satellite_alt, size: 20),
            const SizedBox(width: 8),
            Text(s.appTitle),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: s.tooltipSettings,
            onPressed: _goToSettings,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: s.tooltipHelp,
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 追蹤按鈕永遠置中於整個 body
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TrackingButton(
                  isTracking: _isTracking,
                  onTap: _toggleTracking,
                ),
                const SizedBox(height: 20),
                Text(
                  s.btnSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),

          // 狀態列與警告固定於頂部，展開不影響按鈕位置
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GpsStatusTile(
                  isTracking: _isTracking,
                  lat: _lastLat,
                  lng: _lastLng,
                  timestamp: _lastTimestamp,
                  gpsError: _lastError,
                  postError: _postError,
                  sentAt: _lastSentAt,
                ),

                if (_warnings.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Column(
                      children: [
                        for (final w in _warnings)
                          Card(
                            color: w.color.withValues(alpha: 0.08),
                            margin: const EdgeInsets.only(bottom: 4),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: w.color.withValues(alpha: 0.3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(w.icon, color: w.color, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      w.message,
                                      style: TextStyle(
                                          fontSize: 12, color: w.color),
                                    ),
                                  ),
                                  if (w.actionLabel != null &&
                                      w.onAction != null)
                                    TextButton(
                                      onPressed: w.onAction,
                                      style: TextButton.styleFrom(
                                        foregroundColor: w.color,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(w.actionLabel!,
                                          style:
                                              const TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GPS 狀態卡片
// ---------------------------------------------------------------------------

class _GpsStatusTile extends StatelessWidget {
  const _GpsStatusTile({
    required this.isTracking,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.gpsError,
    required this.postError,
    required this.sentAt,
  });

  final bool isTracking;
  final double? lat;
  final double? lng;
  final String? timestamp;
  final String? gpsError;
  final String? postError;
  final String? sentAt;

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
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
          isTracking ? s.statusTracking : s.statusStopped,
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
            : Text(s.statusNoData, style: const TextStyle(fontSize: 12)),
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
                      label: s.labelGpsError,
                      value: gpsError!)
                else if (lat != null && lng != null) ...[
                  _InfoRow(
                      icon: Icons.my_location,
                      label: s.labelLat,
                      value: lat!.toStringAsFixed(6)),
                  const SizedBox(height: 4),
                  _InfoRow(
                      icon: Icons.my_location,
                      label: s.labelLng,
                      value: lng!.toStringAsFixed(6)),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                        icon: Icons.access_time,
                        label: s.labelGpsRecord,
                        value: _formatTime(timestamp)),
                  ],
                  const SizedBox(height: 4),
                  _InfoRow(
                      icon: Icons.cloud_upload,
                      iconColor: sentAt != null ? Colors.blue : Colors.grey,
                      label: s.labelSentAt,
                      value: _formatTime(sentAt)),
                  const SizedBox(height: 4),
                  if (postError != null)
                    _InfoRow(
                        icon: Icons.cloud_off,
                        iconColor: Colors.orange,
                        label: s.labelSendStatus,
                        value: postError!),
                ] else
                  Text(s.statusNoDataHint,
                      style: const TextStyle(color: Colors.grey)),
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
    final s = AppL10n.of(context);
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
              isTracking ? s.btnStop : s.btnStart,
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
// 時間格式化
// ---------------------------------------------------------------------------

/// 將 UTC ISO-8601 字串轉為本地時區的 "MM/DD HH:mm (原始時間)" 格式。
String _formatTime(String? isoUtc) {
  if (isoUtc == null || isoUtc.isEmpty) return '—';
  try {
    final utc = DateTime.parse(isoUtc).toUtc();
    final offset = appTimezone.value;
    final dt = offset == null ? utc.toLocal() : utc.add(Duration(minutes: offset));
    final display =
        '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$display ($isoUtc)';
  } catch (_) {
    return isoUtc;
  }
}

// ---------------------------------------------------------------------------
// 自檢警告資料模型
// ---------------------------------------------------------------------------

class _CheckWarning {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CheckWarning({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
}

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
        Text('$label：',
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13)),
        Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
