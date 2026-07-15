import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/navigation.dart';
import 'package:kivo_player/ui/update/update_dialog.dart';
import '../fakes/fakes.dart';

// Minimal host that reproduces KivoApp's post-frame auto-check without the full
// widget tree (HomeShell needs many providers). Verifies the check + dialog.
void main() {
  testWidgets('auto-check shows the dialog when enabled, throttle elapsed, update available', (tester) async {
    final svc = await SettingsService.load(InMemorySettingsStore());
    // enabled by default, lastUpdateCheckMs=0 → throttle elapsed
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      appInstallerProvider.overrideWithValue(FakeAppInstaller(version: '1.0.0')),
      updateCheckerProvider.overrideWithValue(FakeUpdateChecker(
        result: const UpdateInfo(version: '1.1.0', tagName: 'v1.1.0', apkUrl: 'u', releaseUrl: 'r', notes: 'x'))),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: kivoNavigatorKey,
        home: Consumer(builder: (ctx, ref, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final r = await ref.read(updateControllerProvider).check();
            final c2 = kivoNavigatorKey.currentContext;
            if (r.status == UpdateStatus.available && c2 != null) {
              showUpdateDialog(c2, ref, r.info!);
            }
          });
          return const Scaffold(body: SizedBox());
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nueva versión 1.1.0'), findsOneWidget);
  });
}
