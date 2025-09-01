import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BackgroundVideoRecorderApp());
}

class BackgroundVideoRecorderApp extends StatelessWidget {
  const BackgroundVideoRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    return MaterialApp(
      title: 'Background Video Recorder',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          centerTitle: true,
        ),
      ),
      home: const _AppRoot(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Decides whether to show onboarding or the main tabs
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
        return snap.data == true ? const TabsRoot() : const OnboardingPage();
      },
    );
  }
}

/// Bottom navigation with Home (Recorder), History, Contact
class TabsRoot extends StatefulWidget {
  const TabsRoot({super.key});

  @override
  State<TabsRoot> createState() => _TabsRootState();
}

class _TabsRootState extends State<TabsRoot> {
  int _index = 0;

  final _pages = const [
    RecorderHomePage(),
    HistoryPage(),
    ContactPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.contact_mail_outlined), selectedIcon: Icon(Icons.contact_mail), label: 'Contact'),
        ],
      ),
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
      MaterialPageRoute(builder: (_) => const TabsRoot()),
    );
  }

  Future<void> _requestPermissions() async {
    setState(() => _requesting = true);
    try {
      final req = <Permission>[Permission.camera, Permission.microphone];
      if (Platform.isAndroid) {
        req.add(Permission.notification);
        // For listing recordings on Android 13+ via MediaStore
        req.add(Permission.videos);
      }
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
            'Select front/back camera and set the recording quality (480p, 720p, 1080p).',
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
      appBar: AppBar(title: const Text('Welcome')),
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
                  // Header fills width and uses vertical space
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary.withOpacity(0.15), cs.secondaryContainer.withOpacity(0.3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
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
                        Icon(
                          _isRecording ? Icons.circle : Icons.radio_button_unchecked,
                          color: _isRecording ? Colors.red : cs.outline,
                          size: 16,
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Controls section uses SegmentedButtons to better utilize width
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Camera', style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'back', label: Text('Back'), icon: Icon(Icons.camera_rear_outlined)),
                                ButtonSegment(value: 'front', label: Text('Front'), icon: Icon(Icons.camera_front_outlined)),
                              ],
                              selected: {_cameraFacing},
                              onSelectionChanged: _isRecording
                                  ? null
                                  : (s) => setState(() => _cameraFacing = s.first),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Quality', style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(value: 480, label: Text('480p')),
                                ButtonSegment(value: 720, label: Text('720p')),
                                ButtonSegment(value: 1080, label: Text('1080p')),
                              ],
                              selected: {_quality},
                              onSelectionChanged: _isRecording
                                  ? null
                                  : (s) => setState(() => _quality = s.first),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Large action area
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                                if (_isRecording) return Colors.red;
                                return null; // default
                              }),
                            ),
                            onPressed: _isRecording ? _stopRecording : _startRecording,
                            icon: Icon(_isRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record),
                            label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                  // Navigate to History without switching tab index
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const HistoryPage()),
                                  );
                                },
                                icon: const Icon(Icons.history),
                                label: const Text('Open History'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Tips/Info uses more vertical space with better readability
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Tips', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text('• A persistent notification shows while recording.'),
                          SizedBox(height: 4),
                          Text('• Videos save to Movies/BackgroundVideoRecorder on Android 10+.'),
                          SizedBox(height: 4),
                          Text('• If recording stops, disable battery optimization for the app.'),
                        ],
                      ),
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
                        color: cs.surfaceContainerLow,
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

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  Future<void> _launch(Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero header uses free vertical space
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary.withOpacity(0.15), cs.secondaryContainer.withOpacity(0.3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.support_agent, color: cs.onPrimaryContainer, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'We\'re here to help',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Contact us for support, feedback, or feature requests.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action cards
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ContactCard(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: 'mamaruyirga1394@gmail.com',
                  onTap: () => _launch(Uri.parse('mailto:mamaruyirga1394@gmail.com?subject=Background%20Video%20Recorder%20Support')),
                ),
                _ContactCard(
                  icon: Icons.language_outlined,
                  title: 'Website',
                  subtitle: 'https://example.com',
                  onTap: () => _launch(Uri.parse('https://example.com')),
                ),
                _ContactCard(
                  icon: Icons.alternate_email,
                  title: 'Twitter / X',
                  subtitle: 'https://x.com/your_handle',
                  onTap: () => _launch(Uri.parse('https://x.com/mamee1313')),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Quick actions row
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launch(Uri.parse('mailto:mamaruyirga1394@gmail.com?subject=Background%20Video%20Recorder%20Support')),
                    icon: const Icon(Icons.send),
                    label: const Text('Email Support'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launch(Uri.parse('https://example.com')),
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Visit Website'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              'We typically respond within 1–2 business days.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 500, // allows Wrap to arrange in 1–2 columns depending on width
      child: Card(
        color: cs.surfaceContainerLow,
        child: ListTile(
          leading: Icon(icon, size: 28),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.open_in_new),
          onTap: onTap,
        ),
      ),
    );
  }
}