# Kivo Mini-Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Minimizing the player (via any exit path) shows a persistent, global mini-bar with a freeze-frame preview, title, play/pause, and close, instead of closing the player outright.

**Architecture:** Two sequential tasks. Task 1 adds the state model (`playerMinimizedProvider`, `miniPlayerThumbnailProvider`) and wires `PlayerScreen` to set/reset it on minimize and on fresh entry. Task 2 builds the `MiniPlayerBar` widget and mounts it globally via `MaterialApp.builder` in `app.dart`. Task 2 depends on Task 1's providers existing.

**Tech Stack:** Flutter (Material 3), Riverpod.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-01-kivo-mini-player-design.md`.
- Every exit path (top-bar back button, system back, swipe-down) minimizes — none close the player outright. Closing outright is only reachable from the mini-bar (X button or swipe-lateral).
- Minimizing always pauses; there is no background playback.
- The mini-bar is global (mounted above the Navigator), not scoped to `LibraryScreen`.
- Expanding reuses the existing resume-open flow (a brief reload is accepted — no session-continuity mechanism).
- The preview is a static freeze-frame (via the existing `FrameExtractor`), never a live video texture.
- `AnimationController`/`Timer` (if any) created in `initState`, disposed — never a field initializer. Never `ref.read(...)` in `dispose()`. `withValues(alpha:)`, not `withOpacity`.
- `flutter analyze` clean + `flutter test` green before each commit. Do not push.

---

### Task 1: Mini-player state + `PlayerScreen` wiring

**Files:**
- Create: `lib/ui/player/state/mini_player_state.dart`
- Modify: `lib/ui/player/player_screen.dart`
- Test: `test/ui/player/state/mini_player_state_test.dart` (new), extend `test/ui/player/player_screen_controls_test.dart`

**Interfaces:**
- Produces: `playerMinimizedProvider` (`StateProvider<bool>`, default `false`); `miniPlayerThumbnailProvider` (`StateProvider<Uint8List?>`, default `null`).
- Consumes: `FrameExtractor.frameAt(Duration position)` (existing, returns `Future<Uint8List?>`), `_lastPosition` (existing field on `_PlayerScreenState`).

- [ ] **Step 1: Create `lib/ui/player/state/mini_player_state.dart`.**

```dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the player is minimized to the global mini-bar instead of
/// showing full-screen. Set on any exit (back button, system back,
/// swipe-down); reset to false whenever a video enters full-screen.
final playerMinimizedProvider = StateProvider<bool>((ref) => false);

/// The freeze-frame preview captured at the moment of minimizing, shown by
/// the mini-bar. Null before any minimize, or if extraction failed/hasn't
/// completed. Reset to null on every fresh player entry.
final miniPlayerThumbnailProvider = StateProvider<Uint8List?>((ref) => null);
```

- [ ] **Step 2: Write the failing test for the new file.**

Create `test/ui/player/state/mini_player_state_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';

void main() {
  test('playerMinimizedProvider defaults to false', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(playerMinimizedProvider), false);
  });

  test('miniPlayerThumbnailProvider defaults to null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(miniPlayerThumbnailProvider), isNull);
  });
}
```

Run: `flutter test test/ui/player/state/mini_player_state_test.dart`
Expected: FAIL (`mini_player_state.dart` does not exist yet) — if you did Step 1 first, this will already PASS; either order is fine as long as both steps land together.

- [ ] **Step 3: Wire `player_screen.dart` — imports and `_start()` resets.**

Add the import near the other `state/` imports:

```dart
import 'state/mini_player_state.dart';
```

In `_start()`, add to the existing per-entry reset block (alongside `dismissProvider`/`resumePromptProvider`/`restartRequestProvider`):

```dart
    ref.read(dismissProvider.notifier).state = 0;
    ref.read(resumePromptProvider.notifier).state = null;
    ref.read(restartRequestProvider.notifier).state = 0;
    ref.read(playerMinimizedProvider.notifier).state = false;
    ref.read(miniPlayerThumbnailProvider.notifier).state = null;
