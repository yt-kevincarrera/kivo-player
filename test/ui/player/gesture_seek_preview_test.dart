import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/ui/player/seek/gesture_seek_preview.dart';
import 'package:kivo_player/ui/player/seek/seek_preview.dart';
import '../../fakes/fakes.dart';

final _png = Uint8List.fromList(
  // 1x1 transparent PNG
  [0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
   0,0,0,1,0,0,0,1,8,6,0,0,0,0x1F,0x15,0xC4,0x89,0,0,0,0x0A,0x49,0x44,0x41,0x54,
   0x78,0x9C,0x63,0,1,0,0,5,0,1,0x0D,0x0A,0x2D,0xB4,0,0,0,0,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82]);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: KivoTheme.dark(), home: const Scaffold(body: GestureSeekPreview())),
  ));
  return c;
}

void main() {
  testWidgets('renders nothing when no swipe-seek is in progress', (tester) async {
    await _pump(tester);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('shows the target time and a signed +delta with the frame', (tester) async {
    final c = await _pump(tester);
    c.read(seekPreviewFrameProvider.notifier).state = _png;
    // From 02:00, target 05:00 → +03:00.
    c.read(gestureSeekProvider.notifier).state =
        (target: const Duration(minutes: 5), from: const Duration(minutes: 2));
    await tester.pump();
    expect(find.text('05:00  (+03:00)'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a backward seek shows a negative delta', (tester) async {
    final c = await _pump(tester);
    // From 02:00, target 00:30 → -01:30.
    c.read(gestureSeekProvider.notifier).state =
        (target: const Duration(seconds: 30), from: const Duration(minutes: 2));
    await tester.pump();
    expect(find.text('00:30  (-01:30)'), findsOneWidget);
  });

  testWidgets('no delta suffix when target equals the start', (tester) async {
    final c = await _pump(tester);
    c.read(gestureSeekProvider.notifier).state =
        (target: const Duration(minutes: 1), from: const Duration(minutes: 1));
    await tester.pump();
    expect(find.text('01:00'), findsOneWidget);
  });
}
