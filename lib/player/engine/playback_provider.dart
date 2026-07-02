import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'playback_engine.dart';

final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  throw UnimplementedError('playbackEngineProvider must be overridden');
});

final positionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackEngineProvider).positionStream;
});

final durationProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackEngineProvider).durationStream;
});

final playingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playbackEngineProvider).playingStream;
});

final bufferingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playbackEngineProvider).bufferingStream;
});

final currentSubtitleTrackProvider = StreamProvider<MediaTrack?>((ref) {
  return ref.watch(playbackEngineProvider).currentSubtitleTrackStream;
});
