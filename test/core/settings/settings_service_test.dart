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
}
