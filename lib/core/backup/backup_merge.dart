import '../../player/bookmarks/bookmark.dart';
import '../../player/playlists/playlist.dart';
import '../../player/tracks/track_prefs_store.dart';
import '../../vault/vault_entry.dart';
import 'backup_file.dart';

/// How many entries of one section a restore would add, update, or leave
/// alone. "Merge, never delete" means every section only ever grows or
/// changes a value — nothing already on the device is ever removed by a
/// restore.
class SectionCounts {
  final int added;
  final int updated;
  final int unchanged;
  const SectionCounts({
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
  });

  int get total => added + updated + unchanged;

  @override
  String toString() =>
      'SectionCounts(added: $added, updated: $updated, unchanged: $unchanged)';
}

/// A snapshot of what is currently on the device, in the shape
/// [buildRestorePlan] needs to compare against a [BackupFile]. Each field is
/// the store's full contents — [bookmarks] and [trackPrefs] only need to
/// carry the videos also present in the backup being planned, so a caller
/// may pass a partial map (matching keys is all `buildRestorePlan` does with
/// them) as well as the store's `all()`.
class CurrentBackupData {
  final Set<String> played;
  final Map<String, List<Bookmark>> bookmarks;
  final List<Playlist> playlists;
  final Map<String, VideoTrackPrefs> trackPrefs;
  final Map<String, ResumeBackupEntry> resume;
  final List<VaultEntry> vault;

  const CurrentBackupData({
    required this.played,
    required this.bookmarks,
    required this.playlists,
    required this.trackPrefs,
    required this.resume,
    required this.vault,
  });
}

/// The result of comparing a [BackupFile] against what is currently on the
/// device: per-section counts for the confirmation dialog, and the merged
/// data [BackupService.apply] writes back through each store's own public
/// methods.
class RestorePlan {
  final BackupFile backup;

  final SectionCounts playedCounts;
  final Set<String> playedToAdd;

  final SectionCounts bookmarksCounts;
  /// Keyed by video; only videos whose bookmark list actually gained
  /// something are present, each mapped to its full merged list.
  final Map<String, List<Bookmark>> bookmarksToWrite;

  final SectionCounts playlistsCounts;
  final List<Playlist> playlistsToAdd;

  final SectionCounts trackPrefsCounts;
  final Map<String, VideoTrackPrefs> trackPrefsToWrite;

  final SectionCounts resumeCounts;
  final Map<String, ResumeBackupEntry> resumeToWrite;

  final SectionCounts vaultCounts;
  final List<VaultEntry> vaultToAdd;

  /// Settings are replaced wholesale, not merged field by field — this is
  /// true whenever the backup carries a settings section at all.
  final bool settingsWillReplace;

  const RestorePlan({
    required this.backup,
    required this.playedCounts,
    required this.playedToAdd,
    required this.bookmarksCounts,
    required this.bookmarksToWrite,
    required this.playlistsCounts,
    required this.playlistsToAdd,
    required this.trackPrefsCounts,
    required this.trackPrefsToWrite,
    required this.resumeCounts,
    required this.resumeToWrite,
    required this.vaultCounts,
    required this.vaultToAdd,
    required this.settingsWillReplace,
  });

  /// Whether applying this plan would change anything at all — used to grey
  /// out or skip the confirm step when a backup is restored twice in a row.
  bool get hasChanges =>
      playedToAdd.isNotEmpty ||
      bookmarksToWrite.isNotEmpty ||
      playlistsToAdd.isNotEmpty ||
      trackPrefsToWrite.isNotEmpty ||
      resumeToWrite.isNotEmpty ||
      vaultToAdd.isNotEmpty ||
      settingsWillReplace;
}

bool _trackPrefsEqual(VideoTrackPrefs a, VideoTrackPrefs b) =>
    a.subtitleDelayMs == b.subtitleDelayMs &&
    a.audioDelayMs == b.audioDelayMs &&
    a.subtitlePath == b.subtitlePath;

