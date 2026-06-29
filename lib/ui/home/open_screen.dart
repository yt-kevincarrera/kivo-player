import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../player/open/video_source.dart';
import '../player/player_screen.dart';

class OpenScreen extends ConsumerStatefulWidget {
  const OpenScreen({super.key});
  @override
  ConsumerState<OpenScreen> createState() => _OpenScreenState();
}

class _OpenScreenState extends ConsumerState<OpenScreen> {
  StreamSubscription<dynamic>? _shareSub;

  @override
  void initState() {
    super.initState();
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (!mounted) return;
      if (files.isNotEmpty) _openPath(files.first.path);
    });
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) _openPath(files.first.path);
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _openPath(String path) {
    if (!mounted) return;
    ref.read(currentVideoProvider.notifier).openPath(path);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open),
          label: const Text('Abrir video'),
        ),
      ),
    );
  }
}
