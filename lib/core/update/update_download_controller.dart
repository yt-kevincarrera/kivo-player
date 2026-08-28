import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/error_log_provider.dart';
import '../errors/kivo_failure.dart';
import '../settings/settings_provider.dart';
import '../../platform/app_installer_provider.dart';
import '../../platform/interfaces/app_installer.dart';
import 'update_info.dart';

/// How often the queued download is re-read while someone is looking at it.
const updatePollInterval = Duration(milliseconds: 500);

/// The four states the update UI can be in. [DownloadProgress.stage] carries
/// the detail inside [downloading] (running, or paused and why).
enum DownloadPhase { idle, downloading, ready, failed }

class UpdateDownloadState {
  const UpdateDownloadState({
    this.phase = DownloadPhase.idle,
    this.progress = const DownloadProgress(DownloadStage.pending),
    this.version,
    this.downloadId = -1,
  });

  final DownloadPhase phase;
  final DownloadProgress progress;
  final String? version;
  final int downloadId;

  bool get isBusy => phase == DownloadPhase.downloading;

  UpdateDownloadState copyWith({
    DownloadPhase? phase,
    DownloadProgress? progress,
    String? version,
    int? downloadId,
  }) =>
      UpdateDownloadState(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        version: version ?? this.version,
        downloadId: downloadId ?? this.downloadId,
      );

  @override
  bool operator ==(Object other) =>
      other is UpdateDownloadState &&
      other.phase == phase &&
      other.progress == progress &&
      other.version == version &&
      other.downloadId == downloadId;

  @override
  int get hashCode => Object.hash(phase, progress, version, downloadId);
}

/// Owns the update APK download.
///
/// The download itself belongs to the system, not to this object: it keeps
/// running with Kivo in the background or killed outright. This notifier only
/// tracks it — re-attaching on launch via the id persisted in settings — and
/// installs it when the user asks. Nothing installs on its own.
class UpdateDownloadNotifier extends Notifier<UpdateDownloadState> {
  Timer? _timer;
  int _watchers = 0;

  AppInstaller get _installer => ref.read(appInstallerProvider);

  /// Polling re-reads the same numbers twice a second for most of a download.
  /// Value equality here is what keeps that from rebuilding the dialog every
  /// tick when nothing actually moved.
  @override
  bool updateShouldNotify(UpdateDownloadState prev, UpdateDownloadState next) =>
      prev != next;

  @override
  UpdateDownloadState build() {
    ref.onDispose(_stopTimer);
    final s = ref.read(settingsProvider);
    if (s.pendingUpdateDownloadId < 0) return const UpdateDownloadState();
    // A download from a previous run is still out there. Show it as in flight
    // until the first refresh says otherwise — a pending download rendered as
    // "idle" would invite the user to queue a second copy of the same APK.
    scheduleMicrotask(refresh);
    return UpdateDownloadState(
      phase: DownloadPhase.downloading,
      version: s.pendingUpdateVersion,
      downloadId: s.pendingUpdateDownloadId,
    );
  }

  /// Called by the UI while it is on screen. Polling only runs between this
  /// and [stopWatching], so a closed dialog costs nothing — the download is
  /// unaffected either way, since the system is the one carrying it.
  void startWatching() {
    _watchers++;
    if (_watchers == 1) {
      unawaited(refresh());
      _syncTimer();
    }
  }

  void stopWatching() {
    if (_watchers > 0) _watchers--;
    if (_watchers == 0) _stopTimer();
  }

  Future<void> start(UpdateInfo info) async {
    final url = info.apkUrl;
    if (url == null) return;
    // Drop anything queued earlier so a superseded APK can't be installed.
    await _forget();
    final id = await _installer.enqueueUpdate(url, 'kivo-${info.version}.apk');
    if (id < 0) {
      _fail(StateError('enqueue returned $id'));
      return;
    }
    state = UpdateDownloadState(
      phase: DownloadPhase.downloading,
      version: info.version,
      downloadId: id,
    );
    await _persist(id, info.version);
    _syncTimer();
  }

  Future<void> refresh() async {
    final id = state.downloadId;
    if (id < 0) return;
    final p = await _installer.downloadStatus(id);
    // A user can cancel or clear the download from the system UI at any point;
    // treat that as "never happened" rather than as an error to report.
    if (p.stage == DownloadStage.gone) {
      await _forget();
      return;
    }
    if (p.stage == DownloadStage.failed) {
      _fail(StateError('download failed'), progress: p);
      return;
    }
    final done = p.stage == DownloadStage.done;
    state = state.copyWith(
      phase: done ? DownloadPhase.ready : DownloadPhase.downloading,
      progress: p,
    );
    if (done) _stopTimer();
  }

  /// Hands the finished APK to the system installer. Returns the outcome so
  /// the dialog can explain a missing "install unknown apps" permission.
  Future<InstallOutcome> install() async {
    if (state.phase != DownloadPhase.ready) return InstallOutcome.failed;
    final outcome = await _installer.installDownload(state.downloadId);
    // The APK on disk is still good, so keep the id: retrying must not mean
    // downloading the same 30 MB again.
    if (outcome == InstallOutcome.failed) {
      _fail(StateError('installer refused the APK'), forget: false);
    }
    return outcome;
  }

  Future<void> cancel() async {
    final id = state.downloadId;
    if (id >= 0) await _installer.cancelDownload(id);
    await _forget();
  }

  /// Recovers from [DownloadPhase.failed]: re-installs the APK when one is
  /// already on disk, otherwise queues the download again. Returns the
  /// install outcome, or null when it started a fresh download.
  Future<InstallOutcome?> retry(UpdateInfo? info) async {
    if (state.downloadId >= 0 && state.progress.stage == DownloadStage.done) {
      state = state.copyWith(phase: DownloadPhase.ready);
      return install();
    }
    await _forget();
    // Reached from the pending-download entry point there is no release to
    // re-download from; clearing the dead download is all that is on offer.
    if (info != null) await start(info);
    return null;
  }

  /// Leaves the failed state so the dialog can offer the download again.
  Future<void> reset() => _forget();

  Future<void> _forget() async {
    _stopTimer();
    state = const UpdateDownloadState();
    await _persist(-1, null);
  }

  void _fail(Object cause, {DownloadProgress? progress, bool forget = true}) {
    _stopTimer();
    ref.read(errorLogProvider).record(KivoFailure(KivoOp.updateInstall, cause));
    state = state.copyWith(
      phase: DownloadPhase.failed,
      progress: progress ?? state.progress,
      downloadId: forget ? -1 : null,
    );
    if (forget) unawaited(_persist(-1, null));
  }

  Future<void> _persist(int id, String? version) async {
    final s = ref.read(settingsProvider);
    if (s.pendingUpdateDownloadId == id && s.pendingUpdateVersion == version) {
      return;
    }
    await ref.read(settingsProvider.notifier).set(
        s.copyWith(pendingUpdateDownloadId: id, pendingUpdateVersion: version));
  }

  void _syncTimer() {
    if (_watchers == 0 || !state.isBusy) return;
    _timer ??= Timer.periodic(updatePollInterval, (_) => refresh());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

final updateDownloadProvider =
    NotifierProvider<UpdateDownloadNotifier, UpdateDownloadState>(
        UpdateDownloadNotifier.new);
