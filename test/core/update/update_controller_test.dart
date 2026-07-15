import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_providers.dart';
import 'package:kivo_player/platform/app_installer_provider.dart';
import '../../fakes/fakes.dart';

UpdateInfo _info(String v) =>
    UpdateInfo(version: v, tagName: 'v$v', apkUrl: 'u', releaseUrl: 'r', notes: 'n');

Future<ProviderContainer> _c({
  required FakeUpdateChecker checker,
  required FakeAppInstaller installer,
}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    appInstallerProvider.overrideWithValue(installer),
    updateCheckerProvider.overrideWithValue(checker),
  ]);
}

void main() {
  test('shouldAutoCheck: enabled + >=24h', () {
    const day = 86400000;
    expect(shouldAutoCheck(enabled: true, nowMs: day, lastMs: 0), true);
    expect(shouldAutoCheck(enabled: true, nowMs: day - 1, lastMs: 0), false);
    expect(shouldAutoCheck(enabled: false, nowMs: day * 5, lastMs: 0), false);
  });

  test('check returns available when the release is newer', () async {
    final checker = FakeUpdateChecker(result: _info('1.1.0'));
    final installer = FakeAppInstaller(version: '1.0.0');
    final c = await _c(checker: checker, installer: installer);
    addTearDown(c.dispose);
    final r = await c.read(updateControllerProvider).check();
    expect(r.status, UpdateStatus.available);
    expect(r.info!.version, '1.1.0');
    // throttle timestamp persisted
    expect(c.read(settingsProvider).lastUpdateCheckMs > 0, true);
  });

  test('check returns upToDate when not newer', () async {
    final c = await _c(
      checker: FakeUpdateChecker(result: _info('1.0.0')),
      installer: FakeAppInstaller(version: '1.0.0'),
    );
    addTearDown(c.dispose);
    expect((await c.read(updateControllerProvider).check()).status, UpdateStatus.upToDate);
  });

  test('check returns error when the checker yields null', () async {
    final c = await _c(
      checker: FakeUpdateChecker()..throwsNull = true,
      installer: FakeAppInstaller(version: '1.0.0'),
    );
    addTearDown(c.dispose);
    expect((await c.read(updateControllerProvider).check()).status, UpdateStatus.error);
  });

  test('auto check suppresses a skipped version; manual does not', () async {
    final c = await _c(
      checker: FakeUpdateChecker(result: _info('1.1.0')),
      installer: FakeAppInstaller(version: '1.0.0'),
    );
    addTearDown(c.dispose);
    await c.read(updateControllerProvider).skip('1.1.0');
    expect((await c.read(updateControllerProvider).check()).status, UpdateStatus.upToDate);
    expect((await c.read(updateControllerProvider).check(manual: true)).status, UpdateStatus.available);
  });

  test('startUpdate forwards to the installer with a versioned file name', () async {
    final installer = FakeAppInstaller(version: '1.0.0');
    final c = await _c(checker: FakeUpdateChecker(), installer: installer);
    addTearDown(c.dispose);
    await c.read(updateControllerProvider).startUpdate(_info('1.1.0'));
    expect(installer.installed.single.$1, 'u');
    expect(installer.installed.single.$2, 'kivo-1.1.0.apk');
  });
}
