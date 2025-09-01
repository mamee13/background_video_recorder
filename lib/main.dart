import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const _AppRoot(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Decides whether to show onboarding or the recorder screen
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  Future<bool> _onboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_done') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboardingDone(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data == true
            ? const RecorderHomePage()
            : const OnboardingPage();
      },
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _index = 0;
  bool _requesting = false;

  Future<void> _markDoneAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RecorderHomePage()),
    );
  }

  Future<void> _requestPermissions() async {
    setState(() => _requesting = true);
    try {
      final req = <Permission>[Permission.camera, Permission.microphone];
      if (Platform.isAndroid) req.add(Permission.notification);
      await req.request();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _OnboardSlide(
        icon: Icons.videocam_outlined,
        title: 'Record in the background',
        text:
            'Capture video while using other apps or when the screen is off. A persistent notification keeps you in control.',
      ),
      _OnboardSlide(
        icon: Icons.tune,
        title: 'Choose camera and quality',
        text:
            'Select front/back camera and set the recording quality that fits your needs (480p, 720p, 1080p).',
      ),
      _OnboardSlide(
        icon: Icons.folder_special_outlined,
        title: 'Your videos, easy to find',
        text: Platform.isAndroid
            ? 'On Android 10+, videos are saved to Movies/BackgroundVideoRecorder and visible in your Gallery.'
            : 'Videos are saved in the app folder.'
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _index = i),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      pages.length,
                      (i) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _requesting ? null : _requestPermissions,
                          icon: _requesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.lock_open_outlined),
                          label: const Text('Grant Permissions'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _markDoneAndContinue,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Get Started'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Use responsibly. Always comply with local laws and inform people when recording.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardSlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _OnboardSlide({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Icon(icon, size: 92, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
    _ensurePermissions(silent: true);
  }

  Future<bool> _ensurePermissions({bool silent = false}) async {
    try {
      final toRequest = <Permission>[Permission.camera, Permission.microphone];
      if (Platform.isAndroid) {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Video Recorder'),
        actions: [
          IconButton(
            tooltip: 'About',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Background Video Recorder',
              applicationVersion: '1.0.0',
              applicationLegalese:
                  'Use responsibly. Comply with laws and always inform people when recording.',
            ),
            icon: const Icon(Icons.info_outline),
          )
        ],
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
              '- Videos are saved to the Movies/BackgroundVideoRecorder folder on Android 10+.\n'
              '- If recording stops unexpectedly, disable battery optimization for this app.',
            ),
          ],
        ),
      ),
    );
  }
}