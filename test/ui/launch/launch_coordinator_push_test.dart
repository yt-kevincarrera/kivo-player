import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/launcher_bridge_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/continue_watching.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/launch/launch_coordinator.dart';
import '../../fakes/fakes.dart';

class _Granted implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

class _SlowIndexer implements MediaIndexer {
  final done = Completer<List<VideoItem>>();
  @override
  Future<List<VideoItem>> scan() => done.future;
  @override
  Future<Uint8List?> thumbnail(String id) async => null;
}

VideoItem _v(String n) => VideoItem(
    id: n,
    uri: 'content://$n',
    name: n,
    folder: 'F',
    durationMs: 100000,
    sizeBytes: 1,
    dateAddedMs: 0);

void main() {
  test('what is in progress reaches the shortcuts/widget, once per change',
      () async {
    final store = InMemoryResumeStore();
    await store.put('a.mp4', 30, 100);
    final bridge = FakeLauncherBridge();
    final settingsSvc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settingsSvc),
      mediaPermissionImplProvider.overrideWithValue(_Granted()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_v('a.mp4')])),
      resumeServiceProvider.overrideWithValue(ResumeService(store)),
      launcherBridgeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);

    await c.read(launchCoordinatorProvider).start();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(bridge.updates, hasLength(1));
    expect(bridge.updates.single.single.name, 'a.mp4');
    expect(bridge.updates.single.single.position, '00:30');

    // Recomputed without a change: not sent again.
    c.invalidate(continueWatchingProvider);
    c.read(continueWatchingProvider);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(bridge.updates, hasLength(1));
  });

  // The list is empty while the library scans: that must not wipe the
  // shortcuts and the widget on every start.
  test('nothing is sent while the library is still loading', () async {
    final store = InMemoryResumeStore();
    await store.put('a.mp4', 30, 100);
    final bridge = FakeLauncherBridge();
    final indexer = _SlowIndexer();
    final settingsSvc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settingsSvc),
      mediaPermissionImplProvider.overrideWithValue(_Granted()),
      mediaIndexerProvider.overrideWithValue(indexer),
      resumeServiceProvider.overrideWithValue(ResumeService(store)),
      launcherBridgeProvider.overrideWithValue(bridge),
    ]);
    addTearDown(c.dispose);

    await c.read(launchCoordinatorProvider).start();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(bridge.updates, isEmpty);

    indexer.done.complete([_v('a.mp4')]);
    await c.read(mediaIndexProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(bridge.updates, hasLength(1));
    expect(bridge.updates.single.single.name, 'a.mp4');
  });

  test('without a launcher bridge the app still starts', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(launchCoordinatorProvider).start(); // no throw
  });
}
