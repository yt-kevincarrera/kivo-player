import 'dart:typed_data';
import 'media_indexer.dart';

class StorageVolume {
  final String path;
  final String name;
  final bool removable;
  const StorageVolume({
    required this.path,
    required this.name,
    required this.removable,
  });
}

class StorageEntry {
  final String path;
  final String name;
  final bool directory;
  final VideoItem? video;
  const StorageEntry({
    required this.path,
    required this.name,
    required this.directory,
    this.video,
  });
}

class StorageListing {
  const StorageListing({required this.entries, this.accessLimited = false});
  final List<StorageEntry> entries;

  /// Android may return an empty filtered view even when files exist. Only a
  /// complete read can establish that a directory contains no videos.
  final bool accessLimited;
}

/// Read-only browsing of mounted volumes. No dependency on a document-picker
/// app, and no permission bypass: Android can refuse each read independently.
abstract class StorageBrowser {
  Future<List<StorageVolume>> volumes();
  Future<List<StorageEntry>> list(String path);
  Future<StorageListing> browse(String path) async =>
      StorageListing(entries: await list(path));
  Future<void> rescan(String path) async {}
  Future<List<VideoItem>> scanRemovable();
  Future<Uint8List?> thumbnail(String path);
}
