import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/media_indexer_provider.dart';

/// Per-id thumbnail; autoDispose frees off-screen ones (MediaStore re-fetch is
/// cheap/system-cached). Returns null if unavailable.
final thumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, id) {
  return ref.read(mediaIndexerProvider).thumbnail(id);
});
