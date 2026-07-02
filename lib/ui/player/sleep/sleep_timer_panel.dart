import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/sleep/sleep_timer.dart';

Future<void> showSleepTimerPanel(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet();
  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  late int _minutes; // 5..120
  bool _episodeSelected = false;

  @override
  void initState() {
    super.initState();
    _minutes = ref.read(settingsProvider).sleepTimerLastMinutes.clamp(5, 120);
  }

  void _start() {
    final n = ref.read(sleepTimerProvider.notifier);
    if (_episodeSelected) {
      n.startEpisode();
    } else {
      n.startFixed(Duration(minutes: _minutes));
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).set(s.copyWith(sleepTimerLastMinutes: _minutes));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(sleepTimerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Text('Temporizador de apagado',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded, size: 15, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (active == null) ..._selectorChildren() else ..._activeChildren(active),
          ],
        ),
      ),
    );
  }

  List<Widget> _selectorChildren() {
    return [
      const _Eyebrow('Duración'),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StepButton(label: '−', onTap: () => setState(() {
            _minutes = (_minutes - 5).clamp(5, 120);
            _episodeSelected = false;
          })),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('$_minutes min',
                style: TextStyle(
                  color: _episodeSelected ? Colors.white38 : KivoColors.gold,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          _StepButton(label: '+', onTap: () => setState(() {
            _minutes = (_minutes + 5).clamp(5, 120);
            _episodeSelected = false;
          })),
        ],
      ),
      const SizedBox(height: 8),
      _SegmentMeter(
        litFraction: _episodeSelected ? 0 : _minutes / 120,
        onSegmentTap: (i) => setState(() {
          _minutes = (i + 1) * 15;
          _episodeSelected = false;
        }),
      ),
      const _Eyebrow('O bien'),
      _EpisodeCard(
        selected: _episodeSelected,
        onTap: () => setState(() => _episodeSelected = !_episodeSelected),
      ),
      const SizedBox(height: 12),
      _PrimaryButton(
        label: _episodeSelected ? 'Iniciar · Al terminar el episodio' : 'Iniciar · $_minutes min',
        onTap: _start,
      ),
    ];
  }

  List<Widget> _activeChildren(SleepTimerState st) {
    final total = st.original.inMilliseconds;
    final frac = total == 0 ? 0.0 : (st.remaining.inMilliseconds / total).clamp(0.0, 1.0);
    return [
      const SizedBox(height: 4),
      Center(
        child: Text(fmtDuration(st.remaining),
            style: const TextStyle(
              color: KivoColors.gold,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Text(
            st.mode == SleepTimerMode.fixed
                ? 'restante · de ${st.original.inMinutes} min'
                : 'hasta el final del episodio',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
      _SegmentMeter(litFraction: frac, onSegmentTap: null),
      const SizedBox(height: 14),
      if (st.mode == SleepTimerMode.fixed)
        Row(
          children: [
            Expanded(child: _GhostButton(label: 'Desactivar', onTap: () => ref.read(sleepTimerProvider.notifier).cancel())),
            const SizedBox(width: 8),
            Expanded(
              child: _PrimaryButton(
                label: 'Extender +${st.original.inMinutes}',
                onTap: () => ref.read(sleepTimerProvider.notifier).extend(),
              ),
            ),
          ],
        )
      else
        _GhostButton(label: 'Desactivar', onTap: () => ref.read(sleepTimerProvider.notifier).cancel()),
    ];
  }
}

class _Eyebrow extends StatelessWidget {
  final String label;
  const _Eyebrow(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            )),
      );
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      );
}

/// The signature segmented meter: 8 segments × 15 min. Tapping segment i sets
/// (i+1)×15 min (when [onSegmentTap] is non-null); a null callback renders the
/// read-only draining variant used while the timer runs.
class _SegmentMeter extends StatelessWidget {
  final double litFraction; // 0..1
  final ValueChanged<int>? onSegmentTap;
  const _SegmentMeter({required this.litFraction, required this.onSegmentTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 8; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 7 ? 0 : 5),
                  child: GestureDetector(
                    onTap: onSegmentTap == null ? null : () => onSegmentTap!(i),
                    child: Container(
                      height: 22,
                      decoration: BoxDecoration(
                        color: (i + 1) / 8 <= litFraction + 0.001
                            ? KivoColors.gold
                            : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (onSegmentTap != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (var i = 0; i < 8; i++)
                  Expanded(
                    child: Text('${(i + 1) * 15}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _EpisodeCard({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? KivoColors.gold.withValues(alpha: 0.16) : const Color(0xFF182036),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: selected ? KivoColors.gold.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? KivoColors.gold.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.movie_outlined,
                  size: 16, color: selected ? KivoColors.gold : Colors.white70),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Al terminar el episodio',
                      style: TextStyle(
                        color: selected ? KivoColors.gold : Colors.white,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      )),
                  const SizedBox(height: 1),
                  Text('Se detiene cuando termine este video',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_rounded, size: 18, color: KivoColors.gold),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: KivoColors.gold,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF231705), fontWeight: FontWeight.w800, fontSize: 13.5)),
        ),
      );
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
      );
}
