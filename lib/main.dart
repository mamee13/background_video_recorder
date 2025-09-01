import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const BackgroundVideoRecorderApp());
}

class BackgroundVideoRecorderApp extends StatelessWidget {
  const BackgroundVideoRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Video Recorder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const RecorderHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RecorderHomePage extends StatefulWidget {
  const RecorderHomePage({super.key});

  @override
  State<RecorderHomePage> createState() => _RecorderHomePageState();
}

class _RecorderHomePageState extends State<RecorderHomePage> {
  static const _channel = MethodChannel('bvr/channel');

  bool _isRecording = false;
  String _status = 'Idle';
  String _cameraFacing = 'back'; // or 'front'
  int _quality = 1080; // 480, 720, 1080

  @override
  void initState() {
    super.initState();
    // Optionally pre-request permissions for smoother UX.
    _ensurePermissions(silent: true);
  }

  Future<bool> _ensurePermissions({bool silent = false}) async {
    try {
      final toRequest = <Permission>[Permission.camera, Permission.microphone];
      if (Platform.isAndroid) {
        // On Android 13+ this is required for foreground notification.
        toRequest.add(Permission.notification);
      }
      final statuses = await toRequest.request();
      final granted = statuses.values.every((s) => s.isGranted);
      if (!granted && !silent && mounted) {
        final denied = statuses.entries
            .where((e) => !e.value.isGranted)
            .map((e) => e.key.toString().split('.').last)
            .join(', ');
        _showSnack('Permissions denied: $denied');
      }
      return granted;
    } catch (e) {
      if (!silent) _showSnack('Permission error: $e');
      return false;
    }
  }

  Future<void> _startRecording() async {
    if (!await _ensurePermissions()) return;

    setState(() {
      _status = 'Starting...';
    });

    try {
      await _channel.invokeMethod('startService', {
        'cameraFacing': _cameraFacing,
        'quality': _quality,
      });
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _status = 'Recording in background';
      });
      _showSnack('Recording started. You can switch apps or lock the screen.');
    } on PlatformException catch (e) {
      _showSnack('Failed to start: ${e.message}');
      setState(() => _status = 'Idle');
    } catch (e) {
      _showSnack('Failed to start: $e');
      setState(() => _status = 'Idle');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _channel.invokeMethod('stopService');
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _status = 'Stopped';
      });
      _showSnack('Recording stopped. Files are saved in the app Movies folder.');
    } on PlatformException catch (e) {
      _showSnack('Failed to stop: ${e.message}');
    } catch (e) {
      _showSnack('Failed to stop: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Video Recorder'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _cameraFacing,
                      decoration: const InputDecoration(
                        labelText: 'Camera',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'back', child: Text('Back')),
                        DropdownMenuItem(value: 'front', child: Text('Front')),
                      ],
                      onChanged: _isRecording
                          ? null
                          : (v) => setState(() => _cameraFacing = v ?? 'back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _quality,
                      decoration: const InputDecoration(
                        labelText: 'Quality',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 480, child: Text('480p')),
                        DropdownMenuItem(value: 720, child: Text('720p')),
                        DropdownMenuItem(value: 1080, child: Text('1080p')),
                      ],
                      onChanged:
                          _isRecording ? null : (v) => setState(() => _quality = v ?? 1080),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isRecording ? null : _startRecording,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('Start Recording'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isRecording ? _stopRecording : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await _ensurePermissions();
                  if (ok) _showSnack('All required permissions granted');
                },
                icon: const Icon(Icons.lock_open),
                label: const Text('Grant Permissions'),
              ),
              const SizedBox(height: 24),
              _InfoCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Notes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '- A persistent notification will appear while recording.\n'
              '- Videos are saved to the app\'s Movies directory (no storage permission needed).\n'
              '- If recording stops unexpectedly, disable battery optimization for this app.',
            ),
          ],
        ),
      ),
    );
  }
}