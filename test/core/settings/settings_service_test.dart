import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import '../../fakes/fakes.dart';

void main() {
  test('loads defaults when store is empty', () async {
    final service = await SettingsService.load(InMemorySettingsStore());
    expect(service.current.centerSkipSeconds, 10);
    expect(service.current.holdRightMax, 4.0);
    expect(service.current.resumeBehavior, 'auto');
  });

  test('persists and reloads updated settings', () async {
    final store = InMemorySettingsStore();
    final service = await SettingsService.load(store);
    await service.update(service.current.copyWith(centerSkipSeconds: 30));

    final reloaded = await SettingsService.load(store);
    expect(reloaded.current.centerSkipSeconds, 30);
  });

  test('round-trips through map', () {
    final s = KivoSettings.defaults().copyWith(volumeBoostMax: 200);
    expect(KivoSettings.fromMap(s.toMap()).volumeBoostMax, 200);
  });

  test('accentColor defaults to gold and round-trips', () {
    expect(KivoSettings.defaults().accentColor, 0xFFE8B84B);
    final s = KivoSettings.defaults().copyWith(accentColor: 0xFF2D6CFF);
    expect(KivoSettings.fromMap(s.toMap()).accentColor, 0xFF2D6CFF);
  });

  test('libraryColumns defaults to 1 and round-trips', () {
    final d = KivoSettings.defaults();
    expect(d.libraryColumns, 1);
    final m = d.copyWith(libraryColumns: 3).toMap();
    expect(KivoSettings.fromMap(m).libraryColumns, 3);
  });
}
