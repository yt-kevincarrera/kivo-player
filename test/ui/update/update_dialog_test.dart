import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/ui/update/update_dialog.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('Descargar triggers the installer; Omitir persists the skip', (tester) async {
    final installer = FakeAppInstaller(version: '1.0.0');
    final svc = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(installer),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker()),
    ]);
    addTearDown(c.dispose);
    const info = UpdateInfo(version: '1.1.0', tagName: 'v1.1.0', apkUrl: 'u', releaseUrl: 'r', notes: 'Novedades');

    late BuildContext dialogHostContext;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          return Scaffold(body: Builder(builder: (b) {
            dialogHostContext = b;
            return TextButton(
              onPressed: () => showUpdateDialog(b, ref, info),
              child: const Text('open'),
            );
          }));
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva versión 1.1.0'), findsOneWidget);
    expect(find.text('Novedades'), findsOneWidget);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();
    expect(installer.installed.single.$2, 'kivo-1.1.0.apk');
    // ignore: use_build_context_synchronously
    expect(dialogHostContext.mounted, true);
  });
}
