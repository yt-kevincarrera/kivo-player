import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/settings/sections/error_log_section.dart';

ErrorLog _emptyLog() =>
    ErrorLog(InMemoryErrorLogStore(), appVersion: '1.1.0', androidSdk: 28);

Widget _host(ErrorLog log) => ProviderScope(
      overrides: [errorLogProvider.overrideWithValue(log)],
      child: const MaterialApp(home: ErrorLogSection()),
    );

void main() {
  testWidgets('lists recorded failures newest first', (tester) async {
    final log = _emptyLog();
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));
    log.record(const KivoFailure(KivoOp.delete, 'permission denied'));

    await tester.pumpWidget(_host(log));

    expect(find.text('KV-301'), findsOneWidget);
    expect(find.text('KV-201'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing has failed', (tester) async {
    await tester.pumpWidget(_host(_emptyLog()));

    expect(find.text('Sin errores registrados'), findsOneWidget);
  });

  testWidgets('expanding an entry reveals its technical detail', (tester) async {
    final log = _emptyLog();
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));

    await tester.pumpWidget(_host(log));
    expect(find.textContaining('sqlite says no'), findsNothing);

    await tester.tap(find.text('KV-201'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sqlite says no'), findsOneWidget);
  });

  testWidgets('clearing empties the list', (tester) async {
    final log = _emptyLog();
    log.record(const KivoFailure(KivoOp.libraryScan, 'sqlite says no'));

    await tester.pumpWidget(_host(log));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Sin errores registrados'), findsOneWidget);
  });
}
