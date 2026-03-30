import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../l10n/app_strings.dart';
import '../l10n/localizations.dart';
import '../services/background_service.dart';
import '../main.dart' show kRelayUrlListKey;
import 'onboarding_screen.dart' show kOnboardingCompleteKey;

class SettingsScreen extends StatefulWidget {
  final bool showInstallGuide;

  const SettingsScreen({super.key, this.showInstallGuide = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _relayUrls = [];
  String? _selectedRelayUrl;
  final _tokenController = TextEditingController();
  final _pubKeyController = TextEditingController();
  bool _tokenObscured = true;
  bool _pubKeyObscured = true;

  String _confirmMode = kDefaultConfirmMode;
  int _bgIntervalSeconds = kDefaultBgIntervalSeconds;
  int _historyGranularitySeconds = kDefaultHistoryGranularitySeconds;
  int _historyRetentionHours = kDefaultHistoryRetentionHours;
  bool _batteryOptDisabled = false;
  int? _timezoneOffsetMinutes; // null = auto
  String _language = 'auto';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.showInstallGuide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final s = AppL10n.of(context);
          _showInstallBridgeDialog(context, s);
        }
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    var urls = prefs.getStringList(kRelayUrlListKey);
    if (urls == null) {
      urls = [kDefaultRelayUrl];
      await prefs.setStringList(kRelayUrlListKey, urls);
    }
    final selected = prefs.getString(kRelayUrlKey) ?? '';
    setState(() {
      _relayUrls = urls!;
      _selectedRelayUrl =
          urls.contains(selected) ? selected : (urls.isNotEmpty ? urls.first : null);
      _tokenController.text = prefs.getString(kTokenKey) ?? '';
      _pubKeyController.text = prefs.getString(kServerPubKeyKey) ?? '';
      _bgIntervalSeconds = prefs.getInt(kBgIntervalKey) ?? kDefaultBgIntervalSeconds;
      _confirmMode = prefs.getString(kConfirmModeKey) ?? kDefaultConfirmMode;
      _historyGranularitySeconds =
          prefs.getInt(kHistoryGranularityKey) ?? kDefaultHistoryGranularitySeconds;
      _historyRetentionHours =
          prefs.getInt(kHistoryRetentionKey) ?? kDefaultHistoryRetentionHours;
      _language = prefs.getString(kLanguageKey) ?? 'auto';
      final tzStored = prefs.getInt(kTimezoneOffsetKey) ?? kTimezoneAuto;
      _timezoneOffsetMinutes = tzStored == kTimezoneAuto ? null : tzStored;
    });
    if (Platform.isAndroid) {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (mounted) setState(() => _batteryOptDisabled = batteryStatus.isGranted);
    }
  }

  Future<void> _requestBatteryOptExemption() async {
    if (!Platform.isAndroid) return;
    await Permission.ignoreBatteryOptimizations.request();
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (mounted) setState(() => _batteryOptDisabled = status.isGranted);
  }

  List<DropdownMenuItem<int?>> _buildTimezoneItems(AppStrings s) {
    const offsets = <int?>[
      null,
      -720, -660, -600, -540, -480, -420, -360, -300, -240, -180, -120, -60,
      0, 60, 120, 180, 210, 240, 270, 300, 330, 345, 360, 390, 420,
      480, 540, 570, 600, 630, 660, 720, 780, 840,
    ];
    return offsets.map((m) {
      final label = m == null ? s.timezoneAuto : _tzLabel(m);
      return DropdownMenuItem<int?>(value: m, child: Text(label));
    }).toList();
  }

  static const _kTzRegions = <int, String>{
    -720: 'Baker Island',
    -660: 'Samoa, Niue',
    -600: 'Hawaii',
    -540: 'Alaska',
    -480: 'Los Angeles, Vancouver',
    -420: 'Denver, Phoenix',
    -360: 'Chicago, Mexico City',
    -300: 'New York, Toronto',
    -240: 'Halifax, Caracas',
    -180: 'Buenos Aires, São Paulo',
    -120: 'South Georgia',
    -60: 'Azores',
    0: 'London, Dublin, Lisbon',
    60: 'Paris, Berlin, Rome',
    120: 'Cairo, Athens, Johannesburg',
    180: 'Moscow, Riyadh, Istanbul',
    210: 'Tehran',
    240: 'Dubai, Baku',
    270: 'Kabul',
    300: 'Karachi, Tashkent',
    330: 'Mumbai, New Delhi',
    345: 'Kathmandu',
    360: 'Dhaka, Almaty',
    390: 'Yangon',
    420: 'Bangkok, Jakarta, Hanoi',
    480: 'Taipei, Beijing, Singapore, HK',
    540: 'Tokyo, Seoul',
    570: 'Adelaide',
    600: 'Sydney, Melbourne',
    630: 'Lord Howe Island',
    660: 'Solomon Islands',
    720: 'Auckland, Fiji',
    780: 'Tonga',
    840: 'Kiribati',
  };

