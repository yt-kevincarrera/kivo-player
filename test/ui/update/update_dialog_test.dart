import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_download_controller.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import 'package:kivo_player/ui/update/update_dialog.dart';
import '../../fakes/fakes.dart';

const _info = UpdateInfo(
    version: '1.1.0', tagName: 'v1.1.0', apkUrl: 'u', releaseUrl: 'r', notes: 'Novedades');

Future<ProviderContainer> _container(FakeAppInstaller installer) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    appInstallerProvider.overrideWithValue(installer),
    updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
  ]);
}

/// Pumps the dialog and returns a closer, so every test tears the dialog down
/// and the poll timer with it.
Future<Future<void> Function()> _openDialog(
    WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (b) => TextButton(
            onPressed: () => showUpdateDialog(b, _info),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () async {
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    if (nav.canPop()) nav.pop();
    await tester.pumpAndSettle();
  };
}

void main() {
  testWidgets('idle shows the notes; Descargar queues the APK and swaps in the bar',
      (tester) async {
    final installer = FakeAppInstaller(nextDownloadId: 12);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    expect(find.text('Nueva versión 1.1.0'), findsOneWidget);
    expect(find.text('Novedades'), findsOneWidget);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();

    expect(installer.enqueued.single, ('u', 'kivo-1.1.0.apk'));
    expect(find.text('Novedades'), findsNothing);
    expect(find.text('Puedes salir de Kivo: la descarga sigue.'), findsOneWidget);
    // The install button is on screen from the start, just not usable yet.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Instalar')).onPressed,
        isNull);

    await close();
  });

  testWidgets('a running download reports bytes and percentage', (tester) async {
    final installer = FakeAppInstaller()
      ..status = const DownloadProgress(DownloadStage.running,
          received: 13002342, total: 33345678);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('12,4 / 31,8 MB · 39 %'), findsOneWidget);

    await close();
  });

  testWidgets('a paused download says why instead of freezing', (tester) async {
    final installer = FakeAppInstaller()
      ..status = const DownloadProgress(DownloadStage.pausedNetwork, received: 5, total: 10);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('En pausa · esperando conexión'), findsOneWidget);
    // Still a download in progress, not a failure.
    expect(find.text('Reintentar'), findsNothing);

    await close();
  });

  testWidgets('Ocultar leaves the download alone', (tester) async {
    final installer = FakeAppInstaller();
    final c = await _container(installer);
    addTearDown(c.dispose);
    await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocultar'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva versión 1.1.0'), findsNothing);
    expect(installer.cancelled, isEmpty);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.downloading);
  });

  testWidgets('Cancelar drops the download and returns to the notes', (tester) async {
    final installer = FakeAppInstaller(nextDownloadId: 9);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(installer.cancelled.single, 9);
    expect(find.text('Novedades'), findsOneWidget);

    await close();
  });

  testWidgets('a finished download offers Instalar, which hands over the APK',
      (tester) async {
    final installer = FakeAppInstaller(nextDownloadId: 4)
      ..status = const DownloadProgress(DownloadStage.done, received: 10, total: 10);
    final c = await _container(installer);
    addTearDown(c.dispose);
    await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('Listo para instalar'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Instalar'));
    await tester.pumpAndSettle();

    expect(installer.installs.single, 4);
    // The system installer took over, so the dialog gets out of the way.
    expect(find.text('Nueva versión 1.1.0'), findsNothing);
  });

  testWidgets('a missing install permission is explained without losing the APK',
      (tester) async {
    final installer = FakeAppInstaller(
        nextDownloadId: 4, installOutcome: InstallOutcome.needsPermission)
      ..status = const DownloadProgress(DownloadStage.done, received: 10, total: 10);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Instalar'));
    await tester.pumpAndSettle();

    expect(find.text('Permite instalar apps para continuar, luego pulsa Instalar.'),
        findsOneWidget);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.ready);

    await close();
  });

  testWidgets('a failed download quotes KV-602 and offers the browser', (tester) async {
    final installer = FakeAppInstaller(nextDownloadId: -1);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('KV-602'), findsOneWidget);
    await tester.tap(find.text('Abrir en navegador'));
    await tester.pumpAndSettle();
    expect(installer.openedUrls.single, 'r');

    await close();
  });

  testWidgets('a hidden download can be re-opened and installed without a check',
      (tester) async {
    final installer = FakeAppInstaller(nextDownloadId: 4)
      ..status = const DownloadProgress(DownloadStage.done, received: 10, total: 10);
    final c = await _container(installer);
    addTearDown(c.dispose);

    // Queue it, then leave: exactly what "Ocultar" does.
    await c.read(updateDownloadProvider.notifier).start(_info);
    await c.read(updateDownloadProvider.notifier).refresh();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (b) => TextButton(
              onPressed: () => showPendingUpdateDialog(b),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No UpdateInfo, so the version has to come from what was persisted.
    expect(find.text('Nueva versión 1.1.0'), findsOneWidget);
    expect(find.text('Listo para instalar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Instalar'));
    await tester.pumpAndSettle();
    expect(installer.installs.single, 4);
  });

  testWidgets('Descartar drops a ready download and frees the slot',
      (tester) async {
    final installer = FakeAppInstaller(nextDownloadId: 4)
      ..status = const DownloadProgress(DownloadStage.done, received: 10, total: 10);
    final c = await _container(installer);
    addTearDown(c.dispose);
    final close = await _openDialog(tester, c);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    await c.read(updateDownloadProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Listo para instalar'), findsOneWidget);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    // The APK is removed and the slot is free again — the release notes are
    // back, so a newer version can be downloaded instead.
    expect(installer.cancelled.single, 4);
    expect(c.read(updateDownloadProvider).phase, DownloadPhase.idle);
    expect(find.text('Novedades'), findsOneWidget);

    await close();
  });

  testWidgets('Omitir esta versión persists the skip', (tester) async {
    final c = await _container(FakeAppInstaller());
    addTearDown(c.dispose);
    await _openDialog(tester, c);

    await tester.tap(find.text('Omitir esta versión'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).skippedUpdateVersion, '1.1.0');
  });
}
