import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/library/library_filter.dart';

/// True while the library's search field is expanded in the AppBar
/// (replacing the "Kivo" title). Reset to false (and the query cleared)
/// when the user taps the close (X) button.
final librarySearchActiveProvider = StateProvider<bool>((ref) => false);

/// The current search text. Not persisted — resets on app restart, like
/// closing search does.
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// Session-only watch-status filter. Sorting remains persisted in settings.
final libraryWatchFilterProvider = StateProvider<LibraryWatchFilter>(
  (ref) => LibraryWatchFilter.all,
);
