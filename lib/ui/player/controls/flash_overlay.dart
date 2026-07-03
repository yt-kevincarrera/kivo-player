import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/flash_state.dart';

class FlashOverlay extends ConsumerWidget {
  const FlashOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msg = ref.watch(flashProvider);
    if (msg == null) return const SizedBox.shrink();
    return IgnorePointer(
      // Upper third, not centered — otherwise it collides with the play/skip
      // controls (same placement as the seek/speed HUD chip).
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            msg,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
