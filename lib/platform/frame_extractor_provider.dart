import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/frame_extractor.dart';

/// Overridden in main() with the Android implementation.
final frameExtractorProvider = Provider<FrameExtractor>((ref) {
  throw UnimplementedError('frameExtractorProvider must be overridden');
});