/// Builds a [RestorePlan] from [backup] against [current]. Pure: no store,
/// no Riverpod — every rule below is exactly the one "Merge, never delete"
/// describes for its section.
RestorePlan buildRestorePlan({
  required BackupFile backup,
  required CurrentBackupData current,
}) {
  // played: union.
  final playedToAdd = <String>{};
  var playedAdded = 0, playedUnchanged = 0;
  for (final key in backup.played) {
    if (current.played.contains(key)) {
      playedUnchanged++;
    } else {
      playedAdded++;
      playedToAdd.add(key);
    }
  }

  // bookmarks: per-video union by value.
  final bookmarksToWrite = <String, List<Bookmark>>{};
  var bookmarksAdded = 0, bookmarksUnchanged = 0;
  for (final entry in backup.bookmarks.entries) {
    final key = entry.key;
    final currentList = current.bookmarks[key] ?? const <Bookmark>[];
    final seen = currentList.toSet();
    final merged = List<Bookmark>.of(currentList);
    var addedHere = 0;
    for (final b in entry.value) {
      if (seen.contains(b)) {
        bookmarksUnchanged++;
      } else {
        seen.add(b);
        merged.add(b);
        addedHere++;
        bookmarksAdded++;
      }
    }
    if (addedHere > 0) bookmarksToWrite[key] = merged;
  }

  // playlists: by id — missing added, existing kept as-is (local wins).
  final playlistsToAdd = <Playlist>[];
  var playlistsAdded = 0, playlistsUnchanged = 0;
  final currentPlaylistIds = current.playlists.map((p) => p.id).toSet();
  for (final p in backup.playlists) {
    if (currentPlaylistIds.contains(p.id)) {
      playlistsUnchanged++;
    } else {
      playlistsAdded++;
      playlistsToAdd.add(p);
    }
  }

  // trackPrefs: backup wins on conflict.
  final trackPrefsToWrite = <String, VideoTrackPrefs>{};
  var trackPrefsAdded = 0, trackPrefsUpdated = 0, trackPrefsUnchanged = 0;
  for (final entry in backup.trackPrefs.entries) {
    final cur = current.trackPrefs[entry.key];
    if (cur == null) {
      trackPrefsAdded++;
      trackPrefsToWrite[entry.key] = entry.value;
    } else if (!_trackPrefsEqual(cur, entry.value)) {
      trackPrefsUpdated++;
      trackPrefsToWrite[entry.key] = entry.value;
    } else {
      trackPrefsUnchanged++;
    }
  }

  // resume: newer updatedAtMs wins; a tie keeps the current entry.
  final resumeToWrite = <String, ResumeBackupEntry>{};
  var resumeAdded = 0, resumeUpdated = 0, resumeUnchanged = 0;
  for (final entry in backup.resume.entries) {
    final cur = current.resume[entry.key];
    if (cur == null) {
      resumeAdded++;
      resumeToWrite[entry.key] = entry.value;
    } else if (entry.value.updatedAtMs > cur.updatedAtMs) {
      resumeUpdated++;
      resumeToWrite[entry.key] = entry.value;
    } else {
      resumeUnchanged++;
    }
  }

  // vault: union by entry identity (the stable MediaStore id).
  final vaultToAdd = <VaultEntry>[];
  var vaultAdded = 0, vaultUnchanged = 0;
  final currentVaultIds = current.vault.map((e) => e.id).toSet();
  for (final e in backup.vault) {
    if (currentVaultIds.contains(e.id)) {
      vaultUnchanged++;
    } else {
      vaultAdded++;
      vaultToAdd.add(e);
    }
  }

  return RestorePlan(
    backup: backup,
    playedCounts: SectionCounts(added: playedAdded, unchanged: playedUnchanged),
    playedToAdd: playedToAdd,
    bookmarksCounts:
        SectionCounts(added: bookmarksAdded, unchanged: bookmarksUnchanged),
    bookmarksToWrite: bookmarksToWrite,
    playlistsCounts:
        SectionCounts(added: playlistsAdded, unchanged: playlistsUnchanged),
    playlistsToAdd: playlistsToAdd,
    trackPrefsCounts: SectionCounts(
        added: trackPrefsAdded,
        updated: trackPrefsUpdated,
        unchanged: trackPrefsUnchanged),
    trackPrefsToWrite: trackPrefsToWrite,
    resumeCounts: SectionCounts(
        added: resumeAdded, updated: resumeUpdated, unchanged: resumeUnchanged),
    resumeToWrite: resumeToWrite,
    vaultCounts: SectionCounts(added: vaultAdded, unchanged: vaultUnchanged),
    vaultToAdd: vaultToAdd,
    settingsWillReplace: backup.settings.isNotEmpty,
  );
}

