import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/android/android_frame_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kivo/frames');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('unsupported Android preview does not fail opening the video', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw PlatformException(
        code: 'PREPARE_FAILED',
        message: 'setDataSource failed',
      );
    });
    final extractor = AndroidFrameExtractor();
    await extractor.prepare('/movies/sample.rm');
    expect(await extractor.frameAt(const Duration(seconds: 2)), isNull);
    expect(calls, ['prepare']);
  });

  test(
    'a supported video restores previews after an unsupported one',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'prepare' && call.arguments['path'] == '/a.rm') {
          throw PlatformException(code: 'PREPARE_FAILED');
        }
        return call.method == 'frameAt' ? Uint8List.fromList([1, 2]) : null;
      });
      final extractor = AndroidFrameExtractor();
      await extractor.prepare('/a.rm');
      await extractor.prepare('/b.mp4');
      expect(await extractor.frameAt(Duration.zero), [1, 2]);
      await extractor.release();
      expect(await extractor.frameAt(Duration.zero), isNull);
    },
  );
  test(
    'suspend frees decoding resources without losing the selected source',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'frameAt' ? Uint8List.fromList([42]) : null;
      });
      final extractor = AndroidFrameExtractor();
      await extractor.prepare('/a.avi');
      expect(await extractor.frameAt(Duration.zero), [42]);
      await extractor.suspend();
      expect(await extractor.frameAt(const Duration(seconds: 5)), [42]);
      expect(calls, ['prepare', 'frameAt', 'suspend', 'frameAt']);
      await extractor.release();
      expect(await extractor.frameAt(Duration.zero), isNull);
    },
  );
}
