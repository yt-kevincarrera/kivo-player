import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/core/update/update_download_controller.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import 'package:kivo_player/ui/update/update_dialog.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _info = UpdateInfo(
  version: '1.1.0',
  tagName: 'v1.1.0',
  apkUrl: 'u',
  releaseUrl: 'r',
  notes: 'Novedades',
);

Future<ProviderContainer> _container(FakeAppInstaller installer) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(installer),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ],
  );
}

/// Pumps the dialog and returns a closer, so every test tears the dialog down
/// and the poll timer with it.
Future<Future<void> Function()> _openDialog(
  WidgetTester tester,
  ProviderContainer c, {
  UpdateInfo info = _info,
  Locale locale = const Locale('es'),
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpLocalized(
    tester,
    Scaffold(
      body: Builder(
        builder: (b) => TextButton(
          onPressed: () => showUpdateDialog(b, info),
          child: const Text('open'),
        ),
      ),
    ),
    container: c,
    locale: locale,
    theme: theme,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () async {
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    if (nav.canPop()) nav.pop();
    await tester.pumpAndSettle();
  };
}

void main() {
  testWidgets(
    'size discovery does not enqueue and waits for a compatible partial plan',
    (tester) async {
      final pending = Completer<UpdatePreview?>();
      final installer = FakeAppInstaller()..onPreview = () => pending.future;
      final c = await _container(installer);
      addTearDown(c.dispose);
      const info = UpdateInfo(
        version: '1.1.0',
        tagName: 'v1.1.0',
        apkUrl: 'u',
        releaseUrl: 'r',
        notes: 'Novedades',
        manifestUrl: 'manifest',
        apkSizeBytes: 35 * 1000000,
      );
      final close = await _openDialog(tester, c, info: info);
      final download = find.widgetWithText(
        FilledButton,
        _l10n.updateDownloadAction,
      );
      expect(find.text(_l10n.updateSizeChecking), findsOneWidget);
      expect(tester.widget<FilledButton>(download).onPressed, isNull);
      expect(installer.previewRequests, [('u', 'manifest')]);
      expect(installer.enqueued, isEmpty);
      expect(c.read(updateDownloadProvider).phase, DownloadPhase.idle);

      pending.complete(
        const UpdatePreview(
          bytes: 3 * 1000000,
          fullBytes: 35 * 1000000,
          partial: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(_l10n.updatePartialDownloadSize('3 MB')),
        findsOneWidget,
      );
      expect(
        find.text(_l10n.updateFullDownloadAlternative('35 MB')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
      expect(installer.enqueued, isEmpty);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(installer.enqueued.single, ('u', 'kivo-1.1.0.apk'));
      expect(find.byKey(const Key('update-size-preview')), findsNothing);
      await close();
    },
  );

  testWidgets(
    'a confirmed full plan shows its exact size without a decimal suffix',
    (tester) async {
      final installer = FakeAppInstaller()
        ..preview = const UpdatePreview(
          bytes: 32 * 1000000,
          fullBytes: 32 * 1000000,
        );
      final c = await _container(installer);
      addTearDown(c.dispose);
      final close = await _openDialog(tester, c);
      expect(find.text(_l10n.updateFullDownloadSize('32 MB')), findsOneWidget);
      expect(find.textContaining('32,0'), findsNothing);
      expect(find.textContaining('Si hace falta'), findsNothing);
      expect(installer.enqueued, isEmpty);
      await close();
    },
  );

  for (final throwsError in [false, true]) {
    testWidgets(
      '${throwsError ? 'failed' : 'unavailable'} preview uses the APK size only as an upper bound',
      (tester) async {
        final installer = FakeAppInstaller();
        if (throwsError) {
          installer.onPreview = () async =>
              throw StateError('preview unavailable');
        }
        final c = await _container(installer);
        addTearDown(c.dispose);
        const info = UpdateInfo(
          version: '1.1.0',
          tagName: 'v1.1.0',
          apkUrl: 'u',
          releaseUrl: 'r',
          notes: 'Novedades',
          apkSizeBytes: 32 * 1000000,
        );
        final close = await _openDialog(tester, c, info: info);
        expect(
          find.text(_l10n.updateDownloadSizeUpperBound('32 MB')),
          findsOneWidget,
        );
        expect(find.text(_l10n.updateFullDownloadSize('32 MB')), findsNothing);
        final download = find.widgetWithText(
          FilledButton,
          _l10n.updateDownloadAction,
        );
        expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
        expect(installer.enqueued, isEmpty);
        await close();
      },
    );
  }

  testWidgets('an unknown size stays honest and allows downloading', (
    tester,
  ) async {
    final installer = FakeAppInstaller();
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);
    expect(find.text(_l10n.updateSizeUnavailable), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, _l10n.updateDownloadAction),
          )
          .onPressed,
      isNotNull,
    );
    expect(installer.enqueued, isEmpty);
    await close();
  });

  testWidgets('a full size without selected bytes stays an upper bound', (
    tester,
  ) async {
    final installer = FakeAppInstaller()
      ..preview = const UpdatePreview(fullBytes: 35000000, partial: true);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);
    expect(
      find.text(_l10n.updateDownloadSizeUpperBound('35 MB')),
      findsOneWidget,
    );
    expect(find.text(_l10n.updatePartialDownloadSize('35 MB')), findsNothing);
    expect(
      find.text(_l10n.updateFullDownloadAlternative('35 MB')),
      findsNothing,
    );
    await close();
  });

  testWidgets('the size is visible before a long changelog without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final installer = FakeAppInstaller()
      ..preview = const UpdatePreview(
        bytes: 690795,
        fullBytes: 35076444,
        partial: true,
      );
    final c = await _container(installer);
    addTearDown(c.dispose);
    final info = UpdateInfo(
      version: '1.1.0',
      tagName: 'v1.1.0',
      apkUrl: 'u',
      releaseUrl: 'r',
      notes: List.filled(
        30,
        '- Mejora de reproducción y biblioteca.',
      ).join('\n'),
    );
    final close = await _openDialog(tester, c, info: info);
    final selected = find.text(_l10n.updatePartialDownloadSize('690,8 KB'));
    final full = find.text(_l10n.updateFullDownloadAlternative('35,1 MB'));
    expect(selected.hitTestable(), findsOneWidget);
    expect(full.hitTestable(), findsOneWidget);
    final notes = find.textContaining('Mejora de reproducción y biblioteca.');
    expect(
      tester.getTopLeft(selected).dy,
      lessThan(tester.getTopLeft(notes).dy),
    );
    expect(installer.enqueued, isEmpty);
    await close();
  });

  testWidgets('closing before the size arrives ignores the late response', (
    tester,
  ) async {
    final pending = Completer<UpdatePreview?>();
    final installer = FakeAppInstaller()..onPreview = () => pending.future;
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);
    await close();
    pending.complete(const UpdatePreview(bytes: 1000000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(installer.enqueued, isEmpty);
    expect(installer.installs, isEmpty);
  });

  testWidgets('a resumed download ignores a preview that finishes late', (
    tester,
  ) async {
    final pending = Completer<UpdatePreview?>();
    final installer = FakeAppInstaller()..onPreview = () => pending.future;
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);
    await c.read(updateDownloadProvider.notifier).start(_info);
    await tester.pump();
    pending.complete(const UpdatePreview(bytes: 1000000, partial: true));
    await tester.pumpAndSettle();
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.downloading);
    expect(find.byKey(const Key('update-size-preview')), findsNothing);
    expect(installer.enqueued, hasLength(1));
    expect(tester.takeException(), isNull);
    await close();
  });

  testWidgets('a dialog opened on an active transfer skips size discovery', (
    tester,
  ) async {
    final installer = FakeAppInstaller();
    final c = await _container(installer);
    addTearDown(c.dispose);
    await c.read(updateDownloadProvider.notifier).start(_info);
    final close = await _openDialog(tester, c);
    expect(installer.previewRequests, isEmpty);
    expect(find.byKey(const Key('update-size-preview')), findsNothing);
    await close();
  });

  testWidgets(
    'browser-only updates do not request a size or block their action',
    (tester) async {
      final installer = FakeAppInstaller();
      final c = await _container(installer);
      addTearDown(c.dispose);
      const info = UpdateInfo(
        version: '1.1.0',
        tagName: 'v1.1.0',
        apkUrl: null,
        releaseUrl: 'r',
        notes: 'Novedades',
      );
      final close = await _openDialog(tester, c, info: info);
      expect(installer.previewRequests, isEmpty);
      expect(find.byKey(const Key('update-size-preview')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                _l10n.updateOpenInBrowserAction,
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(installer.enqueued, isEmpty);
      await close();
    },
  );

  for (final language in ['es', 'en']) {
    testWidgets(
      '$language uses localized KB and MB without fixed decimal punctuation',
      (tester) async {
        final locale = Locale(language);
        final l10n = l10nFor(locale);
        final installer = FakeAppInstaller()
          ..preview = const UpdatePreview(
            bytes: 1500,
            fullBytes: 35 * 1000000 + 500000,
            partial: true,
          );
        final c = await _container(installer);
        addTearDown(c.dispose);
        final close = await _openDialog(tester, c, locale: locale);
        expect(
          find.text(
            l10n.updatePartialDownloadSize(
              language == 'es' ? '1,5 KB' : '1.5 KB',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            l10n.updateFullDownloadAlternative(
              language == 'es' ? '35,5 MB' : '35.5 MB',
            ),
          ),
          findsOneWidget,
        );
        await close();
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: size and actions fit 320px with 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final installer = FakeAppInstaller()
        ..preview = const UpdatePreview(
          bytes: 3 * 1000000,
          fullBytes: 35 * 1000000,
          partial: true,
        );
      final c = await _container(installer);
      addTearDown(c.dispose);
      final close = await _openDialog(
        tester,
        c,
        theme: brightness == Brightness.light
            ? KivoTheme.light()
            : KivoTheme.dark(),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final preview = find.byKey(const Key('update-size-preview'));
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      expect(
        find.text(_l10n.updatePartialDownloadSize('3 MB')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text(_l10n.updateFullDownloadAlternative('35 MB')).hitTestable(),
        findsOneWidget,
      );
      final download = find.widgetWithText(
        FilledButton,
        _l10n.updateDownloadAction,
      );
      expect(download.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await close();
    });
  }

  testWidgets(
    'idle shows the notes; Descargar queues the APK and swaps in the bar',
    (tester) async {
      final installer = FakeAppInstaller(nextDownloadId: 12);
      final c = await _container(installer);
      addTearDown(c.dispose);
      final close = await _openDialog(tester, c);

      expect(find.text(_l10n.updateTitleWithVersion('1.1.0')), findsOneWidget);
      expect(find.text('Novedades'), findsOneWidget);

      await tester.tap(find.text(_l10n.updateDownloadAction));
      await tester.pumpAndSettle();

      expect(installer.enqueued.single, ('u', 'kivo-1.1.0.apk'));
      expect(find.text('Novedades'), findsNothing);
      expect(find.text(_l10n.updateCanLeaveHint), findsOneWidget);
      // The install button is on screen from the start, just not usable yet.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, _l10n.updateInstallAction),
            )
            .onPressed,
        isNull,
      );

      await close();
    },
  );

  testWidgets('a running download reports bytes and percentage', (
    tester,
  ) async {
    final installer = FakeAppInstaller()
      ..status = const DownloadProgress(
        DownloadStage.running,
        received: 13002342,
        total: 33345678,
      );
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(
      find.text(_l10n.updateStatusSizePercent('13 / 33,3 MB', 39)),
      findsOneWidget,
    );

    await close();
  });

  testWidgets('a paused download says why instead of freezing', (tester) async {
    final installer = FakeAppInstaller()
      ..status = const DownloadProgress(
        DownloadStage.pausedNetwork,
        received: 5,
        total: 10,
      );
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text(_l10n.updateStatusPausedNetwork), findsOneWidget);
    // Still a download in progress, not a failure.
    expect(find.text(_l10n.updateRetryAction), findsNothing);

    await close();
  });

  testWidgets('Ocultar leaves the download alone', (tester) async {
    final installer = FakeAppInstaller();
    final c = await _container(installer);
    addTearDown(c.dispose);
    await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.updateHideAction));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.updateTitleWithVersion('1.1.0')), findsNothing);
    expect(installer.cancelled, isEmpty);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.downloading);
  });

  testWidgets('Cancelar drops the download and returns to the notes', (
    tester,
  ) async {
    final installer = FakeAppInstaller(nextDownloadId: 9);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(installer.cancelled.single, 9);
    expect(find.text('Novedades'), findsOneWidget);

    await close();
  });

  testWidgets('a finished download offers Instalar, which hands over the APK', (
    tester,
  ) async {
    final installer = FakeAppInstaller(nextDownloadId: 4)
      ..status = const DownloadProgress(
        DownloadStage.done,
        received: 10,
        total: 10,
      );
    final c = await _container(installer);
    addTearDown(c.dispose);
    await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text(_l10n.updateReadyCaption), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, _l10n.updateInstallAction),
    );
    await tester.pumpAndSettle();

    expect(installer.installs.single, 4);
    // The system installer took over, so the dialog gets out of the way.
    expect(find.text(_l10n.updateTitleWithVersion('1.1.0')), findsNothing);
  });

  testWidgets(
    'a missing install permission is explained without losing the APK',
    (tester) async {
      final installer =
          FakeAppInstaller(
              nextDownloadId: 4,
              installOutcome: InstallOutcome.needsPermission,
            )
            ..status = const DownloadProgress(
              DownloadStage.done,
              received: 10,
              total: 10,
            );
      final c = await _container(installer);
      addTearDown(c.dispose);
      final close = await _openDialog(tester, c);

      await tester.tap(find.text(_l10n.updateDownloadAction));
      await tester.pumpAndSettle();
      await c.read(updateDownloadProvider.notifier).refresh();
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, _l10n.updateInstallAction),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(_l10n.updateInstallNeedsPermissionSnackbar),
        findsOneWidget,
      );
      expect(c.read(updateDownloadProvider).phase, DownloadPhase.ready);

      await close();
    },
  );

  testWidgets('a failed download quotes KV-602 and offers the browser', (
    tester,
  ) async {
    final installer = FakeAppInstaller(nextDownloadId: -1);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();

    expect(find.textContaining('KV-602'), findsOneWidget);
    await tester.tap(find.text(_l10n.updateOpenInBrowserAction));
    await tester.pumpAndSettle();
    expect(installer.openedUrls.single, 'r');

    await close();
  });

  testWidgets(
    'a hidden download can be re-opened and installed without a check',
    (tester) async {
      final installer = FakeAppInstaller(nextDownloadId: 4)
        ..status = const DownloadProgress(
          DownloadStage.done,
          received: 10,
          total: 10,
        );
      final c = await _container(installer);
      addTearDown(c.dispose);

      // Queue it, then leave: exactly what "Ocultar" does.
      await c.read(updateDownloadProvider.notifier).start(_info);
      await c.read(updateDownloadProvider.notifier).refresh();

      await pumpLocalized(
        tester,
        Scaffold(
          body: Builder(
            builder: (b) => TextButton(
              onPressed: () => showPendingUpdateDialog(b),
              child: const Text('open'),
            ),
          ),
        ),
        container: c,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No UpdateInfo, so the version has to come from what was persisted.
      expect(find.text(_l10n.updateTitleWithVersion('1.1.0')), findsOneWidget);
      expect(find.text(_l10n.updateReadyCaption), findsOneWidget);
      expect(installer.previewRequests, isEmpty);

      await tester.tap(
        find.widgetWithText(FilledButton, _l10n.updateInstallAction),
      );
      await tester.pumpAndSettle();
      expect(installer.installs.single, 4);
    },
  );

  testWidgets('Descartar drops a ready download and frees the slot', (
    tester,
  ) async {
    final installer = FakeAppInstaller(nextDownloadId: 4)
      ..status = const DownloadProgress(
        DownloadStage.done,
        received: 10,
        total: 10,
      );
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateDownloadAction));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text(_l10n.updateReadyCaption), findsOneWidget);

    await tester.tap(find.text(_l10n.updateDiscardReadyAction));
    await tester.pumpAndSettle();

    // The APK is removed and the slot is free again — the release notes are
    // back, so a newer version can be downloaded instead.
    expect(installer.cancelled.single, 4);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.idle);
    expect(find.text('Novedades'), findsOneWidget);

    await close();
  });

  testWidgets(
    'preparing explains verification and cannot install until native completion',
    (tester) async {
      final installer = FakeAppInstaller(nextDownloadId: 42)
        ..status = const DownloadProgress(
          DownloadStage.preparing,
          received: 100,
          total: 100,
          partial: true,
        );
      final c = await _container(installer);
      addTearDown(c.dispose);
      final close = await _openDialog(tester, c);

      await tester.tap(find.text(_l10n.updateDownloadAction));
      await tester.pump();
      await c.read(updateDownloadProvider.notifier).refresh();
      await tester.pump();

      expect(find.text(_l10n.updateStatusPreparing), findsOneWidget);
      expect(find.text(_l10n.updatePreparingHint), findsOneWidget);
      expect(find.text(_l10n.updatePartialDownloadHint), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final install = find.widgetWithText(
        FilledButton,
        _l10n.updateInstallAction,
      );
      expect(tester.widget<FilledButton>(install).onPressed, isNull);
      expect(installer.installs, isEmpty);

      installer.status = const DownloadProgress(DownloadStage.done);
      await c.read(updateDownloadProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.text(_l10n.updateReadyCaption), findsOneWidget);
      expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
      await tester.tap(install);
      await tester.pumpAndSettle();
      expect(installer.installs, [42]);
      await close();
    },
  );

  for (final fallback in [false, true]) {
    testWidgets(
      '${fallback ? 'full fallback' : 'partial download'} explains the current transfer',
      (tester) async {
        final installer = FakeAppInstaller()
          ..status = DownloadProgress(
            DownloadStage.running,
            received: 25,
            total: 100,
            partial: !fallback,
            fallback: fallback,
          );
        final c = await _container(installer);
        addTearDown(c.dispose);
        final close = await _openDialog(tester, c);

        await tester.tap(find.text(_l10n.updateDownloadAction));
        await tester.pump();
        await c.read(updateDownloadProvider.notifier).refresh();
        await tester.pumpAndSettle();

        expect(
          find.text(
            fallback
                ? _l10n.updateFullDownloadFallbackHint
                : _l10n.updatePartialDownloadHint,
          ),
          findsOneWidget,
        );
        expect(find.text(_l10n.updateCanLeaveHint), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, _l10n.updateInstallAction),
              )
              .onPressed,
          isNull,
        );
        expect(installer.installs, isEmpty);
        await close();
      },
    );
  }

  testWidgets('Omitir esta versión persists the skip', (tester) async {
    final c = await _container(FakeAppInstaller());
    addTearDown(c.dispose);
    await _openDialog(tester, c);

    await tester.tap(find.text(_l10n.updateSkipVersionAction));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).skippedUpdateVersion, '1.1.0');
  });
}
