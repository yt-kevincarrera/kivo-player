import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the library's search field is expanded in the AppBar
/// (replacing the "Kivo" title). Reset to false (and the query cleared)
/// when the user taps the close (X) button.
final librarySearchActiveProvider = StateProvider<bool>((ref) => false);

/// The current search text. Not persisted — resets on app restart, like
/// closing search does.
final librarySearchQueryProvider = StateProvider<String>((ref) => '');

/// "No vistos" toggle — shows only never-played videos when true. Not
/// persisted (unlike `KivoSettings.librarySort`).
final libraryUnwatchedOnlyProvider = StateProvider<bool>((ref) => false);
