import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_log_provider.dart';
import '../../core/errors/kivo_failure.dart';
import '../../platform/frame_extractor_provider.dart';
import '../../platform/image_saver_provider.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';
import 'capture_name.dart';

/// What a capture attempt produced.
///
/// Carries the bytes as well as the uri so the confirmation can show a
/// thumbnail without reading the file back off the device.
class FrameCapture {
  const FrameCapture({this.uri, this.bytes});
  const FrameCapture.failed() : uri = null, bytes = null;

  final String? uri;
  final Uint8List? bytes;

  bool get ok => uri != null;
}

/// Saves the frame the user is looking at into the gallery.
///
/// Uses the same [FrameExtractor] that already feeds the seek-preview bubble,
/// which means the frame is the nearest keyframe rather than the exact one and
/// carries no subtitles — the trade for a decode path that is already proven
/// on device and never touches mpv.
class FrameCaptureController {
  FrameCaptureController(this._ref);
  final Ref _ref;

  Future<FrameCapture> capture() async {
    final session = _ref.read(currentVideoProvider);
    if (session == null) return const FrameCapture.failed();

    try {
      final extractor = _ref.read(frameExtractorProvider);
      // Idempotent for the same path, and the seek preview has usually done it
      // already — but a capture without ever having dragged the seek bar has
      // not, so it cannot be assumed.
      await extractor.prepare(session.playbackPath);

      final at = _ref.read(positionProvider).value ?? Duration.zero;
      final bytes = await extractor.frameAt(at);
      if (bytes == null) {
        throw StateError('no decodable frame at $at');
      }

      final name = captureFileName(session.displayName, at);
      final uri = await _ref.read(imageSaverProvider).save(bytes, name);
      if (uri == null) {
        throw StateError('the gallery refused $name');
      }

      return FrameCapture(uri: uri, bytes: bytes);
    } catch (e) {
      // A capture is a side feature: it reports and gets out of the way rather
      // than taking playback down with it.
      _ref.read(errorLogProvider).record(KivoFailure(KivoOp.frameCapture, e));
      debugPrint('FrameCaptureController.capture failed: $e');
      return const FrameCapture.failed();
    }
  }

  Future<void> view(String uri) => _ref.read(imageSaverProvider).view(uri);
}

final frameCaptureProvider =
    Provider<FrameCaptureController>((ref) => FrameCaptureController(ref));
