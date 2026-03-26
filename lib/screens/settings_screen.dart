import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/background_service.dart';
import '../main.dart' show kDefaultRelayUrl, kRelayUrlListKey;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
  int _bgIntervalSeconds = kDefaultBgIntervalSeconds;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kRelayUrlListKey, _relayUrls);
    await prefs.setString(kRelayUrlKey, _selectedRelayUrl ?? '');
    await prefs.setString(kTokenKey, _tokenController.text.trim());
    await prefs.setString(kServerPubKeyKey, _pubKeyController.text.trim());
    await prefs.setInt(kBgIntervalKey, _bgIntervalSeconds);
  }

  Future<void> _showAddRelayDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增 Relay 伺服器'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'wss://example.com/relay',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('新增'),
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

  Future<void> _deleteRelayUrl(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除伺服器'),
        content: Text('確定要刪除？\n$url'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('刪除'),
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
    _tokenController.dispose();
    _pubKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Relay 伺服器
          _SectionHeader(title: 'Relay 伺服器', icon: Icons.cloud),
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
                      hint: const Text('尚未設定，請點 + 新增'),
                      items: _relayUrls.map((url) {
                        final isDefault = url == kDefaultRelayUrl;
                        return DropdownMenuItem<String>(
                          value: url,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isDefault ? '官方路由' : url,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!isDefault)
                                GestureDetector(
                                  onTap: () => _deleteRelayUrl(url),
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
                onPressed: _showAddRelayDialog,
                icon: const Icon(Icons.add),
                tooltip: '新增伺服器',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 更新間隔
          _SectionHeader(title: '更新間隔', icon: Icons.timer),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              helperText: '開啟 App 時固定每 5 秒更新',
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _bgIntervalSeconds,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 秒')),
                  DropdownMenuItem(value: 60, child: Text('1 分鐘（預設）')),
                  DropdownMenuItem(value: 120, child: Text('2 分鐘')),
                  DropdownMenuItem(value: 300, child: Text('5 分鐘')),
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

          // 配對設定
          _SectionHeader(title: '配對設定', icon: Icons.link),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: _tokenObscured,
            decoration: InputDecoration(
              labelText: 'Token（配對碼）',
              hintText: '由 OpenClaw 提供',
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
              labelText: '伺服器公鑰',
              hintText: '由 OpenClaw 提供（Base64）',
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

          // 教學
          _SectionHeader(title: '說明與教學', icon: Icons.school),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.menu_book),
            title: const Text('安裝與設定教學'),
            subtitle: const Text('如何搭配 OpenClaw 使用'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () async {
              final uri = Uri.parse(
                  'https://github.com/myasaliu/gps-bridge#readme');
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.code),
            title: const Text('開放原始碼'),
            subtitle: const Text('github.com/myasaliu/gps-bridge'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () async {
              final uri =
                  Uri.parse('https://github.com/myasaliu/gps-bridge');
              if (await canLaunchUrl(uri)) launchUrl(uri);
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
