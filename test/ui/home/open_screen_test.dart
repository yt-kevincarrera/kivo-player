import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/ui/home/open_screen.dart';
import '../../fakes/fakes.dart';

class _Perm implements MediaPermission {
  @override Future<MediaAccess> status() async => MediaAccess.granted;
  @override Future<MediaAccess> request() async => MediaAccess.granted;
}

void main() {
  testWidgets('granted permission lists scanned videos', (tester) async {
    final settingsService = await SettingsService.load(InMemorySettingsStore());
    final fake = FakeMediaIndexer([
      const VideoItem(id: '1', uri: 'content://1', name: 'movie.mp4', folder: 'Movies',
          durationMs: 65000, sizeBytes: 1, dateAddedMs: 0),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        mediaPermissionImplProvider.overrideWithValue(_Perm()),
        mediaIndexerProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: OpenScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('movie.mp4'), findsOneWidget);
  });
}
