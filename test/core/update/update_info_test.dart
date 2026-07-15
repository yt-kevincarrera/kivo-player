// test/core/update/update_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/update_info.dart';

List<Map<String, dynamic>> _assets() => [
      {'name': 'kivo-1.0.1-armeabi-v7a.apk', 'browser_download_url': 'u-v7a'},
      {'name': 'kivo-1.0.1-arm64-v8a.apk', 'browser_download_url': 'u-arm64'},
      {'name': 'kivo-1.0.1-x86_64.apk', 'browser_download_url': 'u-x64'},
    ];

void main() {
  test('picks the asset matching the device ABI', () {
    expect(pickApkAsset(_assets(), 'arm64-v8a'), 'u-arm64');
    expect(pickApkAsset(_assets(), 'armeabi-v7a'), 'u-v7a');
    expect(pickApkAsset(_assets(), 'x86_64'), 'u-x64');
  });

  test('falls back to arm64-v8a for an unknown ABI', () {
    expect(pickApkAsset(_assets(), 'mips'), 'u-arm64');
  });

  test('falls back to the first .apk when no abi match', () {
    final assets = [
      {'name': 'notes.txt', 'browser_download_url': 'u-txt'},
      {'name': 'kivo-universal.apk', 'browser_download_url': 'u-apk'},
    ];
    expect(pickApkAsset(assets, 'arm64-v8a'), 'u-apk');
  });

  test('returns null when there is no apk', () {
    expect(pickApkAsset([{'name': 'x.txt', 'browser_download_url': 'u'}], 'arm64-v8a'), null);
    expect(pickApkAsset(const [], 'arm64-v8a'), null);
  });
}
