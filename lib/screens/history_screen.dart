import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const _channel = MethodChannel('bvr/channel');
  List<RecordingItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Ensure read permission on Android 13+
      if (Platform.isAndroid) {
        await Permission.videos.request();
      }
      final res = await _channel.invokeMethod('listRecordings');
      final list = (res as List)
          .map((e) => RecordingItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      setState(() {
        _items = list;
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(RecordingItem item) async {
    try {
      final uri = item.uri;
      final ok = await launchUrl(
        uri != null ? Uri.parse(uri) : Uri.file(item.path!),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _snack('No app found to open this video');
    } catch (e) {
      _snack('Failed to open: $e');
    }
  }

  Future<void> _delete(RecordingItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete video?'),
        content: Text(item.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final ok = await _channel.invokeMethod('deleteRecording', {
        'uri': item.uri,
        'path': item.path,
      });
      if (ok == true) {
        _snack('Deleted');
        _load();
      } else {
        _snack('Delete failed');
      }
    } catch (e) {
      _snack('Delete error: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No recordings found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final it = _items[i];
                      return Card(
                        color: cs.surfaceVariant.withOpacity(0.8),
                        child: ListTile(
                          leading: const Icon(Icons.movie_outlined, size: 32),
                          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${_formatBytes(it.size)} • ${_formatDate(it.dateSeconds)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Open',
                                onPressed: () => _open(it),
                                icon: const Icon(Icons.open_in_new),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => _delete(it),
                                icon: const Icon(Icons.delete_outline),
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

class RecordingItem {
  final String? uri; // content:// on Android 10+
  final String? path; // file path on older Android
  final String name;
  final int dateSeconds; // seconds since epoch
  final int size;

  RecordingItem({required this.uri, required this.path, required this.name, required this.dateSeconds, required this.size});

  factory RecordingItem.fromMap(Map<String, dynamic> m) => RecordingItem(
        uri: m['uri'] as String?,
        path: m['path'] as String?,
        name: m['name'] as String,
        dateSeconds: (m['date'] as num).toInt(),
        size: (m['size'] as num).toInt(),
      );
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  double v = bytes.toDouble();
  int idx = 0;
  while (v >= 1024 && idx < units.length - 1) {
    v /= 1024;
    idx++;
  }
  return '${v.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
}

String _formatDate(int secondsSinceEpoch) {
  final dt = DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000);
  return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
}

String _pad(int v) => v.toString().padLeft(2, '0');