```

(Insert the two new lines right after the existing three resets, before `final engine = ref.read(playbackEngineProvider);`.)

- [ ] **Step 4: Wire the `PopScope` handler to capture a preview frame and set minimized.**

The current handler (inside `build()`) is:

```dart
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _saveProgress();
        if (!mounted) return;
        navigator.pop();
      },
```

Change it to also capture a freeze-frame and flip `playerMinimizedProvider` before popping:

```dart
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _saveProgress();
        await _captureMiniPreview();
        if (!mounted) return;
        ref.read(playerMinimizedProvider.notifier).state = true;
        navigator.pop();
      },
```

Add a new private method near `_saveProgress`:

```dart
  Future<void> _captureMiniPreview() async {
    try {
      final bytes = await _frames.frameAt(_lastPosition);
      if (mounted) ref.read(miniPlayerThumbnailProvider.notifier).state = bytes;
    } catch (_) {
      // Extraction can fail (e.g. no keyframe near this position); the
      // mini-bar falls back to a placeholder icon when the bytes are null.
    }
  }
```

This runs `_frames.frameAt(...)` (via the cached `_frames` field, never `ref.read` in dispose — this handler runs in `build`'s `PopScope`, not `dispose`, so reading `ref` is fine) BEFORE `navigator.pop()` — which is what eventually triggers `dispose()`'s `_frames.release()`. Capturing the frame first means the extractor is guaranteed to still be prepared for this video's path.

- [ ] **Step 5: Write the failing test for the pop-time capture + reset behavior.**

Extend `test/ui/player/player_screen_controls_test.dart` — add a new `testWidgets` after the existing `'popping the player saves progress before the route is removed'` test, reusing the exact same setup pattern:

```dart
  testWidgets('popping the player minimizes it and captures a preview frame',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final resumeStore = InMemoryResumeStore();
    final frames = FakeFrameExtractor();
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(frames),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(c.read(playerMinimizedProvider), false);

    engine.emitDuration(const Duration(minutes: 10));
    engine.emitPosition(const Duration(minutes: 3));
    await tester.pump();

    final playerElement = tester.element(find.byType(PlayerScreen));
    Navigator.of(playerElement).maybePop();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PlayerScreen), findsNothing);
    expect(c.read(playerMinimizedProvider), true);
    expect(c.read(miniPlayerThumbnailProvider), isNotNull);
    expect(frames.requested, contains(const Duration(minutes: 3)));

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('opening a video resets minimized state and the preview',
      (tester) async {
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      playbackEngineProvider.overrideWithValue(engine),
      deviceControlsProvider.overrideWithValue(NoopControls()),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
    ]);
    addTearDown(c.dispose);
    // Simulate leftover state from a previously minimized video.
    c.read(playerMinimizedProvider.notifier).state = true;
    c.read(miniPlayerThumbnailProvider.notifier).state = Uint8List.fromList([1, 2, 3]);
    c.read(currentVideoProvider.notifier).open(
      const VideoSession(playbackPath: '/v/ep2.mkv', displayName: 'ep2.mkv', queue: ['/v/ep2.mkv'], index: 0),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    expect(c.read(playerMinimizedProvider), false);
    expect(c.read(miniPlayerThumbnailProvider), isNull);

    await tester.pump(const Duration(seconds: 4));
  });
```

Add `import 'dart:typed_data';`, `import 'package:kivo_player/ui/player/state/mini_player_state.dart';` to the top of `player_screen_controls_test.dart`.

- [ ] **Step 6: Run the tests to verify they fail, then pass.**

Run: `flutter test test/ui/player/state/mini_player_state_test.dart test/ui/player/player_screen_controls_test.dart -v`
Expected before Steps 1/3/4: FAIL (`mini_player_state.dart` not found / providers undefined / behavior not wired).
After completing Steps 1, 3, 4: Expected PASS for all tests in both files.

- [ ] **Step 7: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass (118 prior + new ones in this task).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/player/state/mini_player_state.dart lib/ui/player/player_screen.dart test/ui/player/state/mini_player_state_test.dart test/ui/player/player_screen_controls_test.dart
git commit -m "feat: mini-player state (minimized flag + preview frame) wired into PlayerScreen exit/entry"
```

---

### Task 2: `MiniPlayerBar` widget + global mount

