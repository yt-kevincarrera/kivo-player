import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
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
            IconButton(color: Colors.white38, icon: KivoIcon(KivoIcons.lock, size: 24, color: Colors.white38), onPressed: null),
            IconButton(color: Colors.white38, icon: KivoIcon(KivoIcons.aspect, size: 24, color: Colors.white38), onPressed: null),
            IconButton(color: Colors.white38, icon: KivoIcon(KivoIcons.rotate, size: 24, color: Colors.white38), onPressed: null),
          ],
        ),
      ],
    );
  }
}
