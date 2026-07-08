import 'dart:typed_data';

/// Moves video files in and out of the app-private Vault directory. Android
/// impl uses MethodChannel('kivo/vault'); all moves are same-volume renames.
abstract class VaultOps {
  /// Moves each content:// [uris] into the private vault dir and removes its
  /// MediaStore row. Returns one metadata map per SUCCESSFULLY hidden file
  /// (keys: id, privatePath, displayName, originalRelativePath, durationMs,
  /// sizeBytes, dateAddedMs, width, height). Failures are omitted.
  Future<List<Map<String, dynamic>>> hide(List<String> uris);

  /// Moves each private file back to shared storage + re-inserts MediaStore.
  Future<bool> unhide(List<String> privatePaths);

  /// Permanently deletes each private file.
  Future<bool> deleteForever(List<String> privatePaths);

  /// JPEG thumbnail for a private file, or null.
  Future<Uint8List?> thumbnail(String privatePath);
}
