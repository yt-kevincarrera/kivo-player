import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../library/media_index.dart';
import '../open/video_source.dart'; // resumeServiceProvider
import '../../platform/television_provider.dart';

class ContinueItem {
  final VideoItem video;
  final int seconds;
  final double fraction;
  const ContinueItem(this.video, this.seconds, this.fraction);
}

final continueWatchingProvider = Provider<List<ContinueItem>>((ref) {
  final index = ref.watch(libraryIndexProvider).valueOrNull ?? const [];
  if (index.isEmpty) return const [];
  ref.watch(resumeHistoryChangesProvider);
  final byKey = {for (final v in index) v.key: v};
  final entries = ref.read(resumeServiceProvider).entries()
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  final out = <ContinueItem>[];
  for (final e in entries) {
    final v = byKey[e.key];
    if (v == null || (v.durationMs <= 0 && !ref.read(isTelevisionProvider))) {
      continue;
    }
    final frac = v.durationMs > 0 ? (e.seconds * 1000) / v.durationMs : 0.0;
    if (frac >= 0.97) continue;
    out.add(ContinueItem(v, e.seconds, frac.clamp(0.0, 1.0)));
  }
  return out;
});
