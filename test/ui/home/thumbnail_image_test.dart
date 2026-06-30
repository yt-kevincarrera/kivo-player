import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/ui/home/widgets/thumbnail_image.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('shows placeholder then image when bytes arrive', (tester) async {
    final fake = FakeMediaIndexer()..thumb = Uint8List.fromList(
      // 1x1 transparent PNG
      [0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
       0,0,0,1,0,0,0,1,8,6,0,0,0,0x1F,0x15,0xC4,0x89,0,0,0,0x0A,0x49,0x44,0x41,0x54,
       0x78,0x9C,0x63,0,1,0,0,5,0,1,0x0D,0x0A,0x2D,0xB4,0,0,0,0,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82]);
    await tester.pumpWidget(ProviderScope(
      overrides: [mediaIndexerProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: SizedBox(width: 100, height: 100, child: ThumbnailImage('1'))),
    ));
    expect(find.byType(Container), findsOneWidget); // placeholder first
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget); // image after load
  });
}
