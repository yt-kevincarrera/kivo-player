import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/kivo_failure.dart';
import '../../../player/cast/cast_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/open/video_source.dart';
import '../../widgets/failure_snack_bar.dart';
import 'cast_picker_sheet.dart';

/// From this width the cast button sits in the player's top bar; below it
/// (a portrait phone, where the bar has no room) it is a More-menu row.
/// One rule for both places, so it is always in exactly one of them.
const double kCastInBarMinWidth = 560;

/// The player's cast button: pick a TV, pause the phone, and send the video
/// there from where it was. A TV that refuses it gets KV-505.
Future<void> startCasting(BuildContext context, WidgetRef ref) async {
  final session = ref.read(currentVideoProvider);
  if (session == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final device = await showCastPicker(context);
  if (device == null || !context.mounted) return;
  final at = ref.read(positionProvider).value ?? Duration.zero;
  final duration = ref.read(durationProvider).value;
  await ref.read(playbackEngineProvider).pause();
  try {
    await ref
        .read(castControllerProvider.notifier)
        .start(
          device,
          source: session.playbackPath,
          title: session.displayName,
          resumeKey: session.resumeKey,
          startAt: at,
          duration: duration,
        );
  } on KivoFailure catch (f) {
    if (context.mounted) {
      showFailureSnackBarOn(messenger, context, f.op, cause: f.cause);
    }
  }
}
