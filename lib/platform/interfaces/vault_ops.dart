import 'dart:typed_data';

/// Moves video files in and out of the app-private Vault directory. Android
/// impl uses MethodChannel('kivo/vault'); all moves are same-volume renames.
abstract class VaultOps {
  /// Moves each content:// [uris] into the private vault dir and removes its
  /// MediaStore row. Returns one metadata map per SUCCESSFULLY hidden file
  /// (keys: id, privatePath, displayName, originalRelativePath, durationMs,
  /// sizeBytes, dateAddedMs, width, height). Failures are omitted.
  Future<List<Map<String, dynamic>>> hide(List<String> uris);

  /// Moves each entry's private file back to shared storage (a same-volume
  /// rename, not a byte copy) and re-indexes it in MediaStore, restoring its
  /// original folder and — best effort — its original date so it doesn't
  /// resurface as "just added". Each map carries: `privatePath`, `displayName`,
  /// `relativePath` (MediaStore RELATIVE_PATH to restore into, '' → Movies/),
  /// `dateAddedMs`. Returns the subset of `privatePath`s that were SUCCESSFULLY
  /// moved back; failures are omitted so callers never orphan an entry whose
  /// file was actually moved.
  Future<List<String>> unhide(List<Map<String, dynamic>> entries);

  /// Permanently deletes each private file. Returns the subset of
  /// [privatePaths] that were SUCCESSFULLY deleted; failures are omitted so
  /// callers never orphan a vault entry whose file was actually deleted.
  Future<List<String>> deleteForever(List<String> privatePaths);

  /// JPEG thumbnail for a private file, or null.
  Future<Uint8List?> thumbnail(String privatePath);

  /// One-time migration of legacy vault files from the old app-private dir into
  /// the current (shared, same-volume) vault dir. Returns `{old, new}` path
  /// pairs so the caller can rewrite persisted `privatePath`s. No-op (empty)
  /// when there is nothing to migrate.
  Future<List<Map<String, dynamic>>> migrate();
}
