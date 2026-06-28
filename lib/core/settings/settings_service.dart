import 'kivo_settings.dart';
import 'settings_store.dart';

class SettingsService {
  final SettingsStore _store;
  KivoSettings _current;

  SettingsService._(this._store, this._current);

  KivoSettings get current => _current;

  static Future<SettingsService> load(SettingsStore store) async {
    final map = store.read();
    final settings = map == null ? KivoSettings.defaults() : KivoSettings.fromMap(map);
    return SettingsService._(store, settings);
  }

  Future<void> update(KivoSettings next) async {
    _current = next;
    await _store.write(next.toMap());
  }
}
