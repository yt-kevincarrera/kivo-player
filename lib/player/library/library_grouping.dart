import '../../platform/interfaces/media_indexer.dart';

/// [DaySection.group] is null only for the "no date grouping" case (a flat
/// folder view) — never for a genuine group produced by [groupByDay].
class DaySection {
  final DateGroup? group;
  final List<VideoItem> items;
  const DaySection(this.group, this.items);
}

const _mes = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Which relative-day bucket, without baking in any language: [today] and
/// [yesterday] carry no data (a UI maps them to
/// `context.l10n.homeDateToday`/`homeDateYesterday`); [dated] carries an
/// already-formatted date string (`d mmm` for this year, `mmm yyyy` for
/// older), shown as-is. That string is deliberately NOT localized — per the
/// i18n design doc §7, numeric/date formatting by locale is out of scope
/// this wave, so the month abbreviations stay Spanish regardless of the
/// app's language.
enum DateGroupKind { today, yesterday, dated }

class DateGroup {
  final DateGroupKind kind;

  /// Only set when [kind] is [DateGroupKind.dated].
  final String? formatted;

  const DateGroup._(this.kind, [this.formatted]);
  const DateGroup.today() : this._(DateGroupKind.today);
  const DateGroup.yesterday() : this._(DateGroupKind.yesterday);
  const DateGroup.dated(String formatted) : this._(DateGroupKind.dated, formatted);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DateGroup && other.kind == kind && other.formatted == formatted);

  @override
  int get hashCode => Object.hash(kind, formatted);
}

/// Groups [items] into ordered day sections (newest first) with relative
/// groups: today, yesterday, "d mmm" (same year), "mmm yyyy" (older).
/// [now] injected.
List<DaySection> groupByDay(List<VideoItem> items, DateTime now) {
  final sorted = [...items]..sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
  final today = DateTime(now.year, now.month, now.day);
  DateGroup groupFor(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return const DateGroup.today();
    if (diff == 1) return const DateGroup.yesterday();
    if (day.year == now.year) return DateGroup.dated('${day.day} ${_mes[day.month]}');
    return DateGroup.dated('${_mes[day.month]} ${day.year}');
  }

  final sections = <DaySection>[];
  DateGroup? cur;
  for (final v in sorted) {
    final g = groupFor(v.dateAddedMs);
    if (g != cur) {
      cur = g;
      sections.add(DaySection(g, <VideoItem>[]));
    }
    sections.last.items.add(v);
  }
  return sections;
}