**Files:**
- Create: `lib/ui/mini_player/mini_player_bar.dart`
- Modify: `lib/app.dart`
- Test: `test/ui/mini_player/mini_player_bar_test.dart` (new)

**Interfaces:**
- Consumes: `playerMinimizedProvider`, `miniPlayerThumbnailProvider` (Task 1), `currentVideoProvider` (`VideoSession.displayName`/`.playbackPath`), `playingProvider`/`positionProvider`/`durationProvider` (existing app-scoped stream providers in `lib/player/engine/playback_provider.dart`), `playerControllerProvider.togglePlayPause()` (existing), `continueWatchingProvider`/`playedKeysProvider` (existing, invalidated on expand same as `_push`/`_open`), `KivoColors.gold` (`lib/core/theme/kivo_theme.dart`), `PlayerScreen` (`lib/ui/player/player_screen.dart`).
- Produces: `MiniPlayerBar` (a `ConsumerWidget`, no constructor params beyond `key`) — mounted once, globally, in `app.dart`.

- [ ] **Step 1: Read `lib/app.dart`** to confirm its exact current content before editing (it should be the ~20-line `KivoApp` with `MaterialApp(theme:, darkTheme:, themeMode:, home: const LibraryScreen())` and no `builder:` yet).

- [ ] **Step 2: Create `lib/ui/mini_player/mini_player_bar.dart`.**

Note on the spec's §5 "swipe lateral → `Dismissible`": this implementation uses a hand-rolled horizontal drag handler (`_dragDx` + `GestureDetector`) instead of Flutter's `Dismissible` widget. `Dismissible` expects its parent to stop rebuilding it with the same key once dismissed; this bar is deliberately kept mounted at all times (gated by `AnimatedSlide`/`AnimatedOpacity`/`IgnorePointer`, never conditionally removed) so the appear/disappear transition can animate smoothly regardless of which action triggered it (X button, swipe, or expanding). A persistently-mounted `Dismissible` fights that architecture. The user-visible behavior — swiping the bar closes it — is unchanged.

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/kivo_theme.dart';
import '../../player/control/player_controller.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/library/continue_watching.dart';
import '../../player/library/played.dart';
import '../../player/open/video_source.dart';
import '../player/player_screen.dart';
import '../player/state/mini_player_state.dart';

/// Global, persistent mini-bar shown above any screen while a video is
/// minimized (see [playerMinimizedProvider]). Mounted once in `app.dart` via
/// `MaterialApp.builder`, above the Navigator, so it survives route changes.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  void _expand(BuildContext context, WidgetRef ref) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()))
        .then((_) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(playedKeysProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minimized = ref.watch(playerMinimizedProvider);
    final session = ref.watch(currentVideoProvider);
    if (session == null) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !minimized,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: minimized ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: minimized ? 1 : 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: _MiniPlayerContent(
                session: session,
                onExpand: () => _expand(context, ref),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerContent extends ConsumerStatefulWidget {
  final VideoSession session;
  final VoidCallback onExpand;
  const _MiniPlayerContent({required this.session, required this.onExpand});

  @override
  ConsumerState<_MiniPlayerContent> createState() => _MiniPlayerContentState();
}

class _MiniPlayerContentState extends ConsumerState<_MiniPlayerContent> {
  double _dragDx = 0;

  void _close() => ref.read(playerMinimizedProvider.notifier).state = false;

  void _onDragEnd(DragEndDetails d) {
    if (_dragDx.abs() > 80) _close();
    setState(() => _dragDx = 0);
  }

  @override
  Widget build(BuildContext context) {
    final thumb = ref.watch(miniPlayerThumbnailProvider);
    final playing = ref.watch(playingProvider).valueOrNull ?? false;
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_dragDx, 0),
        child: Opacity(
          opacity: (1 - (_dragDx.abs() / 200)).clamp(0.3, 1.0),
          child: Material(
            color: Colors.black.withValues(alpha: 0.92),
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 2,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: Container(color: KivoColors.gold),
                  ),
                ),
                InkWell(
                  onTap: widget.onExpand,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        _Preview(bytes: thumb),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.session.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                          onPressed: () => ref.read(playerControllerProvider).togglePlayPause(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: _close,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final Uint8List? bytes;
  const _Preview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                color: Colors.white12,
                child: const Icon(Icons.movie_outlined, color: Colors.white54, size: 20),
              ),
      ),
    );
  }
}
```

- [ ] **Step 3: Mount it in `app.dart`.** Change:

```dart
    return MaterialApp(
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.light(),
      darkTheme: KivoTheme.dark(),
      themeMode: themeModeFor(mode),
      home: const LibraryScreen(),
    );
```

to:

```dart
    return MaterialApp(
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.light(),
      darkTheme: KivoTheme.dark(),
      themeMode: themeModeFor(mode),
      home: const LibraryScreen(),
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayerBar()),
        ],
      ),
    );
