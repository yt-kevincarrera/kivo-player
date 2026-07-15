import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/settings_provider.dart';
import '../../platform/app_installer_provider.dart';
import '../../platform/interfaces/app_installer.dart';
import 'update_checker.dart';
import 'update_info.dart';
import 'version_compare.dart';

const _dayMs = 86400000;

/// Auto-check only when enabled and at least 24h since the last check.
bool shouldAutoCheck({required bool enabled, required int nowMs, required int lastMs}) =>
    enabled && (nowMs - lastMs) >= _dayMs;

enum UpdateStatus { upToDate, available, error }

class UpdateResult {
  final UpdateStatus status;
  final UpdateInfo? info;
  const UpdateResult(this.status, [this.info]);
}

final updateCheckerProvider = Provider<UpdateChecker>(
    (ref) => GithubUpdateChecker(() => ref.read(appInstallerProvider).primaryAbi()));

class UpdateController {
  final Ref _ref;
  UpdateController(this._ref);

  Future<UpdateResult> check({bool manual = false}) async {
    final info = await _ref.read(updateCheckerProvider).fetchLatest();
    // Record the check time regardless of outcome (throttle).
    final settings = _ref.read(settingsProvider);
    await _ref.read(settingsProvider.notifier).set(settings.copyWith(
        lastUpdateCheckMs: DateTime.now().millisecondsSinceEpoch));
    if (info == null) return const UpdateResult(UpdateStatus.error);
    final current = await _ref.read(appInstallerProvider).appVersion();
    if (!isNewer(info.version, current)) return const UpdateResult(UpdateStatus.upToDate);
    // On an automatic check, a version the user chose to skip is suppressed.
    if (!manual && info.version == _ref.read(settingsProvider).skippedUpdateVersion) {
      return const UpdateResult(UpdateStatus.upToDate);
    }
    return UpdateResult(UpdateStatus.available, info);
  }

  Future<InstallOutcome> startUpdate(UpdateInfo info) {
    return _ref.read(appInstallerProvider)
        .downloadAndInstall(info.apkUrl!, 'kivo-${info.version}.apk');
  }

  Future<void> openInBrowser(UpdateInfo info) =>
      _ref.read(appInstallerProvider).openUrl(info.releaseUrl);

  Future<void> skip(String version) async {
    final s = _ref.read(settingsProvider);
    await _ref.read(settingsProvider.notifier).set(s.copyWith(skippedUpdateVersion: version));
  }
}

final updateControllerProvider = Provider<UpdateController>((ref) => UpdateController(ref));
