import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/android/android_all_files_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kivo/media');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // Regression: request() went through permission_handler, which returns
  // "granted" without opening anything once the permission is on — so the
  // Ajustes row did nothing at all for the people who had granted it, and
  // there was no way back to revoke it.
  test('request always opens the system page, and reports what the user left it at', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return false; // the user switched it off on that page
    });

    expect(await AndroidAllFilesAccess().request(), isFalse);
    expect(calls, ['openAllFilesAccess']);
  });
}
