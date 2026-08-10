import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../engine/playback_engine.dart';

/// Opens [path] on [engine], turning an engine failure into a KV-501 the UI can
/// show. Without this a bad file is an unhandled async error and the user just
/// gets a black screen with no message at all.
Future<void> guardedOpen(
  PlaybackEngine engine,
  String path,
  ErrorLog log, {
  Duration startAt = Duration.zero,
}) async {
  try {
    await engine.open(path, startAt: startAt);
  } catch (e) {
    throw log.record(KivoFailure(KivoOp.openVideo, e));
  }
}
