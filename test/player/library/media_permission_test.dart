import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/library/media_permission.dart';

class _FakePerm implements MediaPermission {
  MediaAccess current;
  final MediaAccess afterRequest;
  _FakePerm(this.current, this.afterRequest);
  @override
  Future<MediaAccess> status() async => current;
  @override
  Future<MediaAccess> request() async => current = afterRequest;
}

void main() {
  test('provider exposes status, then request flips it', () async {
    final c = ProviderContainer(overrides: [
      mediaPermissionImplProvider
          .overrideWithValue(_FakePerm(MediaAccess.denied, MediaAccess.granted)),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(mediaPermissionProvider.future), MediaAccess.denied);
    await c.read(mediaPermissionProvider.notifier).request();
    expect(c.read(mediaPermissionProvider).value, MediaAccess.granted);
  });
}
