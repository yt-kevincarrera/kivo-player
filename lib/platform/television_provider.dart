import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device identity comes from Android's UI mode, never a screen-size guess.
/// Tests and non-TV hosts stay on the existing phone experience by default.
final isTelevisionProvider = Provider<bool>((ref) => false);

Future<bool> detectTelevision() async {
  try {
    return await const MethodChannel(
          'kivo/device',
        ).invokeMethod<bool>('isTelevision') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
