# Kivo — Queue Thumbnail Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A horizontal, scrollable strip of the current queue's thumbnails over the player — current one highlighted, tap to jump to any video, toggled by a queue (☰) button, remembered as a setting.

**Architecture:** The queue is the displayed-list already carried by `VideoSession` (autoplay's queue). Add per-item MediaStore ids (`queueIds`) for thumbnails and a `sessionAt(index)` builder. The strip taps set a `queueJumpProvider`; PlayerScreen (the single owner of engine-open) reuses its factored `_advance(next, countAsAutoplay:false)` to jump. Thumbnails reuse the library's `ThumbnailImage(id)`.

**Tech Stack:** Flutter/Riverpod, existing `thumbnailProvider.family(id)` (MediaStore), `KivoIcon` set.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-03-kivo-queue-strip-design.md` — authoritative.
- Queue = the displayed list already in `VideoSession` (`queue`/`queueNames`, `index`) — do NOT re-sort or re-scope.
- Strip shows only when: controls visible (it lives in the controls overlay), `queue.length > 1`, AND `queueStripVisible` (setting, default true). Hidden in PiP (the whole controls overlay is). Shown in "Solo audio".
- Tap a card → jump to that video reusing the player's open flow, and it must NOT count as an autoplay advance (no sleep "N episodes" decrement).
- Current card: gold border + "Ahora" ribbon + gold name; others dimmed with a ▶ glyph. Auto-scroll to center the current card on appear/change.
- `queueStripVisible` bool default true, all 6 KivoSettings insertion points. The ☰ button toggles it (persisted); no settings-screen UI yet.
- Reuse `ThumbnailImage(id)` / `thumbnailProvider`. Derive nothing from URIs — carry `queueIds` explicitly.
- `flutter analyze` clean + full `flutter test` green before every commit (current suite: 250).
- Do NOT build the APK mid-plan — one build at the end.

---

### Task 1: Foundations — queueIds, sessionAt, queueStripVisible, queueJumpProvider

**Files:**
- Modify: `lib/player/open/video_source.dart`
- Modify: `lib/core/settings/kivo_settings.dart`
- Create: `lib/ui/player/state/queue_strip_state.dart`
- Test: `test/player/open/video_source_queue_test.dart` (new), extend `test/player/open/video_source_next_test.dart`

**Interfaces:**
- Produces (Task 2 relies on):
  - `VideoSession.queueIds` (`List<String>`, default `const []`).
  - `CurrentVideoNotifier.sessionAt(int index)` → `VideoSession?`; `peekNext()` delegates to `sessionAt(index + 1)`.
  - `KivoSettings.queueStripVisible` (`bool`, default `true`).
  - `queueJumpProvider` (`StateProvider<int?>`) in `queue_strip_state.dart`.

- [ ] **Step 1: Write failing tests**

`test/player/open/video_source_queue_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/open/video_source.dart';

VideoItem _item(String name, String folder) => VideoItem(
    id: 'id-$name', uri: 'content://$folder/$name', name: name, folder: folder,
    durationMs: 1000, sizeBytes: 1, dateAddedMs: 0);

void main() {
  ProviderContainer makeC() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('openFromList populates queueIds parallel to queue/queueNames', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('a.mkv', 'A'), _item('b.mkv', 'A'), _item('c.mkv', 'A')];
    n.openFromList(shown[0], shown);
    final s = c.read(currentVideoProvider)!;
    expect(s.queueIds, ['id-a.mkv', 'id-b.mkv', 'id-c.mkv']);
    expect(s.queueIds.length, s.queue.length);
  });

  test('sessionAt builds any index and null out of range; carries ids/names/folder', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('a.mkv', 'A'), _item('b.mkv', 'A'), _item('c.mkv', 'A')];
    n.openFromList(shown[0], shown);
    final s2 = n.sessionAt(2)!;
    expect(s2.playbackPath, 'content://A/c.mkv');
    expect(s2.displayName, 'c.mkv');
    expect(s2.index, 2);
    expect(s2.queueIds, ['id-a.mkv', 'id-b.mkv', 'id-c.mkv']);
    expect(s2.folder, 'A');
    expect(n.sessionAt(3), isNull);
    expect(n.sessionAt(-1), isNull);
  });

  test('peekNext still works (delegates to sessionAt)', () {
    final c = makeC();
    final n = c.read(currentVideoProvider.notifier);
    final shown = [_item('a.mkv', 'A'), _item('b.mkv', 'A')];
    n.openFromList(shown[0], shown);
    expect(n.peekNext()!.playbackPath, 'content://A/b.mkv');
    n.advanceTo(n.peekNext()!);
    expect(n.peekNext(), isNull);
  });
}
```

For the settings field, add a round-trip assertion where the codebase already tests `KivoSettings` defaults/round-trip (search `test/` for `subtitlesEnabledByDefault` or `sleepTimerLastMinutes` — the shared settings test); add `expect(KivoSettings.defaults().queueStripVisible, true);` and a copyWith/toMap→fromMap round-trip there. `peekNext` behavior is unchanged, so `video_source_next_test.dart` needs no edits.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/player/open/video_source_queue_test.dart`
Expected: FAIL — `queueIds`/`sessionAt` don't exist.

