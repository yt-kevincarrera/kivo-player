import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';

/// Takes a subtitle the user picked and returns a path that will still be
/// valid next week.
abstract class SubtitleImporter {
  /// Returns the app-owned path, or null when the import failed.
  Future<String?> importFor(String videoKey, String sourcePath);

  Future<void> discard(String importedPath);
}

/// The file picker hands back paths into a cache the OS is free to clear, so
/// storing one and re-reading it on the next launch is a broken association
/// waiting to happen. Subtitles are kilobytes — copying is what makes the
/// association actually survive.
class FileSubtitleImporter implements SubtitleImporter {
  FileSubtitleImporter(this.targetDir, {ErrorLog? log}) : _log = log;

  final Directory targetDir;
  final ErrorLog? _log;

  @override
  Future<String?> importFor(String videoKey, String sourcePath) async {
    File? tempFile;
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        throw FileSystemException('subtitle source is gone', sourcePath);
      }
      if (!targetDir.existsSync()) targetDir.createSync(recursive: true);

      final dot = sourcePath.lastIndexOf('.');
      final ext = dot == -1 ? '.srt' : sourcePath.substring(dot);
      final dest = File('${targetDir.path}${Platform.pathSeparator}$videoKey$ext');

      // Copy into a temp file in the same directory first. The copy is the
      // step most likely to fail (disk full, permission error, a concurrent
      // deletion of targetDir) and is also the slowest one; doing it before
      // touching anything means a failed copy leaves whatever was already
      // working for this video completely untouched, instead of deleting a
      // good copy and then failing to replace it.
      tempFile = File('${dest.path}.importing');
      if (tempFile.existsSync()) tempFile.deleteSync();
      await source.copy(tempFile.path);

      // Only now, with the new copy safely on disk, is it safe to clear any
      // stale copy for this video and swap the temp file into place. Keyed
      // by video, so one video owns at most one imported subtitle and a
      // re-import can never pile up orphans. Matched by the exact stem (the
      // name with only OUR added extension stripped), never a prefix: video
      // keys can themselves contain dots (e.g. "ep1.mkv" vs
      // "ep1.mkv.backup"), and "ep1.mkv.backup.srt" must not be mistaken for
      // a stale copy of "ep1.mkv" just because it starts with "ep1.mkv.".
      for (final existing in targetDir.listSync()) {
        if (existing is! File || existing.path == tempFile.path) continue;
        final name = existing.path.split(Platform.pathSeparator).last;
        final nameDot = name.lastIndexOf('.');
        final stem = nameDot == -1 ? name : name.substring(0, nameDot);
        if (stem == videoKey) existing.deleteSync();
      }
      await tempFile.rename(dest.path);
      tempFile = null;
      return dest.path;
    } catch (e) {
      _log?.record(KivoFailure(KivoOp.subtitleLoad, e));
      debugPrint('FileSubtitleImporter.importFor failed: $e');
      return null;
    } finally {
      // Never leave the temp file behind on a failed attempt.
      if (tempFile != null) {
        try {
          if (tempFile.existsSync()) tempFile.deleteSync();
        } catch (_) {
          // Best-effort cleanup; the outer catch already recorded the real
          // failure.
        }
      }
    }
  }

  @override
  Future<void> discard(String importedPath) async {
    try {
      final f = File(importedPath);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      debugPrint('FileSubtitleImporter.discard failed: $e');
    }
  }
}

final subtitleImporterProvider = Provider<SubtitleImporter>((ref) {
  throw UnimplementedError('subtitleImporterProvider must be overridden');
});
