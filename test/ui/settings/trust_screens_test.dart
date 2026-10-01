import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/core/legal/native_licenses.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import 'package:kivo_player/ui/settings/sections/privacy_section.dart';
import 'package:kivo_player/ui/settings/sections/problem_report_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  group('Reportar un problema', () {
    Future<(FakeAppInstaller, ErrorLog)> pump(WidgetTester tester) async {
      final installer = FakeAppInstaller(version: '1.20.0');
      final log =
          ErrorLog(InMemoryErrorLogStore(), appVersion: '1.20.0', androidSdk: 36);
      log.record(const KivoFailure(KivoOp.updateCheck, 'API: HTTP 403'));
      final c = ProviderContainer(overrides: [
        appInstallerProvider.overrideWithValue(installer),
        errorLogProvider.overrideWithValue(log),
      ]);
      addTearDown(c.dispose);
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpLocalized(tester, const ProblemReportScreen(),
          container: c, theme: KivoTheme.dark());
      await tester.pumpAndSettle();
      return (installer, log);
    }

    String preview(WidgetTester t) =>
        t.widget<SelectableText>(find.byKey(const Key('report-preview'))).data!;

    testWidgets('the preview shows exactly what will be sent', (tester) async {
      await pump(tester);
      final text = preview(tester);
      expect(text, contains('Kivo 1.20.0'));
      expect(text, contains('Google Pixel 6'));
      expect(text, contains('KV-601'));
      expect(text, contains('API: HTTP 403'));
    });

    testWidgets('what the user types appears in the report live',
        (tester) async {
      await pump(tester);
      await tester.enterText(
          find.byKey(const Key('report-description')), 'Se queda en negro');
      await tester.pump();
      expect(preview(tester), contains('Se queda en negro'));
    });

    testWidgets('email opens a mailto with the report; nothing else is sent',
        (tester) async {
      final (installer, _) = await pump(tester);
      expect(installer.openedUrls, isEmpty, reason: 'nothing on its own');
      await tester.tap(find.text(_l10n.reportSendEmail));
      await tester.pumpAndSettle();
      final url = installer.openedUrls.single;
      expect(url, startsWith('mailto:kevin.ccdo@gmail.com?subject='));
      expect(Uri.decodeComponent(url), contains('KV-601'));
    });

    testWidgets('GitHub opens a prefilled new issue', (tester) async {
      final (installer, _) = await pump(tester);
      await tester.tap(find.text(_l10n.reportOpenGithub));
      await tester.pumpAndSettle();
      expect(installer.openedUrls.single,
          startsWith('https://github.com/yt-kevincarrera/kivo-player/issues/new'));
    });
  });

  testWidgets('the privacy page says what leaves the phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLocalized(tester, const PrivacySection(), theme: KivoTheme.dark());
    expect(find.text(_l10n.privacyNetworkTitle), findsOneWidget);
    expect(find.text(_l10n.privacyBackupTitle), findsOneWidget);
    expect(find.text(_l10n.privacyPermissionsTitle), findsOneWidget);
  });

  test('the native libraries reach the license page', () async {
    registerNativeLicenses();
    final names = <String>{};
    await for (final e in LicenseRegistry.licenses) {
      names.addAll(e.packages);
    }
    for (final l in nativeLicenses) {
      expect(names, contains(l.name));
    }
    expect(nativeLicenses.map((l) => l.name).join(' '),
        allOf(contains('mpv'), contains('FFmpeg'), contains('libass'),
            contains('juniversalchardet')));
  });
}
