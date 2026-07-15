import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeAppInstaller records install + open, honors outcome', () async {
    final i = FakeAppInstaller(version: '1.0.0', abi: 'arm64-v8a')
      ..installOutcome = InstallOutcome.needsPermission;
    expect(await i.appVersion(), '1.0.0');
    expect(await i.primaryAbi(), 'arm64-v8a');
    expect(await i.downloadAndInstall('u', 'kivo.apk'), InstallOutcome.needsPermission);
    expect(i.installed.single, ('u', 'kivo.apk'));
    await i.openUrl('r');
    expect(i.openedUrls.single, 'r');
  });
}
