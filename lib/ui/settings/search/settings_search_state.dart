import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the Ajustes app bar is showing the search field. A provider, not
/// screen state, so HomeShell's back handler can close it.
final settingsSearchActiveProvider = StateProvider<bool>((ref) => false);

final settingsSearchQueryProvider = StateProvider<String>((ref) => '');

void closeSettingsSearch(WidgetRef ref) {
  ref.read(settingsSearchActiveProvider.notifier).state = false;
  ref.read(settingsSearchQueryProvider.notifier).state = '';
}

/// The anchor id a search result asked to reveal. Set right before pushing
/// the section; the matching `SettingAnchor` consumes it (sets it back to
/// null) once it has scrolled into view and flashed.
final settingsHighlightProvider = StateProvider<String?>((ref) => null);
