import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeAppInstaller records the queue, the install and the open', () async {
    final i = FakeAppInstaller(version: '1.0.0', abi: 'arm64-v8a', nextDownloadId: 3)
      ..installOutcome = InstallOutcome.needsPermission;
    expect(await i.appVersion(), '1.0.0');
    expect(await i.primaryAbi(), 'arm64-v8a');

    expect(await i.enqueueUpdate('u', 'kivo.apk'), 3);
    expect(i.enqueued.single, ('u', 'kivo.apk'));

    expect(await i.installDownload(3), InstallOutcome.needsPermission);
    expect(i.installs.single, 3);

    await i.cancelDownload(3);
    expect(i.cancelled.single, 3);

    await i.openUrl('r');
    expect(i.openedUrls.single, 'r');
  });

  test('downloadStatus only knows the id it handed out', () async {
    final i = FakeAppInstaller(nextDownloadId: 3);
    expect((await i.downloadStatus(3)).stage, DownloadStage.running);
    expect((await i.downloadStatus(4)).stage, DownloadStage.gone);
  });
}
