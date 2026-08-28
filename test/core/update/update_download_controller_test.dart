import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_download_controller.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import '../../fakes/fakes.dart';

const _info = UpdateInfo(
    version: '1.1.0', tagName: 'v1.1.0', apkUrl: 'https://x/kivo.apk', releaseUrl: 'r', notes: 'n');

Future<ProviderContainer> _c(FakeAppInstaller installer, {Map<String, dynamic>? seed}) async {
  final store = InMemorySettingsStore();
  if (seed != null) await store.write(seed);
  final svc = await SettingsService.load(store);
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    appInstallerProvider.overrideWithValue(installer),
  ]);
}

void main() {
  test('start queues the APK under a versioned name and persists the id', () async {
    final installer = FakeAppInstaller(nextDownloadId: 42);
    final c = await _c(installer);
    addTearDown(c.dispose);

    await c.read(updateDownloadProvider.notifier).start(_info);

    expect(installer.enqueued.single, ('https://x/kivo.apk', 'kivo-1.1.0.apk'));
    final st = c.read(updateDownloadProvider);
    expect(st.phase, DownloadPhase.downloading);
    expect(st.downloadId, 42);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, 42);
    expect(c.read(settingsProvider).pendingUpdateVersion, '1.1.0');
  });

  test('a refused queue fails instead of pretending to download', () async {
    final c = await _c(FakeAppInstaller(nextDownloadId: -1));
    addTearDown(c.dispose);

    await c.read(updateDownloadProvider.notifier).start(_info);

    expect(c.read(updateDownloadProvider).phase, DownloadPhase.failed);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, -1);
  });

  test('refresh carries progress through, and a paused download stays visible', () async {
    final installer = FakeAppInstaller()
      ..status = const DownloadProgress(DownloadStage.running, received: 25, total: 100);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    await dl.refresh();
    expect(c.read(updateDownloadProvider).progress.fraction, 0.25);

    installer.status = const DownloadProgress(DownloadStage.pausedNetwork, received: 25, total: 100);
    await dl.refresh();
    final st = c.read(updateDownloadProvider);
    // Still "downloading": the system parked it, it did not die.
    expect(st.phase, DownloadPhase.downloading);
    expect(st.progress.stage, DownloadStage.pausedNetwork);
    expect(st.progress.isPaused, true);
  });

  test('a finished download becomes ready to install', () async {
    final installer = FakeAppInstaller()
      ..status = const DownloadProgress(DownloadStage.done, received: 100, total: 100);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    await dl.refresh();

    expect(c.read(updateDownloadProvider).phase, DownloadPhase.ready);
    expect(await dl.install(), InstallOutcome.started);
    expect(installer.installs.single, installer.nextDownloadId);
  });

  test('install only runs once the APK is on disk', () async {
    final installer = FakeAppInstaller();
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info); // still downloading
    expect(await dl.install(), InstallOutcome.failed);
    expect(installer.installs, isEmpty);
  });

  test('a failed download reports KV-602 and drops the id', () async {
    final installer = FakeAppInstaller()..status = const DownloadProgress(DownloadStage.failed);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    await dl.refresh();

    expect(c.read(updateDownloadProvider).phase, DownloadPhase.failed);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, -1);
  });

  test('a download cleared outside the app is forgotten, not reported', () async {
    final installer = FakeAppInstaller()..status = DownloadProgress.gone;
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    installer.nextDownloadId = 999; // the fake now denies knowing the old id
    await dl.refresh();

    expect(c.read(updateDownloadProvider).phase, DownloadPhase.idle);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, -1);
  });

  test('a failed install keeps the APK so retry does not re-download', () async {
    final installer = FakeAppInstaller(installOutcome: InstallOutcome.failed)
      ..status = const DownloadProgress(DownloadStage.done, received: 100, total: 100);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    await dl.refresh();
    await dl.install();
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.failed);
    expect(c.read(updateDownloadProvider).downloadId, installer.nextDownloadId);

    installer.installOutcome = InstallOutcome.started;
    expect(await dl.retry(_info), InstallOutcome.started);
    expect(installer.enqueued.length, 1); // no second download
  });

  test('retry re-downloads when there is no APK to install', () async {
    final installer = FakeAppInstaller(nextDownloadId: -1);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.failed);

    installer.nextDownloadId = 3;
    expect(await dl.retry(_info), isNull);
    expect(installer.enqueued.length, 2);
    expect(c.read(updateDownloadProvider).downloadId, 3);
  });

  test('cancel removes the download and clears what was persisted', () async {
    final installer = FakeAppInstaller(nextDownloadId: 8);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    await dl.cancel();

    expect(installer.cancelled.single, 8);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.idle);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, -1);
  });

  test('re-attaches on launch to a download that outlived the process', () async {
    final installer = FakeAppInstaller(nextDownloadId: 5)
      ..status = const DownloadProgress(DownloadStage.done, received: 100, total: 100);
    final c = await _c(installer,
        seed: {'pendingUpdateDownloadId': 5, 'pendingUpdateVersion': '1.1.0'});
    addTearDown(c.dispose);

    // Before the first refresh it must not read as idle, or the UI would
    // invite the user to queue the same APK a second time.
    final initial = c.read(updateDownloadProvider);
    expect(initial.phase, DownloadPhase.downloading);
    expect(initial.downloadId, 5);
    expect(initial.version, '1.1.0');

    await c.read(updateDownloadProvider.notifier).refresh();
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.ready);
  });

  test('starting a new download drops the previous one', () async {
    final installer = FakeAppInstaller(nextDownloadId: 1);
    final c = await _c(installer);
    addTearDown(c.dispose);
    final dl = c.read(updateDownloadProvider.notifier);

    await dl.start(_info);
    installer.nextDownloadId = 2;
    await dl.start(_info);

    expect(c.read(updateDownloadProvider).downloadId, 2);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, 2);
  });
}
