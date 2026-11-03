import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/android/media_kit_thumbnailer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [(1920, 1080), (1080, 1920), (352, 240), (64, 48)]) {
    test(
      'thumbnail fits 320x180 without stretching or enlarging $size',
      () async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final original = await picture.toImage(size.$1, size.$2);
        final encoded = await original.toByteData(
          format: ui.ImageByteFormat.png,
        );
        original.dispose();
        picture.dispose();
        final bytes = await resizeLibraryThumbnail(
          encoded!.buffer.asUint8List(),
        );
        expect(bytes, isNotNull);
        final codec = await ui.instantiateImageCodec(bytes!);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, lessThanOrEqualTo(320));
        expect(image.height, lessThanOrEqualTo(180));
        expect(image.width, lessThanOrEqualTo(size.$1));
        expect(image.height, lessThanOrEqualTo(size.$2));
        expect(image.width / image.height, closeTo(size.$1 / size.$2, 0.02));
        image.dispose();
        codec.dispose();
      },
    );
  }
}
