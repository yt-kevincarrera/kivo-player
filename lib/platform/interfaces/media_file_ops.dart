/// Result of a file op that may require system consent (the user can cancel
/// the OS dialog).
enum FileOpStatus { ok, cancelled, error }

class RenameOutcome {
  final FileOpStatus status;
  final String? newName; // final name incl. extension when status == ok
  const RenameOutcome(this.status, {this.newName});
}

/// Operations on a device video file (MediaStore on Android).
abstract class MediaFileOps {
  /// Deletes the file. On Android 11+ the SYSTEM shows its own confirmation;
  /// returns [FileOpStatus.cancelled] if the user declines it.
  Future<FileOpStatus> delete(String uri);

  /// Renames DISPLAY_NAME, preserving the extension. [newBaseName] is the base
  /// name only (no extension). On Android 11+ the SYSTEM asks for write consent.
  Future<RenameOutcome> rename(String uri, String newBaseName);

  /// Shares the file via ACTION_SEND (fire-and-forget; the OS chooser handles
  /// the rest).
  Future<void> share(String uri);
}
