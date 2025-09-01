import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerPage extends StatefulWidget {
  final String title;
  final String? uri; // content:// on Android 10+
  final String? path; // file path on older Android

  const VideoPlayerPage({super.key, required this.title, this.uri, this.path});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _initFuture = _controller!.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  VideoPlayerController _buildController() {
    if (widget.uri != null) {
      return VideoPlayerController.contentUri(Uri.parse(widget.uri!));
    }
    return VideoPlayerController.file(File(widget.path!));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: c == null
          ? const Center(child: Text('Invalid video'))
          : FutureBuilder<void>(
              future: _initFuture,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    AspectRatio(
                      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(c),
                          _ControlsOverlay(
                            controller: c,
                            onPlayPause: (playing) => setState(() => _isPlaying = playing),
                          ),
                        ],
                      ),
                    ),
                    _buildSeekBar(c, cs),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSeekBar(VideoPlayerController c, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(_fmt(c.value.position)),
          Expanded(
            child: Slider(
              value: c.value.position.inMilliseconds.clamp(0, c.value.duration.inMilliseconds).toDouble(),
              max: c.value.duration.inMilliseconds.toDouble(),
              onChanged: (v) async {
                final pos = Duration(milliseconds: v.toInt());
                await c.seekTo(pos);
                setState(() {});
              },
            ),
          ),
          Text(_fmt(c.value.duration)),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  final ValueChanged<bool> onPlayPause;
  const _ControlsOverlay({required this.controller, required this.onPlayPause});

  @override
  State<_ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<_ControlsOverlay> {
  bool _visible = true;

  void _toggle() => setState(() => _visible = !_visible);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black26,
          child: Center(
            child: IconButton(
              iconSize: 64,
              color: Colors.white,
              icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
              onPressed: () async {
                if (c.value.isPlaying) {
                  await c.pause();
                } else {
                  await c.play();
                }
                widget.onPlayPause(c.value.isPlaying);
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );
  }
}