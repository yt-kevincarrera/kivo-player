import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../core/format.dart';
import '../../core/icons/kivo_icons.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/interfaces/media_permission.dart';
import '../../player/library/media_index.dart';
import '../../player/library/media_permission.dart';
import '../../player/open/video_source.dart';
import '../player/controls/resume_prompt.dart';
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
    try {
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (!mounted) return;
        if (files.isNotEmpty) _openPath(files.first.path);
      });
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        if (files.isNotEmpty) _openPath(files.first.path);
      });
    } catch (_) {
      // ReceiveSharingIntent is not available in test/desktop environments.
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  void _push() {
    // Clear any leftover resume toast before the next player mounts, so a stale
    // toast from a previous video never flashes onto the new one.
    ref.read(resumePromptProvider.notifier).state = null;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  void _openPath(String path) {
    if (!mounted) return;
    ref.read(currentVideoProvider.notifier).openPath(path);
    _push();
  }

  void _openItem(VideoItem item, List<VideoItem> all) {
    ref.read(currentVideoProvider.notifier).openInFolder(item, all);
    _push();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(mediaPermissionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kivo'),
        actions: [
          IconButton(
            tooltip: 'Abrir archivo',
            icon: KivoIcon(KivoIcons.folderOpen, size: 22),
            onPressed: _pick,
          ),
        ],
      ),
      body: perm.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _AccessPrompt(onGrant: () => ref.read(mediaPermissionProvider.notifier).request()),
        data: (access) {
          if (access == MediaAccess.denied) {
            return _AccessPrompt(onGrant: () => ref.read(mediaPermissionProvider.notifier).request());
          }
          final index = ref.watch(mediaIndexProvider);
          return index.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
            data: (videos) {
              if (videos.isEmpty) {
                return const Center(child: Text('No se encontraron videos', style: TextStyle(color: Colors.white70)));
              }
              return ListView.builder(
                itemCount: videos.length,
                itemBuilder: (_, i) {
                  final v = videos[i];
                  return ListTile(
                    title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${v.folder} · ${fmtDuration(Duration(milliseconds: v.durationMs))}',
                        style: const TextStyle(color: Colors.white54)),
                    onTap: () => _openItem(v, videos),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AccessPrompt extends StatelessWidget {
  final VoidCallback onGrant;
  const _AccessPrompt({required this.onGrant});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Da acceso a tus videos para verlos aquí',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onGrant, child: const Text('Dar acceso')),
          ],
        ),
      );
}
