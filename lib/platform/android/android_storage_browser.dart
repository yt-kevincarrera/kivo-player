import 'package:flutter/services.dart';
import '../interfaces/media_indexer.dart';
import '../interfaces/storage_browser.dart';

class AndroidStorageBrowser extends StorageBrowser {
  static const _channel = MethodChannel('kivo/storage');

  static VideoItem video(Map<Object?, Object?> m) => VideoItem(
    id: m['id'] as String,
    uri: m['uri'] as String,
    name: m['name'] as String,
    folder: m['folder'] as String? ?? '',
    durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
    sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
    dateAddedMs: (m['dateAddedMs'] as num?)?.toInt() ?? 0,
    filePath: m['filePath'] as String? ?? '',
  );

  @override
  Future<List<StorageVolume>> volumes() async {
    final raw = await _channel.invokeListMethod<Map>('volumes') ?? [];
    return raw
        .map(
          (m) => StorageVolume(
            path: m['path'] as String,
            name: m['name'] as String,
            removable: m['removable'] as bool,
          ),
        )
        .toList();
  }

  @override
  Future<List<StorageEntry>> list(String path) async {
    return (await browse(path)).entries;
  }

  @override
  Future<StorageListing> browse(String path) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('browse', {
      'path': path,
    });
    final raw = (result?['entries'] as List? ?? []).cast<Map>();
    return StorageListing(
      accessLimited: result?['accessLimited'] == true,
      entries: raw
          .map(
            (m) => StorageEntry(
              path: m['filePath'] as String,
              name: m['name'] as String,
              directory: m['directory'] as bool,
              video: m['directory'] == true ? null : video(m),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> rescan(String path) =>
      _channel.invokeMethod<void>('rescan', {'path': path});

  @override
  Future<List<VideoItem>> scanRemovable() async {
    final raw = await _channel.invokeListMethod<Map>('scanRemovable') ?? [];
    return raw.map(video).toList();
  }

  @override
  Future<Uint8List?> thumbnail(String path) =>
      _channel.invokeMethod<Uint8List>('thumbnail', {'path': path});
}