- [ ] **Step 3: Implement**

`kivo_settings.dart` — add `queueStripVisible` at all 6 points (field `final bool queueStripVisible;`, ctor `required this.queueStripVisible,`, `defaults()` `queueStripVisible: true,`, copyWith param `bool? queueStripVisible,` + body `queueStripVisible: queueStripVisible ?? this.queueStripVisible,`, `toMap` `'queueStripVisible': queueStripVisible,`, `fromMap` `queueStripVisible: m['queueStripVisible'] ?? d.queueStripVisible,`). If a central settings test asserts defaults, add `expect(d.queueStripVisible, true);` there.

`video_source.dart` — add `final List<String> queueIds;` to `VideoSession` (ctor `this.queueIds = const [],`). Populate in `openFromList`:
```dart
  void openFromList(VideoItem current, List<VideoItem> shown) {
    var idx = shown.indexWhere((v) => v.uri == current.uri);
    final list = idx < 0 ? <VideoItem>[current] : shown;
    if (idx < 0) idx = 0;
    state = VideoSession(
      playbackPath: current.uri,
      displayName: current.name,
      queue: list.map((v) => v.uri).toList(),
      queueNames: list.map((v) => v.name).toList(),
      queueIds: list.map((v) => v.id).toList(),
      index: idx,
      folder: current.folder,
    );
  }
```
Replace `peekNext` + add `sessionAt`:
```dart
  /// Builds (without mutating) the session for any valid queue [index], or
  /// null if out of range. Carries the full queue (uris/names/ids) and folder.
  VideoSession? sessionAt(int index) {
    final s = state;
    if (s == null || index < 0 || index >= s.queue.length) return null;
    final name = index < s.queueNames.length ? s.queueNames[index] : basenameOf(s.queue[index]);
    final id = index < s.queueIds.length ? s.queueIds[index] : '';
    return VideoSession(
      playbackPath: s.queue[index],
      displayName: name,
      queue: s.queue,
      queueNames: s.queueNames,
      queueIds: s.queueIds,
      index: index,
      folder: s.folder,
    );
  }

  /// The next session in the queue, or null at the end.
  VideoSession? peekNext() {
    final s = state;
    return s == null ? null : sessionAt(s.index + 1);
  }
```

`lib/ui/player/state/queue_strip_state.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to the queue index the user tapped in the strip; PlayerScreen listens,
/// jumps to it (reusing the open flow, not counted as autoplay), then clears.
final queueJumpProvider = StateProvider<int?>((ref) => null);
```

- [ ] **Step 4: Run tests, analyze, full suite**

Run the queue test → PASS. `flutter analyze` → clean. `flutter test` → 250 + new (report actual).

- [ ] **Step 5: Commit**

```bash
git add lib/player/open/video_source.dart lib/core/settings/kivo_settings.dart lib/ui/player/state/queue_strip_state.dart test/player/open/video_source_queue_test.dart
git commit -m "feat: queue-strip foundations — VideoSession.queueIds, sessionAt, queueStripVisible, queueJumpProvider"
```

---

### Task 2: QueueStrip widget + ☰ toggle + PlayerScreen jump wiring

**Files:**
- Create: `lib/ui/player/queue/queue_strip.dart`
- Modify: `lib/core/icons/kivo_icons.dart` (KivoIcons.queue)
- Modify: `lib/ui/player/controls/controls_overlay.dart` (mount above BottomBar)
- Modify: `lib/ui/player/controls/bottom_bar.dart` (☰ toggle button)
- Modify: `lib/ui/player/player_screen.dart` (`_advance` gains `countAsAutoplay`; `queueJumpProvider` listener)
- Test: `test/ui/player/queue_strip_test.dart`

**Interfaces:**
- Consumes: `currentVideoProvider`/`sessionAt` (Task 1); `queueJumpProvider`; `settingsProvider.queueStripVisible`; `ThumbnailImage`/`thumbnailProvider`; `controlsVisibleProvider`; `KivoColors`.

- [ ] **Step 1: KivoIcons.queue (duotone list)**

