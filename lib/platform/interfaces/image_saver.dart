import 'dart:typed_data';

/// Puts an image into the device's gallery.
///
/// Its own interface rather than another method on [MediaFileOps]: that
/// contract is about operations on the *video* file the user is watching —
/// delete, rename, share. Writing a new image somewhere else is a different
/// job with a different failure mode.
abstract class ImageSaver {
  /// Saves [bytes] as [fileName] under the gallery's Pictures/Kivo.
  ///
  /// Returns the resulting `content://` uri, or null if it could not be
  /// written. Never throws — a failed capture must not take the player with
  /// it.
  Future<String?> save(Uint8List bytes, String fileName);

  /// Opens a saved image in whatever the device uses to view pictures.
  Future<void> view(String uri);
}
