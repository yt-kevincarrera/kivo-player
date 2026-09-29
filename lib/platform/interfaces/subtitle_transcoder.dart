/// What mpv should load for an external subtitle, and what it was read as.
class PreparedSubtitle {
  const PreparedSubtitle({
    required this.uri,
    required this.encoding,
    required this.detected,
  });

  /// The original uri when the file could go to mpv untouched (already UTF-8,
  /// or a binary format), otherwise a converted UTF-8 copy.
  final String uri;

  /// The charset the file was read as (e.g. `windows-1251`), or null for a
  /// binary subtitle that has no text encoding.
  final String? encoding;

  /// True when [encoding] was guessed; false when the user chose it.
  final bool detected;
}

/// Turns any external text subtitle into something the bundled libmpv reads
/// correctly. It has no charset detection or conversion of its own, so
/// anything that is not UTF-8 has to be converted before it gets there.
abstract class SubtitleTranscoder {
  /// [name] is the file's display name, used for its extension when [uri] is
  /// a `content://` uri. [encoding] forces a charset; null detects it.
  Future<PreparedSubtitle> prepare(String uri, {String? name, String? encoding});

  /// Every charset the system can decode, for the picker's "Más…".
  Future<List<String>> availableEncodings();

  /// The one font libass may use (it has no font provider on Android): a
  /// directory holding just that font, and its family name. Null when none
  /// could be prepared — ASS is then drawn by Kivo instead.
  Future<({String dir, String family})?> systemSubtitleFont();
}
