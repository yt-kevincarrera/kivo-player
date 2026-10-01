import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_order.dart';
import '../state/controls_visibility.dart';
import '../state/lock_state.dart';
import '../state/queue_strip_state.dart';
import '../state/skip_feedback.dart';
import '../tracks/track_sync_hud.dart';

/// Media keys do the same whatever is on screen, locked included.
final _mediaKeys = <LogicalKeyboardKey, PlayerKeyAction>{
  LogicalKeyboardKey.mediaPlayPause: PlayerKeyAction.togglePlay,
  LogicalKeyboardKey.mediaPlay: PlayerKeyAction.play,
  LogicalKeyboardKey.mediaPause: PlayerKeyAction.pause,
  LogicalKeyboardKey.mediaFastForward: PlayerKeyAction.seekForward,
  LogicalKeyboardKey.mediaRewind: PlayerKeyAction.seekBack,
  LogicalKeyboardKey.mediaTrackNext: PlayerKeyAction.next,
  LogicalKeyboardKey.mediaTrackPrevious: PlayerKeyAction.previous,
};

/// What a key does in the player.
enum PlayerKeyAction {
  togglePlay,
  play,
  pause,
  seekBack,
  seekForward,
  next,
  previous,

  /// Bring the controls up and put the focus on play/pause, so the arrows
  /// can move between the buttons from there.
  revealControls,

  /// Leave it to the focused button and Flutter's focus traversal.
  pass,
}

/// The player's keys — a TV remote's D-pad, a game pad, a keyboard, media
/// buttons. Media keys always do their thing. The D-pad depends on whether
/// the controls are up: hidden, ←/→ seek, OK plays/pauses and ↑/↓ bring
/// the controls; up, the D-pad moves between the buttons and OK presses the
/// focused one, like anywhere else in the app. Locked, only media keys work.
PlayerKeyAction playerKeyAction(
  LogicalKeyboardKey key, {
  required bool controlsVisible,
  required bool locked,
}) {
  final media = _mediaKeys[key];
  if (media != null) return media;
  if (locked) return PlayerKeyAction.pass;
  // Space is play/pause on a keyboard even with the controls up — the one
  // key every desktop player agrees on.
  if (key == LogicalKeyboardKey.space) return PlayerKeyAction.togglePlay;
  if (controlsVisible) return PlayerKeyAction.pass;
  if (key == LogicalKeyboardKey.arrowLeft) return PlayerKeyAction.seekBack;
  if (key == LogicalKeyboardKey.arrowRight) return PlayerKeyAction.seekForward;
  if (key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA) {
    return PlayerKeyAction.togglePlay;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown) {
    return PlayerKeyAction.revealControls;
  }
  return PlayerKeyAction.pass;
}

/// Where the focus lands when the controls come up from a key.
final playPauseFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'play-pause');
  ref.onDispose(node.dispose);
  return node;
});

/// Where the focus lands when a key wakes the lock overlay.
final unlockFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'unlock');
  ref.onDispose(node.dispose);
  return node;
});

/// Wraps the player and turns keys into [playerKeyAction]s. It sits under
/// the app's shortcuts, so it sees a key before the default "move focus" /
/// "activate" handling does, and only claims the keys it acts on.
class PlayerKeys extends ConsumerStatefulWidget {
  final Widget child;
  const PlayerKeys({super.key, required this.child});

  @override
  ConsumerState<PlayerKeys> createState() => _PlayerKeysState();
}

class _PlayerKeysState extends ConsumerState<PlayerKeys> {
  final _node = FocusNode(debugLabel: 'player-keys');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  bool get _controlsShown => controlsShouldRender(
    visible: ref.read(controlsVisibleProvider),
    syncPanelOpen: ref.read(syncHudProvider) != null,
  );

