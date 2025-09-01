import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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
  Timer? _statePoller;
  int? _recordingStartEpochSec;

  @override
  void initState() {
    super.initState();
    _ensurePermissions(silent: true);

    // Listen for native recording state changes (e.g., stopping from notification)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'recordingStateChanged') {
        final args = call.arguments;
        bool rec = false;
        try {
          final map = Map<String, dynamic>.from(args as Map);
          rec = map['recording'] == true;
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _isRecording = rec;
          _status = rec ? 'Recording in background' : 'Stopped';
        });
      }
    });
  }

  Future<bool> _ensurePermissions({bool silent = false}) async {
    try {
      final toRequest = <Permission>[Permission.camera, Permission.microphone];
      if (Platform.isAndroid) {
        toRequest.add(Permission.notification);
        // Request read videos for history browsing
        toRequest.add(Permission.videos);
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

  void _startPollingForStop() {
    _statePoller?.cancel();
    _statePoller = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isRecording || _recordingStartEpochSec == null) {
        _statePoller?.cancel();
        return;
      }
      try {
        final res = await _channel.invokeMethod('listRecordings');
        final list = (res as List?)?.cast<dynamic>() ?? const [];
        if (list.isEmpty) return;
        bool found = false;
        for (final e in list) {
          try {
            final m = Map<String, dynamic>.from(e as Map);
            final int dateSec = (m['date'] as num).toInt();
            if (dateSec >= (_recordingStartEpochSec! - 1)) {
              found = true;
              break;
            }
          } catch (_) {}
        }
        if (found) {
          if (!mounted) return;
          setState(() {
            _isRecording = false;
            _status = 'Stopped';
          });
          _statePoller?.cancel();
        }
      } catch (_) {}
    });
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
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      setState(() {
        _isRecording = true;
        _status = 'Recording in background';
        _recordingStartEpochSec = nowSec;
      });
      _startPollingForStop();
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
      _statePoller?.cancel();
      await _channel.invokeMethod('stopService');
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _status = 'Stopped';
      });
      _showSnack('Recording stopped. Files are saved in the Movies folder.');
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
  void dispose() {
    _statePoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Video Recorder'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary.withOpacity(0.15), cs.secondary.withOpacity(0.20)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.videocam_rounded, color: cs.onPrimaryContainer, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isRecording ? 'Recording...' : 'Ready to record',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _status,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isRecording ? Colors.red.withOpacity(0.12) : cs.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _isRecording ? Colors.red : cs.outlineVariant),
                          ),
                          child: Text(
                            _isRecording ? 'REC' : 'IDLE',
                            style: TextStyle(
                              color: _isRecording ? Colors.red : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Camera chips
                  Text('Camera', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Back'),
                        showCheckmark: false,
                        selected: _cameraFacing == 'back',
                        onSelected: (v) {
                          if (!_isRecording) setState(() => _cameraFacing = 'back');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Front'),
                        showCheckmark: false,
                        selected: _cameraFacing == 'front',
                        onSelected: (v) {
                          if (!_isRecording) setState(() => _cameraFacing = 'front');
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Quality chips
                  Text('Quality', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('480p'),
                        showCheckmark: false,
                        selected: _quality == 480,
                        onSelected: (v) {
                          if (!_isRecording) setState(() => _quality = 480);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('720p'),
                        showCheckmark: false,
                        selected: _quality == 720,
                        onSelected: (v) {
                          if (!_isRecording) setState(() => _quality = 720);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('1080p'),
                        showCheckmark: false,
                        selected: _quality == 1080,
                        onSelected: (v) {
                          if (!_isRecording) setState(() => _quality = 1080);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Action area
                  Container(
                    padding: const EdgeInsets.all(16),
                    constraints: const BoxConstraints(minHeight: 240),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            style: ButtonStyle(
                              backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
                                if (_isRecording) return Colors.red;
                                return null; // default
                              }),
                            ),
                            onPressed: _isRecording ? _stopRecording : _startRecording,
                            icon: Icon(_isRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record),
                            label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final ok = await _ensurePermissions();
                                  if (ok) _showSnack('All required permissions granted');
                                },
                                icon: const Icon(Icons.lock_open),
                                label: const Text('Grant Permissions'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushNamed('/history');
                                },
                                icon: const Icon(Icons.history),
                                label: const Text('Open History'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A notification shows while recording. Videos save to Movies/BackgroundVideoRecorder (Android 10+).',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