```

Add the import: `import 'ui/mini_player/mini_player_bar.dart';`

- [ ] **Step 4: Write the failing test for `MiniPlayerBar`.**

Create `test/ui/mini_player/mini_player_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/device_controls_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/mini_player/mini_player_bar.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';

// A local no-op DeviceControls fake — deliberately not imported from
// player_screen_controls_test.dart to avoid coupling one test file's
// internals to another's.
class _NoopControls implements DeviceControls {
  @override Future<double> currentBrightness() async => 0.5;
  @override Future<void> setBrightness(double v) async {}
  @override Future<double> currentVolume() async => 0.5;
  @override Future<void> setSystemVolume(double v) async {}
  @override Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override Future<void> keepAwake(bool on) async {}
  @override Future<void> setImmersive(bool on) async {}
  @override Future<void> resetBrightness() async {}
  @override Stream<double> get systemVolumeStream => const Stream<double>.empty();
  @override Future<void> setVolumeKeyInterception(bool on) async {}
}

Future<ProviderContainer> _pumpBar(WidgetTester tester, {required bool minimized}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    deviceControlsProvider.overrideWithValue(_NoopControls()),
    resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(
    const VideoSession(playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0),
  );
  c.read(playerMinimizedProvider.notifier).state = minimized;

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: MiniPlayerBar())),
  ));
  await tester.pump();
  return c;
}

void main() {
  testWidgets('shows the title when minimized', (tester) async {
    await _pumpBar(tester, minimized: true);
    expect(find.text('ep1.mkv'), findsOneWidget);
  });

  testWidgets('is not hit-testable when not minimized', (tester) async {
    await _pumpBar(tester, minimized: false);
    // The close button exists in the tree (always mounted for the implicit
    // animation) but must not be tappable while hidden.
    final ignorePointer = tester.widget<IgnorePointer>(find.byType(IgnorePointer));
    expect(ignorePointer.ignoring, true);
  });

  testWidgets('tapping the close button un-minimizes', (tester) async {
    final c = await _pumpBar(tester, minimized: true);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(c.read(playerMinimizedProvider), false);
  });

  testWidgets('tapping the bar expands to PlayerScreen', (tester) async {
    await _pumpBar(tester, minimized: true);
    await tester.tap(find.text('ep1.mkv'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run the test to verify it fails, then implement/fix until it passes.**

Run: `flutter test test/ui/mini_player/mini_player_bar_test.dart -v`
Expected before Steps 2/3: FAIL (`mini_player_bar.dart` not found).
After Steps 2/3: Expected PASS.

- [ ] **Step 6: Run the full suite and analyze.**

Run: `flutter analyze` — expect "No issues found!"
Run: `flutter test` — expect all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/mini_player/mini_player_bar.dart lib/app.dart test/ui/mini_player/mini_player_bar_test.dart
git commit -m "feat: global MiniPlayerBar with freeze-frame preview, play/pause, expand, close"
```

---

## After all tasks

1. `flutter test` green, `flutter analyze` clean.
2. Whole-branch review (opus).
3. Release build to the Pixel 6: minimize via all 3 exit paths and confirm the bar appears with a reasonable preview and correct title; play/pause in the bar works without expanding; tapping the bar expands and resumes near the same position; X and swipe-lateral both close it; the bar is visible while browsing a folder, not just the main library screen; it does not interfere with the pinch/scroll gestures on the screen beneath it.
