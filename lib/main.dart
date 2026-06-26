import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'l10n/app_strings.dart';
import 'l10n/localizations.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/background_service.dart';
import 'services/lock_password.dart';

const String kRelayUrlListKey = 'relay_url_list';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();

  // If tracking was enabled before app was killed (e.g. iOS terminated it),
  // restart the background service immediately so it resumes on relaunch.
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kTrackingEnabledKey) ?? false) {
    final running = await FlutterBackgroundService().isRunning();
    if (!running) {
      await FlutterBackgroundService().startService();
    }
  }

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
  bool _showGuide = false;

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
        onComplete: () => setState(() {
          _onboardingComplete = true;
          _showGuide = true;
        }),
      );
    }
    return TrackingHomePage(
      showSetupGuide: _showGuide,
      onGuideComplete: () => setState(() => _showGuide = false),
    );
  }
}

// ---------------------------------------------------------------------------
// Home page
// ---------------------------------------------------------------------------

class TrackingHomePage extends StatefulWidget {
  final bool showSetupGuide;
  final VoidCallback? onGuideComplete;

  const TrackingHomePage({
    super.key,
    this.showSetupGuide = false,
    this.onGuideComplete,
  });

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage>
    with WidgetsBindingObserver {
  bool _showingGuide = false;
  bool _locked = true;
  String? _lockPasswordHash;
  bool _isTracking = false;
  double? _lastLat;
  double? _lastLng;
  String? _lastTimestamp;
  String? _lastError;
  String? _postError;
  StreamSubscription? _locationSub;
  StreamSubscription? _confirmSub;
  List<_CheckWarning> _warnings = [];
  Timer? _watchdogTimer;
  String? _lastSentAt;
  String? _lastConfirmedAt;
  bool _unconfirmed = false;

  @override
  void initState() {
    super.initState();
    _showingGuide = widget.showSetupGuide;
    if (_showingGuide) _locked = false;
    WidgetsBinding.instance.addObserver(this);
    _checkServiceStatus();
    _listenToLocationUpdates();
    _listenToLocationRequests();
    _ensureDefaultRelay();
    _runSelfCheck();
    _startWatchdog();
    _loadLockPasswordHash();
  }

  Future<void> _loadLockPasswordHash() async {
    final hash = await getLockPasswordHash();
    if (mounted) setState(() => _lockPasswordHash = hash);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSelfCheck();
      _loadLockPasswordHash();
      if (mounted && !_locked) setState(() => _locked = true);
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
          if (event['confirmedAt'] != null) {
            _lastConfirmedAt = event['confirmedAt'] as String;
          }
          _unconfirmed = event['unconfirmed'] == true;
        } else {
          _lastError = event['error'] as String?;
        }
      });
    });

    _confirmSub =
        FlutterBackgroundService().on('deliveryConfirmed').listen((event) {
      if (event == null || !mounted) return;
      setState(() {
        _lastConfirmedAt = event['confirmedAt'] as String?;
        _unconfirmed = false;
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

  Future<void> _goToSettings({bool showInstallGuide = false}) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(showInstallGuide: showInstallGuide),
      ),
    );
    if (result == 'replay_onboarding') {
      // Trigger _AppEntry to recheck onboarding state
      if (mounted && context.findAncestorStateOfType<_AppEntryState>() != null) {
        context.findAncestorStateOfType<_AppEntryState>()!._checkOnboarding();
      }
      return;
    }
    _checkServiceStatus();
    _runSelfCheck();
    _loadLockPasswordHash();
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
    // App is in foreground — tell service to use 5s interval.
    // Small delay to let the service initialize and register listeners.
    Future.delayed(const Duration(seconds: 1), () {
      _notifyServiceInterval(foreground: true);
    });
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
    _confirmSub?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  void _handleGuideSettingsTap() {
    setState(() => _showingGuide = false);
    widget.onGuideComplete?.call();
    _goToSettings(showInstallGuide: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
    return Stack(
      children: [
        Scaffold(
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
                icon: Icon(
                  Icons.settings,
                  color: _showingGuide ? Colors.yellow : null,
                ),
                tooltip: s.tooltipSettings,
                onPressed: _showingGuide
                    ? _handleGuideSettingsTap
                    : _goToSettings,
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: s.tooltipHelp,
                onPressed: _showingGuide ? null : _showHelpDialog,
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
                  confirmedAt: _lastConfirmedAt,
                  unconfirmed: _unconfirmed,
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
    ),
    // Setup guide overlay
    if (_showingGuide)
      GestureDetector(
        onTap: _handleGuideSettingsTap,
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: SafeArea(
            child: Column(
              children: [
                // Arrow pointing to settings gear
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.arrow_upward, color: Colors.yellow, size: 32),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.yellow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '點這裡開始設定\nTap here to start setup',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    // Lock overlay (always on top — sits above settings/help icons too)
    if (_locked)
      _LockOverlay(
        passwordHash: _lockPasswordHash,
        onUnlock: () => setState(() => _locked = false),
      ),
    ],
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
    required this.confirmedAt,
    required this.unconfirmed,
  });

  final bool isTracking;
  final double? lat;
  final double? lng;
  final String? timestamp;
  final String? gpsError;
  final String? postError;
  final String? sentAt;
  final String? confirmedAt;
  final bool unconfirmed;

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
            color: !isTracking
                ? Colors.grey
                : unconfirmed
                    ? Colors.orange
                    : Colors.green,
            boxShadow: isTracking
                ? [
                    BoxShadow(
                      color: (unconfirmed ? Colors.orange : Colors.green)
                          .withValues(alpha: 0.4),
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
            color: !isTracking
                ? Colors.grey
                : unconfirmed
                    ? Colors.orange
                    : Colors.green,
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
                  if (confirmedAt != null) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                        icon: Icons.check_circle_outline,
                        iconColor: Colors.green,
                        label: s.labelConfirmedAt,
                        value: _formatTime(confirmedAt)),
                  ],
                  if (unconfirmed) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                        icon: Icons.warning_amber_rounded,
                        iconColor: Colors.orange,
                        label: s.labelSendStatus,
                        value: s.labelUnconfirmed),
                  ],
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
// 螢幕鎖定 overlay（滑桿解鎖）
// ---------------------------------------------------------------------------

class _LockOverlay extends StatefulWidget {
  const _LockOverlay({required this.onUnlock, required this.passwordHash});

  final VoidCallback onUnlock;
  final String? passwordHash;

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  final _pwCtrl = TextEditingController();
  bool _wrong = false;
  bool _verifying = false;

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    final ok = await verifyLockPassword(_pwCtrl.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlock();
    } else {
      setState(() {
        _wrong = true;
        _verifying = false;
        _pwCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
    final hasPassword = widget.passwordHash != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              children: [
                const Spacer(),
                const Icon(Icons.lock_outline, color: Colors.white, size: 56),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    hasPassword ? s.lockPasswordPrompt : s.lockHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: hasPassword
                      ? _buildPasswordInput(s)
                      : _SlideToUnlock(
                          label: s.lockSlideToUnlock,
                          onUnlock: widget.onUnlock,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordInput(AppStrings s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _pwCtrl,
          obscureText: true,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitPassword(),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: s.lockPasswordHint,
            hintStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            errorText: _wrong ? s.lockPasswordWrong : null,
            errorStyle: const TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
          onChanged: (_) {
            if (_wrong) setState(() => _wrong = false);
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _verifying ? null : _submitPassword,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.lock_open, color: Colors.white),
          label: Text(
            s.lockUnlockBtn,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

class _SlideToUnlock extends StatefulWidget {
  const _SlideToUnlock({required this.label, required this.onUnlock});

  final String label;
  final VoidCallback onUnlock;

  @override
  State<_SlideToUnlock> createState() => _SlideToUnlockState();
}

class _SlideToUnlockState extends State<_SlideToUnlock> {
  static const double _handleSize = 56;
  static const double _padding = 4;
  double _dragX = 0;
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - _handleSize - _padding * 2;
        final progress =
            maxDrag > 0 ? (_dragX / maxDrag).clamp(0.0, 1.0) : 0.0;
        return Container(
          height: _handleSize + _padding * 2,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius:
                BorderRadius.circular((_handleSize + _padding * 2) / 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: (1 - progress).clamp(0.0, 1.0),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _padding + _dragX,
                top: _padding,
                child: GestureDetector(
                  onHorizontalDragUpdate: _unlocked
                      ? null
                      : (d) {
                          setState(() {
                            _dragX =
                                (_dragX + d.delta.dx).clamp(0, maxDrag);
                          });
                        },
                  onHorizontalDragEnd: _unlocked
                      ? null
                      : (_) {
                          if (_dragX >= maxDrag * 0.9) {
                            setState(() {
                              _dragX = maxDrag;
                              _unlocked = true;
                            });
                            widget.onUnlock();
                          } else {
                            setState(() => _dragX = 0);
                          }
                        },
                  child: Container(
                    width: _handleSize,
                    height: _handleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.45),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
