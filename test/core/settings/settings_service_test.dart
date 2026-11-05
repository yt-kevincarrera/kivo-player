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
    expect(KivoSettings.defaults().accentColor, 0xFFC7A15A);
    final s = KivoSettings.defaults().copyWith(accentColor: 0xFF2D6CFF);
    expect(KivoSettings.fromMap(s.toMap()).accentColor, 0xFF2D6CFF);
  });

  test('libraryColumns defaults to 1 and round-trips', () {
    final d = KivoSettings.defaults();
    expect(d.libraryColumns, 1);
    final m = d.copyWith(libraryColumns: 3).toMap();
    expect(KivoSettings.fromMap(m).libraryColumns, 3);
  });

  test('iconStyle defaults to duotone and round-trips', () async {
    expect(KivoSettings.defaults().iconStyle, 'duotone');

    final store = InMemorySettingsStore();
    final service = await SettingsService.load(store);
    await service.update(service.current.copyWith(iconStyle: 'flat'));

    final reloaded = await SettingsService.load(store);
    expect(reloaded.current.iconStyle, 'flat');
  });

  test('excludedFolders defaults to empty and round-trips', () async {
    final store = InMemorySettingsStore();
    final svc = await SettingsService.load(store);
    expect(svc.current.excludedFolders, isEmpty);
    await svc.update(svc.current.copyWith(excludedFolders: const ['WhatsApp']));
    final reloaded = await SettingsService.load(store);
    expect(reloaded.current.excludedFolders, ['WhatsApp']);
  });

  test('wide density defaults independently of an existing phone list', () {
    final settings = KivoSettings.fromMap({'libraryColumns': 1});
    expect(settings.libraryColumns, 1);
    expect(settings.wideLibraryDensity, 2);
    final updated = settings.copyWith(wideLibraryDensity: 3);
    final restored = KivoSettings.fromMap(updated.toMap());
    expect(restored.libraryColumns, 1);
    expect(restored.wideLibraryDensity, 3);
    expect(
      KivoSettings.fromMap({'wideLibraryDensity': 0}).wideLibraryDensity,
      0,
    );
    expect(
      KivoSettings.fromMap({
        'wideLibraryDensity': 'compact',
      }).wideLibraryDensity,
      2,
    );
    expect(
      KivoSettings.fromMap({'wideLibraryDensity': 2.0}).wideLibraryDensity,
      2,
    );
  });

  test('legacy default gold upgrades while custom accents remain saved', () {
    expect(
      KivoSettings.fromMap({'accentColor': 0xFFE8B84B}).accentColor,
      0xFFC7A15A,
    );
    expect(
      KivoSettings.fromMap({'accentColor': 0xFF5B9BE8}).accentColor,
      0xFF5B9BE8,
    );
  });
}
