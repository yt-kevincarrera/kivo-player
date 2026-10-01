import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/navigation.dart';
import '../../platform/interfaces/launcher_bridge.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/launcher_bridge_provider.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/media_index.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../player/player_route.dart';

/// How many entries the launcher shortcuts and the widget get.
const launcherContinueCount = 3;

/// The "Continuar viendo" list as the launcher surfaces show it.
List<ContinueEntry> continueEntriesFor(List<ContinueItem> items) => [
      for (final c in items.take(launcherContinueCount))
        ContinueEntry(
          id: c.video.id,
          uri: c.video.uri,
          name: c.video.name,
          position: fmtDuration(Duration(seconds: c.seconds)),
          fraction: c.fraction,
        ),
    ];

/// The video a shortcut/widget asked for, and the queue to open it with: its
/// folder, in library order — so folder subtitles and autoplay-next work as
/// if it had been tapped in the library. Null when it is gone (deleted,
/// moved to the Vault) since the shortcut was made.
({VideoItem video, List<VideoItem> queue})? resolveLaunch(
    String id, List<VideoItem> index) {
  final i = index.indexWhere((v) => v.id == id);
  if (i < 0) return null;
  final video = index[i];
  return (
    video: video,
    queue: index.where((v) => v.folder == video.folder).toList(),
  );
}

/// Keeps the launcher shortcuts and the home-screen widget in step with
/// "Continuar viendo", and opens what a tap on either asks for.
///
/// App-scoped, started from KivoApp: a tap can arrive with the app closed
/// (initial request) or open on any screen (stream).
class LaunchCoordinator {
  LaunchCoordinator(this._ref);
  final Ref _ref;

  LauncherBridge? _bridge;
  List<ContinueEntry>? _sent;
  Timer? _debounce;
  StreamSubscription<String>? _requests;

  Future<void> start() async {
    try {
      _bridge = _ref.read(launcherBridgeProvider);
    } catch (e) {
      debugPrint('launch coordinator: no launcher bridge ($e)');
      return;
    }
    _ref.listen<List<ContinueItem>>(continueWatchingProvider, (_, next) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () => _push(next));
    }, fireImmediately: true);
    _requests = _bridge!.openRequests.listen(open);
    final initial = await _bridge!.takeInitialOpenRequest();
    if (initial != null) await open(initial);
  }

  Future<void> _push(List<ContinueItem> items) async {
    final entries = continueEntriesFor(items);
    if (listEquals(entries, _sent)) return;
    _sent = entries;
    await _bridge?.updateContinue(entries);
  }

  /// Opens the video with MediaStore [id], replacing whatever player is up.
  Future<void> open(String id) async {
    List<VideoItem> index;
    try {
      index = await _ref.read(mediaIndexProvider.future);
    } catch (_) {
      return;
    }
    final target = resolveLaunch(id, index);
    final nav = kivoNavigatorKey.currentState;
    if (target == null || nav == null) return;
    _ref.read(currentVideoProvider.notifier).openFromList(target.video, target.queue);
    // One player at a time: a tap while another video is up replaces it.
    nav.popUntil((r) => r.isFirst);
    unawaited(nav.push(playerRoute()).then((_) {
      _ref.invalidate(continueWatchingProvider);
      _ref.invalidate(playedKeysProvider);
    }));
  }

  void dispose() {
    _debounce?.cancel();
    _requests?.cancel();
  }
}

final launchCoordinatorProvider = Provider<LaunchCoordinator>((ref) {
  final c = LaunchCoordinator(ref);
  ref.onDispose(c.dispose);
  return c;
});
