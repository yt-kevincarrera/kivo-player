import 'dart:convert';

import '../../player/bookmarks/bookmark.dart';
import '../../player/playlists/playlist.dart';
import '../../player/tracks/track_prefs_store.dart';
import '../../vault/vault_entry.dart';

/// The backup file format's own version, independent of the app version. Bump
/// only for a shape change that an older Kivo could not make sense of.
/// [BackupFile.fromJson] refuses anything stamped higher than this.
const int kBackupFormatVersion = 1;

/// Thrown by [BackupFile.fromJson]/[BackupFile.fromMap] when the file's
/// `kivo` field is higher than [kBackupFormatVersion] — it was written by a
/// newer Kivo this build cannot fully understand.
class BackupTooNewException implements Exception {
  final int fileVersion;
  const BackupTooNewException(this.fileVersion);

  @override
  String toString() => 'Esta copia es de una versión más nueva de Kivo.';
}

/// Thrown by [BackupFile.fromJson]/[BackupFile.fromMap] when the content
/// isn't a Kivo backup at all — not valid JSON, or not a JSON object.
class BackupFormatException implements Exception {
  final String reason;
  const BackupFormatException(this.reason);

  @override
  String toString() => 'Este archivo no es una copia de seguridad de Kivo.';
}

/// The resume position for one video, as the backup file stores it — the
/// same 's'/'u' shape [HiveResumeStore] itself already persists, kept as its
/// own tiny value type here because [ResumeStore]/[ResumeEntry] have no
/// toMap/fromMap of their own to reuse.
class ResumeBackupEntry {
  final int seconds;
  final int updatedAtMs;
  const ResumeBackupEntry(this.seconds, this.updatedAtMs);

  @override
  bool operator ==(Object other) =>
      other is ResumeBackupEntry &&
      other.seconds == seconds &&
      other.updatedAtMs == updatedAtMs;

  @override
  int get hashCode => Object.hash(seconds, updatedAtMs);
}

/// One JSON-serializable snapshot of everything Kivo keeps that the user
/// made: settings, resume positions, played status, per-video track prefs,
/// playlists, bookmarks, and the vault's entry index (never its PIN/salt —
/// see [BackupService] for why).
///
/// Pure and Riverpod-free: reading the live stores into one of these, and
/// writing one back into them, is [BackupService]'s job. This class only
/// knows the file's shape, and reuses every model's own toMap/fromMap rather
/// than inventing a second serialization for any of them.
class BackupFile {
  final String app;
  final int createdAtMs;

  /// [KivoSettings.toMap]'s output, kept as a raw map (not a KivoSettings)
  /// so this file stays Riverpod/model-decoupled; [KivoSettings.fromMap]
  /// already tolerates old/missing keys, which is exactly what a settings
  /// restore across app versions needs.
  final Map<String, dynamic> settings;

  final Map<String, ResumeBackupEntry> resume;
  final Set<String> played;
  final Map<String, VideoTrackPrefs> trackPrefs;
  final List<Playlist> playlists;
  final Map<String, List<Bookmark>> bookmarks;
  final List<VaultEntry> vault;

  const BackupFile({
    required this.app,
    required this.createdAtMs,
    required this.settings,
    required this.resume,
    required this.played,
    required this.trackPrefs,
    required this.playlists,
    required this.bookmarks,
    required this.vault,
  });

  Map<String, dynamic> toMap() => {
        'kivo': kBackupFormatVersion,
        'app': app,
        'createdAtMs': createdAtMs,
        'settings': settings,
        'resume': {
          for (final e in resume.entries)
            e.key: {'s': e.value.seconds, 'u': e.value.updatedAtMs},
        },
        'played': played.toList(),
        'trackPrefs': {
          for (final e in trackPrefs.entries) e.key: e.value.toMap(),
        },
        'playlists': playlists.map((p) => p.toMap()).toList(),
        'bookmarks': {
          for (final e in bookmarks.entries)
            e.key: e.value.map((b) => b.toMap()).toList(),
        },
        'vault': vault.map((v) => v.toMap()).toList(),
      };

  String toJson() => const JsonEncoder.withIndent('  ').convert(toMap());

  factory BackupFile.fromMap(Map<String, dynamic> m) {
    final rawVersion = m['kivo'];
    // Missing 'kivo' is tolerated as version 1 (an old or hand-made file) —
    // only a version ABOVE what this build understands is refused.
    final version = rawVersion is num ? rawVersion.toInt() : 1;
    if (version > kBackupFormatVersion) {
      throw BackupTooNewException(version);
    }

    final settingsRaw = m['settings'];
    final settings = settingsRaw is Map
        ? Map<String, dynamic>.from(settingsRaw)
        : <String, dynamic>{};

    final resume = <String, ResumeBackupEntry>{};
    final resumeRaw = m['resume'];
    if (resumeRaw is Map) {
      for (final e in resumeRaw.entries) {
        final v = e.value;
        if (v is Map) {
          resume[e.key.toString()] = ResumeBackupEntry(
            (v['s'] as num?)?.toInt() ?? 0,
            (v['u'] as num?)?.toInt() ?? 0,
          );
        }
      }
    }

    final playedRaw = m['played'];
    final played = playedRaw is List
        ? playedRaw.map((e) => e.toString()).toSet()
        : <String>{};

    final trackPrefs = <String, VideoTrackPrefs>{};
    final trackPrefsRaw = m['trackPrefs'];
    if (trackPrefsRaw is Map) {
      for (final e in trackPrefsRaw.entries) {
        if (e.value is Map) {
          trackPrefs[e.key.toString()] =
              VideoTrackPrefs.fromMap(e.value as Map);
        }
      }
    }

    final playlistsRaw = m['playlists'];
    final playlists = playlistsRaw is List
        ? playlistsRaw.whereType<Map>().map(Playlist.fromMap).toList()
        : <Playlist>[];

    final bookmarks = <String, List<Bookmark>>{};
    final bookmarksRaw = m['bookmarks'];
    if (bookmarksRaw is Map) {
      for (final e in bookmarksRaw.entries) {
        if (e.value is List) {
          bookmarks[e.key.toString()] = (e.value as List)
              .whereType<Map>()
              .map(Bookmark.fromMap)
              .toList();
        }
      }
    }

    final vaultRaw = m['vault'];
    final vault = vaultRaw is List
        ? vaultRaw
            .whereType<Map>()
            .map((e) => VaultEntry.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <VaultEntry>[];

    return BackupFile(
      app: (m['app'] as String?) ?? '',
      createdAtMs: (m['createdAtMs'] as num?)?.toInt() ?? 0,
      settings: settings,
      resume: resume,
      played: played,
      trackPrefs: trackPrefs,
      playlists: playlists,
      bookmarks: bookmarks,
      vault: vault,
    );
  }

  factory BackupFile.fromJson(String json) {
    dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException('invalid JSON');
    }
    if (decoded is! Map) {
      throw const BackupFormatException('not a JSON object');
    }
    return BackupFile.fromMap(Map<String, dynamic>.from(decoded));
  }
}
