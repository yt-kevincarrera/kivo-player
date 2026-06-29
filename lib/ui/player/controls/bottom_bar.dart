import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/control/player_controller.dart';
import '../speed/speed_panel.dart';
import 'seek_bar.dart';

class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(rateProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SeekBar(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => showSpeedPanel(context),
              child: Text('${rate.toStringAsFixed(2)}x',
                  style: const TextStyle(color: KivoColors.gold, fontWeight: FontWeight.w600)),
            ),
            const IconButton(color: Colors.white38, icon: Icon(Icons.lock_outline), onPressed: null),
            const IconButton(color: Colors.white38, icon: Icon(Icons.aspect_ratio), onPressed: null),
            const IconButton(color: Colors.white38, icon: Icon(Icons.screen_rotation), onPressed: null),
          ],
        ),
      ],
    );
  }
}
