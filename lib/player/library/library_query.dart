import '../../platform/interfaces/media_indexer.dart';
import '../queue/natural_sort.dart';

Map<String, List<VideoItem>> groupByFolder(List<VideoItem> items) {
  final map = <String, List<VideoItem>>{};
  for (final v in items) {
    (map[v.folder] ??= <VideoItem>[]).add(v);
  }
  for (final list in map.values) {
    list.sort((a, b) => naturalCompare(a.name, b.name));
  }
  return map;
}

List<VideoItem> folderQueueFor(List<VideoItem> all, VideoItem current) {
  final siblings = all.where((v) => v.folder == current.folder).toList()
    ..sort((a, b) => naturalCompare(a.name, b.name));
  return siblings;
}
