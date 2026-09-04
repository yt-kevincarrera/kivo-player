import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/settings/sections/error_log_section.dart';
import '../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

ErrorLog _emptyLog() =>
    ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28);

Future<void> _pump(WidgetTester tester, ErrorLog log) {
  final container =
      ProviderContainer(overrides: [errorLogProvider.overrideWithValue(log)]);
  addTearDown(container.dispose);
  return pumpLocalized(tester, const ErrorLogSection(), container: container);
}

void main() {
  testWidgets('lists recorded failures newest first', (tester) async {
    final log = _emptyLog();
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));
    log.record(const KivoFailure(KivoOp.delete, 'permission denied'));

    await _pump(tester, log);

    expect(find.text('KV-301'), findsOneWidget);
    expect(find.text('KV-201'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing has failed', (tester) async {
    await _pump(tester, _emptyLog());

    expect(find.text(_l10n.settingsErrorLogEmpty), findsOneWidget);
  });

  testWidgets('expanding an entry reveals its technical detail', (tester) async {
    final log = _emptyLog();
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));

    await _pump(tester, log);
    expect(find.textContaining('sqlite says no'), findsNothing);

    await tester.tap(find.text('KV-201'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sqlite says no'), findsOneWidget);
  });

  testWidgets('clearing empties the list', (tester) async {
    final log = _emptyLog();
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));

    await _pump(tester, log);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.settingsErrorLogEmpty), findsOneWidget);
  });
}