In `kivo_icons.dart`, near the bottom-bar icons, add:
```dart
  // Queue/playlist — three list rows, the top one in the accent.
  static final String queue = _wrap(
    '<g stroke-width="2" stroke-linecap="round">'
    '<path d="M4 7 H20" stroke="$_g"/><path d="M4 12 H20" stroke="currentColor"/>'
    '<path d="M4 17 H14" stroke="currentColor"/></g>',
  );
```

- [ ] **Step 2: Create `lib/ui/player/queue/queue_strip.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/open/video_source.dart';
import '../../home/widgets/thumbnail_image.dart';
import '../state/controls_visibility.dart';
import '../state/queue_strip_state.dart';

/// Horizontal strip of the current queue's thumbnails, over the bottom bar.
/// Tap a card to jump. Auto-scrolls to the current item.
class QueueStrip extends ConsumerStatefulWidget {
  const QueueStrip({super.key});
  @override
  ConsumerState<QueueStrip> createState() => _QueueStripState();
}

class _QueueStripState extends ConsumerState<QueueStrip> {
  final _scroll = ScrollController();
  int? _centered; // last index we auto-scrolled to — don't fight manual scroll
  static const _cardW = 104.0;
  static const _gap = 10.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _centerOn(int index, double viewportW) {
    if (!_scroll.hasClients) return;
    final target = (index * (_cardW + _gap)) - (viewportW - _cardW) / 2;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(target.clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentVideoProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.queueStripVisible));
    if (session == null || session.queue.length <= 1 || !visible) {
      return const SizedBox.shrink();
    }
    final index = session.index;
    // Center ONLY when the current index changes (appear / autoplay / jump) —
    // never on every build, or it would fight the user's manual scrolling.
    if (_centered != index) {
      _centered = index;
      final w = MediaQuery.sizeOf(context).width;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(index, w));
    }
    return SizedBox(
      height: 92,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: session.queue.length,
        itemBuilder: (context, i) {
          final active = i == index;
          final id = i < session.queueIds.length ? session.queueIds[i] : '';
          final name = i < session.queueNames.length ? session.queueNames[i] : '';
          return Padding(
            padding: EdgeInsets.only(right: i == session.queue.length - 1 ? 0 : _gap),
            child: _QueueCard(
              width: _cardW,
              id: id,
              name: name,
              index: i,
              active: active,
              onTap: () {
                if (active) return;
                ref.read(queueJumpProvider.notifier).state = i;
                ref.read(controlsVisibleProvider.notifier).show();
              },
            ),
          );
        },
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  final double width;
  final String id;
  final String name;
  final int index;
  final bool active;
  final VoidCallback onTap;
  const _QueueCard({
    required this.width,
    required this.id,
    required this.name,
    required this.index,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: active ? KivoColors.gold : Colors.transparent,
                  width: 2,
                ),
                color: const Color(0xFF0C1120),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: active ? 1 : 0.62,
                    child: id.isEmpty
                        ? const ColoredBox(color: Color(0xFF1C2A44))
                        : ThumbnailImage(id, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4, left: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (active)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        color: KivoColors.gold,
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: const Text('AHORA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF231705),
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6)),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 22),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? KivoColors.gold : Colors.white.withValues(alpha: 0.6),
                fontSize: 9.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Mount in `controls_overlay.dart`**

In the bottom `Positioned` (the `SafeArea(top:false, child: BottomBar())`), replace `BottomBar()` with a Column that stacks the strip above it. Concretely, change the child of that bottom container's SafeArea from `const BottomBar()` to:
```dart
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [QueueStrip(), BottomBar()],
                        ),
```
Add `import '../queue/queue_strip.dart';`. (The strip returns `SizedBox.shrink()` when it shouldn't show, so this is inert otherwise.)

- [ ] **Step 4: ☰ toggle in `bottom_bar.dart`**

Add a queue toggle button. Place it in the toolbar Row (e.g., before the headphones button). It's always available (independent of audio-only). Reads `queueStripVisible`, gold when true:
```dart
            IconButton(
              color: ref.watch(settingsProvider.select((s) => s.queueStripVisible)) ? accent : Colors.white,
              tooltip: 'Cola',
              icon: KivoIcon(
                KivoIcons.queue,
                size: 24,
                color: ref.watch(settingsProvider.select((s) => s.queueStripVisible)) ? accent : Colors.white,
              ),
              onPressed: () {
                final s = ref.read(settingsProvider);
                ref.read(settingsProvider.notifier).set(s.copyWith(queueStripVisible: !s.queueStripVisible));
              },
            ),