/// Structured counterpart to [describeRestorePlan]: the same six per-section
/// counts plus [settingsWillReplace], with no sentence or language baked in.
/// A UI builds the confirmation sentence from these via ICU plurals
/// (`settingsBackupRestoreItem*` in the ARB) — one plural placeholder per
/// section, joined in Dart with the locale's own join word
/// (`settingsBackupRestoreJoinWord`) — which is the shape (rather than one
/// giant multi-plural message) because the number of sections that actually
/// changed varies per restore, so the sentence's structure varies too; a
/// single ICU message can't conditionally omit clauses the way a small loop
/// over non-zero counts can.
class RestoreSummary {
  final int playlistsAdded;
  final int bookmarksAdded;

  /// Resume positions added or updated — [RestorePlan.resumeCounts] doesn't
  /// distinguish the two in the sentence (both read as "positions changed").
  final int positionsChanged;
  final int watchedVideosAdded;
  final int hiddenVideosAdded;

  /// Track prefs (sync offsets, chosen subtitle) added or updated.
  final int trackSettingsChanged;
  final bool settingsWillReplace;

  const RestoreSummary({
    this.playlistsAdded = 0,
    this.bookmarksAdded = 0,
    this.positionsChanged = 0,
    this.watchedVideosAdded = 0,
    this.hiddenVideosAdded = 0,
    this.trackSettingsChanged = 0,
    this.settingsWillReplace = false,
  });
}

/// Builds a [RestoreSummary] from [plan] — the counts [describeRestorePlan]
/// turns into its hardcoded Spanish sentence, exposed instead as plain data
/// for a localized UI to phrase itself.
RestoreSummary summarizeRestorePlan(RestorePlan plan) => RestoreSummary(
      playlistsAdded: plan.playlistsCounts.added,
      bookmarksAdded: plan.bookmarksCounts.added,
      positionsChanged: plan.resumeCounts.added + plan.resumeCounts.updated,
      watchedVideosAdded: plan.playedCounts.added,
      hiddenVideosAdded: plan.vaultCounts.added,
      trackSettingsChanged:
          plan.trackPrefsCounts.added + plan.trackPrefsCounts.updated,
      settingsWillReplace: plan.settingsWillReplace,
    );

String _pluralize(int n, String singular, String plural) =>
    n == 1 ? singular : plural;

String _joinSpanish(List<String> parts) {
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}';
}

/// The Spanish sentence shown in the restore confirmation dialog, e.g.
/// «Se añadirán 3 listas, 40 marcadores, 12 posiciones. Los ajustes se
/// reemplazarán.» — or «No hay nada nuevo que añadir.» when [plan] would
/// change nothing (restoring the same backup twice).
///
/// Kept for any caller still on the hardcoded-Spanish API; [summarizeRestorePlan]
/// is the localized-UI replacement.
String describeRestorePlan(RestorePlan plan) {
  final parts = <String>[];
  if (plan.playlistsCounts.added > 0) {
    parts.add(
        '${plan.playlistsCounts.added} ${_pluralize(plan.playlistsCounts.added, 'lista', 'listas')}');
  }
  if (plan.bookmarksCounts.added > 0) {
    parts.add(
        '${plan.bookmarksCounts.added} ${_pluralize(plan.bookmarksCounts.added, 'marcador', 'marcadores')}');
  }
  final resumeChanged = plan.resumeCounts.added + plan.resumeCounts.updated;
  if (resumeChanged > 0) {
    parts.add(
        '$resumeChanged ${_pluralize(resumeChanged, 'posición', 'posiciones')}');
  }
  if (plan.playedCounts.added > 0) {
    parts.add(
        '${plan.playedCounts.added} ${_pluralize(plan.playedCounts.added, 'video visto', 'videos vistos')}');
  }
  if (plan.vaultCounts.added > 0) {
    parts.add(
        '${plan.vaultCounts.added} ${_pluralize(plan.vaultCounts.added, 'video oculto', 'videos ocultos')}');
  }
  final trackPrefsChanged =
      plan.trackPrefsCounts.added + plan.trackPrefsCounts.updated;
  if (trackPrefsChanged > 0) {
    parts.add(
        '$trackPrefsChanged ${_pluralize(trackPrefsChanged, 'ajuste de pista', 'ajustes de pista')}');
  }

  final sentence = StringBuffer();
  if (parts.isEmpty) {
    sentence.write('No hay nada nuevo que añadir.');
  } else {
    sentence.write('Se añadirán ${_joinSpanish(parts)}.');
  }
  if (plan.settingsWillReplace) {
    if (parts.isNotEmpty) sentence.write(' ');
    sentence.write('Los ajustes se reemplazarán.');
  }
  return sentence.toString();
}