  String _tzLabel(int minutes) {
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    final sign = minutes >= 0 ? '+' : '-';
    final utc = m == 0 ? 'UTC$sign$h' : 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
    final region = _kTzRegions[minutes];
    return region != null ? '$utc  –  $region' : utc;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kRelayUrlListKey, _relayUrls);
    await prefs.setString(kRelayUrlKey, _selectedRelayUrl ?? '');
    await prefs.setString(kTokenKey, _tokenController.text.trim());
    await prefs.setString(kServerPubKeyKey, _pubKeyController.text.trim());
    await prefs.setInt(kBgIntervalKey, _bgIntervalSeconds);
    await prefs.setString(kConfirmModeKey, _confirmMode);
    await prefs.setInt(kHistoryGranularityKey, _historyGranularitySeconds);
    await prefs.setInt(kHistoryRetentionKey, _historyRetentionHours);

    final isRunning = await FlutterBackgroundService().isRunning();
    if (isRunning) {
      FlutterBackgroundService().invoke('updateSettings', {
        'confirmMode': _confirmMode,
        'historyGranularity': _historyGranularitySeconds,
        'historyRetention': _historyRetentionHours,
        'bgInterval': _bgIntervalSeconds,
      });
    }
    _showSavedHint();
  }

  Timer? _savedHintTimer;

  void _showSavedHint() {
    _savedHintTimer?.cancel();
    _savedHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已儲存，設定立即生效'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  Future<void> _showAddRelayDialog(AppStrings s) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.relayAddTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.relayAddHint,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(s.btnAdd),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty && !_relayUrls.contains(url)) {
      setState(() {
        _relayUrls.add(url);
        _selectedRelayUrl = url;
      });
      await _saveSettings();
    }
  }

  Future<void> _deleteRelayUrl(String url, AppStrings s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.relayDeleteTitle),
        content: Text(s.relayDeleteConfirm(url)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _relayUrls.remove(url);
        if (_selectedRelayUrl == url) {
          _selectedRelayUrl = _relayUrls.isNotEmpty ? _relayUrls.first : null;
        }
      });
      await _saveSettings();
    }
  }

  @override
  void dispose() {
    _savedHintTimer?.cancel();
    _tokenController.dispose();
    _pubKeyController.dispose();
    super.dispose();
  }

  void _showInstallBridgeDialog(BuildContext context, AppStrings s) {
    final copyText =
        'Please install GPS Bridge to receive encrypted GPS coordinates from my phone.\n\n'
        'pip install gps-bridge\n\n'
        'After installation, help me set up GPS tracking (generate keypair and pairing token).\n\n'
        'Project info: https://github.com/luna61ouo/gps-bridge';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.installBridgeDialogTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.installBridgeDialogBody),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.btnCancel),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.content_copy, size: 18),
            label: Text(s.btnCopy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyText));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(s.installBridgeCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showPairingHelp(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.pairingHelpTitle),
        content: SingleChildScrollView(
          child: Text(s.pairingHelpBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _confirmModeHelperText(AppStrings s) {
    switch (_confirmMode) {
      case 'ask':
        return s.confirmHintAsk;
      case 'deny':
        return s.confirmHintDeny;
      default:
        return s.confirmHintAuto;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 中繼資料轉送伺服器 ───────────────────────────────────────────────
          Row(
            children: [
              _SectionHeader(title: s.sectionRelay, icon: Icons.cloud),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Row(
                      children: [
                        const Icon(Icons.cloud, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(s.relayInfoTitle),
                      ],
                    ),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.relayInfoWhatTitle,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(s.relayInfoWhatBody),
                          const SizedBox(height: 12),
                          Text(s.relayInfoSecurityTitle,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(s.relayInfoSecurityBody),
                          const SizedBox(height: 12),
                          Text(s.relayInfoSelfHostTitle,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(s.relayInfoSelfHostBody),
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
                ),
                child: const Icon(Icons.help_outline,
                    size: 16, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRelayUrl,
                      isExpanded: true,
                      hint: Text(s.relayDropdownHint),
                      items: _relayUrls.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final url = entry.value;
                        final isDefault = idx == 0; // first entry is always the default
                        return DropdownMenuItem<String>(
                          value: url,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isDefault ? s.relayOfficialLabel : url,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!isDefault)
                                GestureDetector(
                                  onTap: () => _deleteRelayUrl(url, s),
                                  child: const Icon(Icons.close,
                                      size: 16, color: Colors.grey),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedRelayUrl = val);
                        _saveSettings();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _showAddRelayDialog(s),
                icon: const Icon(Icons.add),
                tooltip: s.relayAddTitle,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── 提取確認方式 ───────────────────────────────────────────────────
          _SectionHeader(title: s.sectionConfirmMode, icon: Icons.verified_user),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              helperText: _confirmModeHelperText(s),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _confirmMode,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'auto', child: Text(s.confirmModeAuto)),
                  DropdownMenuItem(value: 'ask', child: Text(s.confirmModeAsk)),
                  DropdownMenuItem(value: 'deny', child: Text(s.confirmModeDeny)),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _confirmMode = val);
                  _saveSettings();
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 更新間隔 ───────────────────────────────────────────────────────
          _SectionHeader(title: s.sectionInterval, icon: Icons.timer),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              helperText: s.intervalFgNote,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _bgIntervalSeconds,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 30, child: Text(s.intervalSec(30))),
                  DropdownMenuItem(value: 60, child: Text(s.withDefault(s.intervalMin(1)))),
                  DropdownMenuItem(value: 120, child: Text(s.intervalMin(2))),
                  DropdownMenuItem(value: 300, child: Text(s.intervalMin(5))),
                  DropdownMenuItem(value: 600, child: Text(s.intervalMin(10))),
                  DropdownMenuItem(value: 900, child: Text(s.intervalMin(15))),
                  DropdownMenuItem(value: 1800, child: Text(s.intervalMin(30))),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _bgIntervalSeconds = val);
                  _saveSettings();
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 歷史追蹤 ───────────────────────────────────────────────────────
          _SectionHeader(title: s.sectionHistory, icon: Icons.history),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              s.historyNote,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              labelText: s.historyGranularityLabel,
              helperText: s.historyGranularityHint,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _historyGranularitySeconds,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 0, child: Text(s.historyNoSave)),
                  DropdownMenuItem(value: 60, child: Text(s.intervalMin(1))),
                  DropdownMenuItem(value: 300, child: Text(s.intervalMin(5))),
                  DropdownMenuItem(value: 600, child: Text(s.withDefault(s.intervalMin(10)))),
                  DropdownMenuItem(value: 900, child: Text(s.intervalMin(15))),
                  DropdownMenuItem(value: 1800, child: Text(s.intervalMin(30))),
                  DropdownMenuItem(value: 3600, child: Text(s.intervalHour(1))),
                  DropdownMenuItem(value: 7200, child: Text(s.intervalHour(2))),
                  DropdownMenuItem(value: 10800, child: Text(s.intervalHour(3))),
                  DropdownMenuItem(value: 21600, child: Text(s.intervalHour(6))),
                  DropdownMenuItem(value: 28800, child: Text(s.intervalHour(8))),
                  DropdownMenuItem(value: 43200, child: Text(s.intervalHour(12))),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _historyGranularitySeconds = val);
                  _saveSettings();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              labelText: s.historyRetentionLabel,
              helperText: s.historyRetentionHint,
              enabled: _historyGranularitySeconds > 0,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _historyRetentionHours,
                isExpanded: true,
                disabledHint: const Text('—'),
                onChanged: _historyGranularitySeconds > 0
                    ? (val) {
                        if (val == null) return;
                        setState(() => _historyRetentionHours = val);
                        _saveSettings();
                      }
                    : null,
                items: [
                  DropdownMenuItem(value: 6, child: Text(s.retentionHour(6))),
                  DropdownMenuItem(value: 12, child: Text(s.retentionHour(12))),
                  DropdownMenuItem(value: 24, child: Text(s.retentionDay(1))),
                  DropdownMenuItem(value: 72, child: Text(s.retentionDay(3))),
                  DropdownMenuItem(value: 168, child: Text(s.withDefault(s.retentionWeek(1)))),
                  DropdownMenuItem(value: 336, child: Text(s.retentionWeek(2))),
                  DropdownMenuItem(value: 720, child: Text(s.retentionMonth(1))),
                  DropdownMenuItem(value: -1, child: Text(s.retentionUnlimited)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 安裝 Bridge ──────────────────────────────────────────────────
          _SectionHeader(title: s.sectionInstallBridge, icon: Icons.computer),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.blue),
              title: Text(s.installBridgeTitle),
              subtitle: Text(s.installBridgeSubtitle),
              onTap: () => _showInstallBridgeDialog(context, s),
            ),
          ),
          const SizedBox(height: 24),

          // ── 配對設定 ───────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _SectionHeader(title: s.sectionPairing, icon: Icons.link)),
              IconButton(
                icon: const Icon(Icons.help_outline, size: 20),
                tooltip: s.pairingHelpTitle,
                onPressed: () => _showPairingHelp(context, s),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: _tokenObscured,
            decoration: InputDecoration(
              labelText: s.labelToken,
              hintText: s.labelTokenHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key),
              suffixIcon: IconButton(
                icon: Icon(
                    _tokenObscured ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _tokenObscured = !_tokenObscured),
              ),
            ),
            onChanged: (_) => _saveSettings(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pubKeyController,
            obscureText: _pubKeyObscured,
            decoration: InputDecoration(
              labelText: s.labelPubKey,
              hintText: s.labelPubKeyHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                    _pubKeyObscured ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _pubKeyObscured = !_pubKeyObscured),
              ),
            ),
            onChanged: (_) => _saveSettings(),
          ),
          const SizedBox(height: 32),

          // ── 進階設定（Android only）────────────────────────────────────────
          if (Platform.isAndroid) ...[
            _SectionHeader(title: s.sectionAdvanced, icon: Icons.tune),
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              leading: Icon(
                Icons.battery_charging_full,
                color: _batteryOptDisabled ? Colors.green : Colors.grey,
              ),
              title: Text(s.batteryModeTitle),
              subtitle: Text(
                _batteryOptDisabled
                    ? s.batteryModeOnDesc
                    : s.batteryModeOffDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: _batteryOptDisabled ? Colors.green : Colors.grey,
                ),
              ),
              trailing: _batteryOptDisabled
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.chevron_right),
              onTap: _batteryOptDisabled ? null : _requestBatteryOptExemption,
            ),
            const SizedBox(height: 24),
          ],

          // ── 顯示時區 ────────────────────────────────────────────────────────
          _SectionHeader(title: s.sectionTimezone, icon: Icons.schedule),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _timezoneOffsetMinutes,
                isExpanded: true,
                items: _buildTimezoneItems(s),
                onChanged: (val) async {
                  setState(() => _timezoneOffsetMinutes = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt(kTimezoneOffsetKey, val ?? kTimezoneAuto);
                  appTimezone.value = val;
                },
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── 語言 ───────────────────────────────────────────────────────────
          _SectionHeader(title: s.sectionLanguage, icon: Icons.language),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _language,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'auto', child: Text(s.langAuto)),
                  DropdownMenuItem(value: 'zh', child: Text(s.langZh)),
                  DropdownMenuItem(value: 'en', child: Text(s.langEn)),
                ],
                onChanged: (val) async {
                  if (val == null) return;
                  setState(() => _language = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(kLanguageKey, val);
                  appLocale.value = resolveStrings(val);
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── 說明與教學 ─────────────────────────────────────────────────────
          _SectionHeader(title: s.sectionGuide, icon: Icons.school),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.menu_book),
            title: Text(s.guideTutorialTitle),
            subtitle: Text(s.guideTutorialSubtitle),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(s.guideTutorialTitle),
                  content: SingleChildScrollView(
                    child: Text(s.guideTutorialBody),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(s.btnGotIt),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.code),
            title: Text(s.guideBridgeTitle),
            subtitle: Text(s.guideBridgeSubtitle),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () async {
              final uri = Uri.parse(kGithubBridgeUrl);
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.router),
            title: Text(s.guideRelayTitle),
            subtitle: Text(s.guideRelaySubtitle),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () async {
              final uri = Uri.parse(kGithubRelayUrl);
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.replay),
            title: Text(s.guideReplayTitle),
            subtitle: Text(s.guideReplaySubtitle),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(kOnboardingCompleteKey, false);
              if (!mounted) return;
              // Pop with result to tell _AppEntry to recheck onboarding
              Navigator.of(context).pop('replay_onboarding');
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