```
(Import already present for KivoIcons/settings.) Note the bottom-bar Row currently has speed · lock · [aspect · rotate] · headphones. Add the ☰ button; keep it visible in audio-only too (the strip works there).

- [ ] **Step 5: PlayerScreen jump wiring**

In `player_screen.dart`:
- Change `_advance`'s signature to `Future<void> _advance(VideoSession next, {bool countAsAutoplay = true}) async {` and guard the decrement: replace `ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();` with `if (countAsAutoplay) ref.read(sleepTimerProvider.notifier).onAutoplayAdvance();`.
- Add a listener in `build()` next to the others:
```dart
    ref.listen(queueJumpProvider, (_, index) {
      if (index == null) return;
      final s = ref.read(currentVideoProvider.notifier).sessionAt(index);
      ref.read(queueJumpProvider.notifier).state = null;
      if (s != null) _advance(s, countAsAutoplay: false);
    });
```
- Add import `import 'state/queue_strip_state.dart';`.
- In `_start()`'s reset block, also clear `ref.read(queueJumpProvider.notifier).state = null;` so a stale jump can't bleed into a fresh entry.

- [ ] **Step 6: Write the widget test**

`test/ui/player/queue_strip_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/queue/queue_strip.dart';
import 'package:kivo_player/ui/player/state/queue_strip_state.dart';
import '../../fakes/fakes.dart';

const _session = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
  queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
  queueIds: ['ida', 'idb', 'idc'],
  index: 1, folder: 'A',
);

Future<ProviderContainer> _pump(WidgetTester tester, {bool visible = true, VideoSession session = _session}) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  if (!visible) await s.update(s.current.copyWith(queueStripVisible: false));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(session);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const Scaffold(body: QueueStrip())),
  ));
  await tester.pump();
  return c;
}

void main() {
  testWidgets('shows a card per queue item; tap sets queueJumpProvider', (tester) async {
    final c = await _pump(tester);
    expect(find.text('AHORA'), findsOneWidget); // the current (index 1)
    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.text('c.mkv'), findsOneWidget);
    await tester.tap(find.text('c.mkv'));
    await tester.pump();
    expect(c.read(queueJumpProvider), 2);
  });

  testWidgets('hidden when queueStripVisible is false', (tester) async {
    await _pump(tester, visible: false);
    expect(find.text('a.mkv'), findsNothing);
  });

  testWidgets('hidden for a single-item queue', (tester) async {
    await _pump(tester, session: const VideoSession(
      playbackPath: '/v/solo.mkv', displayName: 'solo.mkv',
      queue: ['/v/solo.mkv'], queueNames: ['solo.mkv'], queueIds: ['id'], index: 0,
    ));
    expect(find.text('solo.mkv'), findsNothing);
  });
}
```

- [ ] **Step 7: Run tests, analyze, full suite**

Run the strip test → PASS. `flutter analyze` → clean. `flutter test` → prior + new (report actual). If a PlayerScreen test needs adjusting for the new listener/Column, make the minimal fix and report.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/player/queue/queue_strip.dart lib/core/icons/kivo_icons.dart lib/ui/player/controls/controls_overlay.dart lib/ui/player/controls/bottom_bar.dart lib/ui/player/player_screen.dart test/ui/player/queue_strip_test.dart
git commit -m "feat: queue thumbnail strip — tap-to-jump, current highlighted, ☰ toggle"
```

---

## After all tasks

1. Whole-branch review (opus): the strip's auto-scroll (`addPostFrameCallback` every build — cheap? does it fight user scrolling?), the jump path reusing `_advance(countAsAutoplay:false)` (no sleep decrement, no double-open, cached controller), the `queueJump` not stranding across opens, `queueIds`/`sessionAt` correctness, the ☰ toggle persistence, and that the strip stays hidden in PiP (via the controls overlay) and shows in audio-only.
2. Fix Critical/Important; record Minors.
3. Build + install release, report the device checklist from spec §3.

---

## REVISION (2026-07-03, after mockup): Task 2 redesigned to "Option A"

Design change from the user: the strip is **always visible with the controls**
(no ☰ toggle, no `queueStripVisible` setting — Task 1 dropped that field), and
it's **integrated into the bottom control area**, orientation-aware:
- **Landscape:** below the seek bar, a single Row — `Expanded(QueueStrip)` on the
  left, the tool buttons clustered on the right (≈ half/half).
- **Portrait:** below the seek bar, a compact full-width QueueStrip, then the
  tool-buttons row below it.
The strip lives INSIDE `BottomBar` (not mounted separately in ControlsOverlay).
No `KivoIcons.queue`, no toggle button. Everything else (tap→queueJump, auto-scroll
to current, PlayerScreen `_advance(countAsAutoplay:false)` jump wiring) stands.
The authoritative Task-2 spec is `.superpowers/sdd/task-2-brief.md`.
