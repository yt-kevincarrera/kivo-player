import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'kivo_settings.dart';
import 'settings_service.dart';

/// Overridden in main() once SettingsService is loaded.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError('settingsServiceProvider must be overridden');
});

class SettingsNotifier extends Notifier<KivoSettings> {
  @override
  KivoSettings build() => ref.read(settingsServiceProvider).current;

  Future<void> set(KivoSettings next) async {
    state = next;
    await ref.read(settingsServiceProvider).update(next);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, KivoSettings>(SettingsNotifier.new);
