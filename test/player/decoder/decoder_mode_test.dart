import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/decoder/decoder_mode.dart';

void main() {
  group('DecoderMode storage', () {
    test('parses the stored ids and falls back to auto on junk', () {
      expect(DecoderMode.fromId('auto'), DecoderMode.auto);
      expect(DecoderMode.fromId('hw'), DecoderMode.hardware);
      expect(DecoderMode.fromId('sw'), DecoderMode.software);
      expect(DecoderMode.fromId('turbo'), DecoderMode.auto);
      expect(DecoderMode.fromId(null), DecoderMode.auto);
    });

    test('ids round-trip', () {
      for (final m in DecoderMode.values) {
        expect(DecoderMode.fromId(m.id), m);
      }
    });
  });

  group('mpv mapping', () {
    test('auto and hardware ask mpv for hardware, software for none', () {
      expect(DecoderMode.auto.mpvHwdec, 'auto-safe');
      expect(DecoderMode.hardware.mpvHwdec, 'auto-safe');
      expect(DecoderMode.software.mpvHwdec, 'no');
    });

    test('only auto runs the watchdog', () {
      expect(DecoderMode.auto.watched, isTrue);
      expect(DecoderMode.hardware.watched, isFalse);
      expect(DecoderMode.software.watched, isFalse);
    });
  });

  group('resolveDecoderMode', () {
    test('the per-video override wins over the global default', () {
      expect(
          resolveDecoderMode(global: 'auto', perVideo: 'sw'), DecoderMode.software);
      expect(
          resolveDecoderMode(global: 'sw', perVideo: 'hw'), DecoderMode.hardware);
    });

    test('no override follows the global default', () {
      expect(resolveDecoderMode(global: 'sw', perVideo: null),
          DecoderMode.software);
      expect(resolveDecoderMode(global: 'auto', perVideo: null),
          DecoderMode.auto);
    });
  });

  group('overrideFor', () {
    test('choosing the global default stores nothing', () {
      expect(overrideFor(DecoderMode.software, global: 'sw'), isNull);
      expect(overrideFor(DecoderMode.auto, global: 'auto'), isNull);
    });

    test('choosing anything else stores it', () {
      expect(overrideFor(DecoderMode.software, global: 'auto'), 'sw');
      expect(overrideFor(DecoderMode.hardware, global: 'auto'), 'hw');
      expect(overrideFor(DecoderMode.auto, global: 'sw'), 'auto');
    });
  });

  group('isHardwareActive', () {
    test('reads mpv hwdec-current', () {
      expect(isHardwareActive('mediacodec-copy'), isTrue);
      expect(isHardwareActive('mediacodec'), isTrue);
      expect(isHardwareActive('no'), isFalse);
      expect(isHardwareActive(''), isFalse);
      expect(isHardwareActive(null), isFalse);
    });
  });
}
