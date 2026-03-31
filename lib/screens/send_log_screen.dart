import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/localizations.dart';
import '../services/background_service.dart';

class SendLogScreen extends StatefulWidget {
  const SendLogScreen({super.key});

  @override
  State<SendLogScreen> createState() => _SendLogScreenState();
}

class _SendLogScreenState extends State<SendLogScreen> {
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(kSendLogKey) ?? [];
    final parsed = list
        .map((e) {
          try {
            return jsonDecode(e) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    if (mounted) setState(() => _entries = parsed);
  }

  Future<void> _clear() async {
    final s = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.sendLogClear),
        content: Text(s.sendLogClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kSendLogKey);
      if (mounted) setState(() => _entries = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.sendLogTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: s.sendLogClear,
              onPressed: _clear,
            ),
        ],
      ),
      body: _entries.isEmpty
          ? Center(
              child: Text(
                s.sendLogEmpty,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final e = _entries[index];
                return _SendLogTile(entry: e);
              },
            ),
    );
  }
}

class _SendLogTile extends StatelessWidget {
  const _SendLogTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final s = AppL10n.of(context);
    final status = entry['status'] as String? ?? '';
    final time = entry['time'] as String? ?? '';
    final lat = entry['lat'] as num?;
    final lng = entry['lng'] as num?;
    final error = entry['error'] as String?;

    final IconData icon;
    final Color color;
    final String label;

    switch (status) {
      case 'confirmed':
        icon = Icons.check_circle;
        color = Colors.green;
        label = s.sendLogStatusConfirmed;
        break;
      case 'sent':
        icon = Icons.upload;
        color = Colors.blue;
        label = s.sendLogStatusSent;
        break;
      case 'failed':
        icon = Icons.error;
        color = Colors.red;
        label = s.sendLogStatusFailed;
        break;
      case 'queued':
        icon = Icons.hourglass_bottom;
        color = Colors.orange;
        label = s.sendLogStatusQueued;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
        label = status;
    }

    final timeStr = _formatLogTime(time);
    final coordStr = lat != null && lng != null
        ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
        : '—';

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Row(
        children: [
          Text(
            timeStr,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(coordStr, style: const TextStyle(fontSize: 12)),
          if (error != null)
            Text(error, style: TextStyle(fontSize: 11, color: Colors.red.shade300)),
        ],
      ),
    );
  }

  String _formatLogTime(String isoUtc) {
    try {
      final dt = DateTime.parse(isoUtc).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoUtc;
    }
  }
}