  /// Puts [target] in focus once the frame that shows it has been built
  /// (hidden controls are excluded from focus).
  void _focusAfterFrame(FocusNode target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) target.requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final controls = ref.read(controlsVisibleProvider.notifier);
    final locked = ref.read(lockProvider);
    final syncOpen = ref.read(syncHudProvider) != null;
    final shown = _controlsShown;
    final action = playerKeyAction(
      key,
      // The sync panel is a set of controls of its own: the D-pad moves
      // through it, like through the bars.
      controlsVisible: shown || syncOpen,
      locked: locked,
    );
    if (action == PlayerKeyAction.pass) {
      if (!_navigates(key)) {
        if (shown) controls.show();
        return KeyEventResult.ignored;
      }
      if (syncOpen) {
        // Nothing in the panel focused yet: step into it.
        if (node.hasPrimaryFocus) {
          node.nextFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (locked) {
        // Locked, the only control is unlock: any D-pad press brings it up
        // with the focus on it, and OK there unlocks.
        controls.show();
        if (!shown || node.hasPrimaryFocus) {
          _focusAfterFrame(ref.read(unlockFocusProvider));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (!shown) return KeyEventResult.ignored;
      // Moving around the controls counts as using them: keep them up.
      controls.show();
      // Up from a tap, nothing of them has the focus yet: the first D-pad
      // press lands on play/pause instead of going nowhere.
      if (node.hasPrimaryFocus) {
        ref.read(playPauseFocusProvider).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Holding a seek key repeats it; holding OK must not flicker play/pause.
    if (event is KeyRepeatEvent &&
        action != PlayerKeyAction.seekBack &&
        action != PlayerKeyAction.seekForward) {
      return KeyEventResult.handled;
    }
    _run(action);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Controls fading out take the focus out with them (they are excluded
    // from focus while hidden): bring it back here, or the next key would
    // go nowhere — and an invisible button must not keep it.
    ref.listen<bool>(controlsVisibleProvider, (_, visible) {
      if (!visible && !_node.hasPrimaryFocus) _node.requestFocus();
    });
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }

  static bool _navigates(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  void _run(PlayerKeyAction action) {
    final ctrl = ref.read(playerControllerProvider);
    final engine = ref.read(playbackEngineProvider);
    switch (action) {
      case PlayerKeyAction.togglePlay:
        ctrl.togglePlayPause();
      case PlayerKeyAction.play:
        engine.play();
      case PlayerKeyAction.pause:
        engine.pause();
      case PlayerKeyAction.seekBack:
      case PlayerKeyAction.seekForward:
        final skip = ref.read(settingsProvider).centerSkipSeconds;
        final s = action == PlayerKeyAction.seekForward ? skip : -skip;
        ctrl.skipBy(s);
        ref.read(skipFeedbackProvider).bump(s);
      case PlayerKeyAction.next:
      case PlayerKeyAction.previous:
        final target = queueStep(
          ref.read(currentVideoProvider),
          forward: action == PlayerKeyAction.next,
          wrap: ref.read(settingsProvider).repeatMode == RepeatMode.list.name,
        );
        if (target != null) ref.read(queueJumpProvider.notifier).state = target;
      case PlayerKeyAction.revealControls:
        ref.read(controlsVisibleProvider.notifier).show();
        _focusAfterFrame(ref.read(playPauseFocusProvider));
      case PlayerKeyAction.pass:
        break;
    }
  }
}

/// The queue index a next/previous key goes to: the neighbour in play order
/// (shuffle included), wrapping around only under repeat-list. Repeat-one
/// does not hold it on the same video — a "next" key means another video.
int? queueStep(VideoSession? s, {required bool forward, required bool wrap}) {
  if (s == null || s.queue.isEmpty) return null;
  final order = s.order ?? List<int>.generate(s.queue.length, (i) => i);
  final at = order.indexOf(s.index);
  if (at < 0) return null;
  final to = at + (forward ? 1 : -1);
  if (to >= 0 && to < order.length) return order[to];
  if (!wrap || order.length < 2) return null;
  return order[(to + order.length) % order.length];
}
