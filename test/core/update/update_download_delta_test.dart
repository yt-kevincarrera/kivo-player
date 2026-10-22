import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_download_controller.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';

import '../../fakes/fakes.dart';

const _info = UpdateInfo(
  version: '1.1.0',
  tagName: 'v1.1.0',
  apkUrl: 'https://example.com/kivo-arm64-v8a.apk',
  releaseUrl: 'https://example.com/releases/v1.1.0',
  notes: 'Update',
  manifestUrl: 'https://example.com/kivo-update-v1.json',
);

const _newer = UpdateInfo(
  version: '1.2.0',
  tagName: 'v1.2.0',
  apkUrl: 'https://example.com/newer.apk',
  releaseUrl: 'https://example.com/releases/v1.2.0',
  notes: 'Newer update',
  manifestUrl: 'https://example.com/newer-manifest.json',
);

Future<ProviderContainer> _container(FakeAppInstaller installer) async {
  final settings = await SettingsService.load(InMemorySettingsStore());
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(settings),
      appInstallerProvider.overrideWithValue(installer),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'forwards the optional manifest with the full APK fallback URL',
    () async {
      final installer = FakeAppInstaller(nextDownloadId: 42);
      final c = await _container(installer);

      await c.read(updateDownloadProvider.notifier).start(_info);

      expect(installer.enqueued, [(_info.apkUrl, 'kivo-1.1.0.apk')]);
      expect(installer.manifests, [_info.manifestUrl]);
      expect(c.read(settingsProvider).pendingUpdateDownloadId, 42);
      expect(c.read(settingsProvider).pendingUpdateVersion, '1.1.0');
    },
  );

  test(
    'preparing remains uninstalled even with every byte downloaded',
    () async {
      final entered = Completer<void>();
      final enqueued = Completer<int>();
      final installer = FakeAppInstaller(nextDownloadId: 42)
        ..onEnqueue = () {
          entered.complete();
          return enqueued.future;
        };
      final c = await _container(installer);
      final notifier = c.read(updateDownloadProvider.notifier);
      final start = notifier.start(_info);
      await entered.future;

      expect(
        c.read(updateDownloadProvider).progress.stage,
        DownloadStage.preparing,
      );
      expect(await notifier.install(), InstallOutcome.failed);
      expect(installer.installs, isEmpty);

      enqueued.complete(42);
      await start;
      installer.status = const DownloadProgress(
        DownloadStage.preparing,
        received: 100,
        total: 100,
        partial: true,
      );
      await notifier.refresh();
      final preparing = c.read(updateDownloadProvider);
      expect(preparing.phase, DownloadPhase.downloading);
      expect(preparing.progress.fraction, isNull);
      expect(preparing.progress.isSettled, isFalse);
      expect(await notifier.install(), InstallOutcome.failed);
      expect(installer.installs, isEmpty);

      installer.status = const DownloadProgress(DownloadStage.done);
      await notifier.refresh();
      expect(await notifier.install(), InstallOutcome.started);
      expect(installer.installs, [42]);
    },
  );

  test(
    'partial preparation and full fallback retain one durable job',
    () async {
      final installer = FakeAppInstaller(nextDownloadId: 42);
      final c = await _container(installer);
      final notifier = c.read(updateDownloadProvider.notifier);
      await notifier.start(_info);

      for (final progress in const [
        DownloadProgress(DownloadStage.running, partial: true),
        DownloadProgress(DownloadStage.preparing, partial: true),
        DownloadProgress(DownloadStage.running, fallback: true),
        DownloadProgress(DownloadStage.preparing, fallback: true),
        DownloadProgress(DownloadStage.done, fallback: true),
      ]) {
        installer.status = progress;
        await notifier.refresh();
        expect(c.read(updateDownloadProvider).downloadId, 42);
        expect(c.read(updateDownloadProvider).progress, progress);
        expect(c.read(settingsProvider).pendingUpdateDownloadId, 42);
      }

      expect(installer.enqueued, hasLength(1));
      expect(installer.cancelled, isEmpty);
      expect(c.read(updateDownloadProvider).phase, DownloadPhase.ready);
      expect(await notifier.install(), InstallOutcome.started);
      expect(installer.installs, [42]);
    },
  );

  test('recovers native work when Dart never persisted the handle', () async {
    final installer = FakeAppInstaller(nextDownloadId: 21)
      ..pending = const PendingUpdate(21, '1.1.0')
      ..status = const DownloadProgress(DownloadStage.preparing, partial: true);
    final c = await _container(installer);

    expect(c.read(settingsProvider).pendingUpdateDownloadId, -1);
    c.read(updateDownloadProvider);
    await Future<void>.delayed(Duration.zero);

    final recovered = c.read(updateDownloadProvider);
    expect(recovered.phase, DownloadPhase.downloading);
    expect(recovered.downloadId, 21);
    expect(recovered.version, '1.1.0');
    expect(recovered.progress.stage, DownloadStage.preparing);
    expect(recovered.progress.partial, isTrue);
    expect(c.read(settingsProvider).pendingUpdateDownloadId, 21);
    expect(c.read(settingsProvider).pendingUpdateVersion, '1.1.0');
    expect(installer.enqueued, isEmpty);
    expect(installer.installs, isEmpty);
  });

  test(
    'cancelling while enqueue waits removes the late native handle',
    () async {
      final entered = Completer<void>();
      final enqueued = Completer<int>();
      final installer = FakeAppInstaller()
        ..onEnqueue = () {
          entered.complete();
          return enqueued.future;
        };
      final c = await _container(installer);
      final notifier = c.read(updateDownloadProvider.notifier);
      final start = notifier.start(_info);
      await entered.future;

      await notifier.cancel();
      enqueued.complete(17);
      await start;

      expect(installer.cancelled, [17]);
      expect(c.read(updateDownloadProvider).phase, DownloadPhase.idle);
      expect(c.read(settingsProvider).pendingUpdateDownloadId, -1);
      expect(c.read(settingsProvider).pendingUpdateVersion, isNull);
    },
  );

  test('double taps during async enqueue create only one native job', () async {
    final entered = Completer<void>();
    final enqueued = Completer<int>();
    final installer = FakeAppInstaller()
      ..onEnqueue = () {
        entered.complete();
        return enqueued.future;
      };
    final c = await _container(installer);
    final notifier = c.read(updateDownloadProvider.notifier);
    final start = notifier.start(_info);
    await entered.future;

    await notifier.start(_info);
    expect(installer.enqueued, hasLength(1));
    enqueued.complete(17);
    await start;
    expect(c.read(updateDownloadProvider).downloadId, 17);
  });

  test(
    'disposing during enqueue still removes the late native handle',
    () async {
      final entered = Completer<void>();
      final enqueued = Completer<int>();
      final installer = FakeAppInstaller()
        ..onEnqueue = () {
          entered.complete();
          return enqueued.future;
        };
      final settings = await SettingsService.load(InMemorySettingsStore());
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(settings),
          appInstallerProvider.overrideWithValue(installer),
        ],
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) c.dispose();
      });
      final start = c.read(updateDownloadProvider.notifier).start(_info);
      await entered.future;

      c.dispose();
      disposed = true;
      enqueued.complete(17);
      await expectLater(start, completes);
      expect(installer.cancelled, [17]);
    },
  );

  test('a superseded late enqueue cannot replace the new version', () async {
    final entered = Completer<void>();
    final oldEnqueue = Completer<int>();
    final installer = FakeAppInstaller()
      ..onEnqueue = () {
        entered.complete();
        return oldEnqueue.future;
      };
    final c = await _container(installer);
    final notifier = c.read(updateDownloadProvider.notifier);
    final oldStart = notifier.start(_info);
    await entered.future;
    await notifier.cancel();

    installer.onEnqueue = () async => 29;
    await notifier.start(_newer);
    oldEnqueue.complete(17);
    await oldStart;

    expect(installer.cancelled, [17]);
    expect(c.read(updateDownloadProvider).downloadId, 29);
    expect(c.read(updateDownloadProvider).version, '1.2.0');
    expect(c.read(settingsProvider).pendingUpdateDownloadId, 29);
    expect(c.read(settingsProvider).pendingUpdateVersion, '1.2.0');
  });

  for (final supersede in [false, true]) {
    test(
      'late ready status cannot ${supersede ? 'overwrite a new job' : 'undo cancellation'}',
      () async {
        final installer = FakeAppInstaller(nextDownloadId: 17);
        final c = await _container(installer);
        final notifier = c.read(updateDownloadProvider.notifier);
        await notifier.start(_info);
        final entered = Completer<void>();
        final oldStatus = Completer<DownloadProgress>();
        installer.onStatus = () {
          entered.complete();
          return oldStatus.future;
        };
        final refresh = notifier.refresh();
        await entered.future;

        if (supersede) {
          installer.nextDownloadId = 29;
          await notifier.start(_newer);
        } else {
          await notifier.cancel();
        }
        oldStatus.complete(const DownloadProgress(DownloadStage.done));
        await refresh;

        final state = c.read(updateDownloadProvider);
        expect(
          state.phase,
          supersede ? DownloadPhase.downloading : DownloadPhase.idle,
        );
        expect(state.downloadId, supersede ? 29 : -1);
        expect(
          c.read(settingsProvider).pendingUpdateDownloadId,
          supersede ? 29 : -1,
        );
        expect(installer.cancelled, [17]);
        expect(installer.installs, isEmpty);
      },
    );
  }
}
