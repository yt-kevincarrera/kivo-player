import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/open/video_source.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  VideoController? _controller;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  String? _path;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
  }

  Future<void> _start() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    _path = session.path;
    final engine = ref.read(playbackEngineProvider);
    final resume = ref.read(resumeServiceProvider);
    final startAt = resume.positionFor(session.path) ?? Duration.zero;

    final c = engine.createVideoController();
    if (c is VideoController) {
      _controller = c;
      setState(() {});
    }
    await engine.open(session.path, startAt: startAt);
  }

  Future<void> _saveProgress() async {
    final path = _path;
    if (path == null || _lastDuration == Duration.zero) return;
    await ref.read(resumeServiceProvider).record(path, _lastPosition, _lastDuration);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(); // best-effort for in-app pop
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(positionProvider, (_, next) {
      next.whenData((d) => _lastPosition = d);
    });
    ref.listen(durationProvider, (_, next) {
      next.whenData((d) => _lastDuration = d);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _controller == null
            ? const CircularProgressIndicator()
            : Video(controller: _controller!),
      ),
    );
  }
}
