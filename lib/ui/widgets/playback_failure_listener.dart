import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/error_log_provider.dart';
import '../../core/errors/kivo_failure.dart';
import '../../core/navigation.dart';
import '../../player/engine/playback_provider.dart';
import 'failure_snack_bar.dart';

final _unplayableProvider = StreamProvider<String>(
    (ref) => ref.watch(playbackEngineProvider).unplayableStream);

/// Shows native failures which arrive after the asynchronous open returned.
class PlaybackFailureListener extends ConsumerWidget {
  const PlaybackFailureListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(_unplayableProvider, (previous, next) {
      final message = next.asData?.value;
      final navigatorContext = kivoNavigatorKey.currentContext;
      if (message != null) {
        final failure = ref.read(errorLogProvider).record(
            KivoFailure(KivoOp.openVideo, StateError(message)));
        if (navigatorContext != null && navigatorContext.mounted) {
          showFailureSnackBar(navigatorContext, failure.op, cause: failure.cause);
        }
      }
    });
    return child;
  }
}
