import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:media_kit/media_kit.dart';

/// A separate, silent software decoder. Never borrows the playback engine or
/// creates a Flutter texture. Serial work bounds memory while scrolling.
class MediaKitThumbnailer {
  Future<void> _tail = Future.value();

  Future<Uint8List?> thumbnail(String uri) {
    final result = _tail.then((_) => _thumbnail(uri));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Uint8List?> _thumbnail(String uri) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        vo: 'null',
        muted: true,
        bufferSize: 2 * 1024 * 1024,
      ),
    );
    try {
      final native = player.platform as NativePlayer;
      // media_kit starts with vid=no until a VideoController attaches. This
      // headless player needs decoding enabled explicitly, without a texture.
      await native.setProperty('vid', 'auto');
      await native.setProperty('aid', 'no');
      await native.setProperty('sid', 'no');
      await native.setProperty('hwdec', 'no');
      await player.open(Media(uri), play: false);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        final bytes = await player.screenshot();
        if (bytes != null && bytes.isNotEmpty) {
          return resizeLibraryThumbnail(bytes);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } finally {
      await player.dispose();
    }
  }
}

/// The bundled FFmpeg omits its scale filter. Resize with Flutter's codec so
/// cached thumbnails stay small regardless of the source video's resolution.
Future<Uint8List?> resizeLibraryThumbnail(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      math.min(320 / descriptor.width, 180 / descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
