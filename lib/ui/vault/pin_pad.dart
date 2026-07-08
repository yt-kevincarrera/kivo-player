import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric PIN entry. Calls [onComplete] when [length] digits are entered,
/// then clears itself so the parent can show an error and let the user retry.
class PinPad extends StatefulWidget {
  final String title;
  final String? error;
  final int length;
  final ValueChanged<String> onComplete;
  const PinPad({
    super.key,
    required this.title,
    required this.onComplete,
    this.error,
    this.length = 4,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _tap(String d) {
    if (_pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final done = _pin;
      _pin = '';
      widget.onComplete(done);
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) {
            final filled = i < _pin.length;
            return Container(
              key: Key('pin-dot-$i'),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? cs.secondary : Colors.transparent,
                border: Border.all(color: cs.secondary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 20,
          child: widget.error == null
              ? null
              : Text(widget.error!, style: TextStyle(color: cs.error, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        for (final row in const [['1','2','3'],['4','5','6'],['7','8','9']])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _key(cs, d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 76),
            _key(cs, '0'),
            SizedBox(
              width: 76,
              child: IconButton(
                key: const Key('pin-backspace'),
                icon: Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant),
                onPressed: _back,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(ColorScheme cs, String d) => SizedBox(
        width: 76, height: 66,
        child: InkWell(
          key: Key('pin-key-$d'),
          borderRadius: BorderRadius.circular(40),
          onTap: () => _tap(d),
          child: Center(child: Text(d, style: TextStyle(color: cs.onSurface, fontSize: 26, fontWeight: FontWeight.w500))),
        ),
      );
}
