import '../../platform/interfaces/media_indexer.dart';

class DaySection {
  final String label;
  final List<VideoItem> items;
  const DaySection(this.label, this.items);
}

const _mes = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Groups [items] into ordered day sections (newest first) with relative
/// labels: Hoy, Ayer, "d mmm" (same year), "mmm yyyy" (older). [now] injected.
List<DaySection> groupByDay(List<VideoItem> items, DateTime now) {
  final sorted = [...items]..sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
  final today = DateTime(now.year, now.month, now.day);
  String labelFor(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (day.year == now.year) return '${day.day} ${_mes[day.month]}';
    return '${_mes[day.month]} ${day.year}';
  }

  final sections = <DaySection>[];
  String? cur;
  for (final v in sorted) {
    final l = labelFor(v.dateAddedMs);
    if (l != cur) {
      cur = l;
      sections.add(DaySection(l, <VideoItem>[]));
    }
    sections.last.items.add(v);
  }
  return sections;
}
