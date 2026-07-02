import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../platform/interfaces/subtitle_finder.dart';
import '../../../platform/subtitle_finder_provider.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/engine/playback_engine.dart';
import '../../../player/open/video_source.dart';
import '../../../player/tracks/track_selection.dart';

Future<void> showSubtitlePicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _TrackPickerSheet(isSubtitles: true),
  );
}

Future<void> showAudioPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _TrackPickerSheet(isSubtitles: false),
  );
}

/// Subtitles get two tabs ("Pistas" / "Estilo"); audio has no style tab,
/// so it renders the track list directly with no tab bar at all.
class _TrackPickerSheet extends ConsumerStatefulWidget {
  final bool isSubtitles;
  const _TrackPickerSheet({required this.isSubtitles});

  @override
  ConsumerState<_TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends ConsumerState<_TrackPickerSheet> {
  bool _styleTab = false;

  @override
  Widget build(BuildContext context) {
    final engine = ref.read(playbackEngineProvider);
    final session = ref.watch(currentVideoProvider);
    final showStyle = widget.isSubtitles && _styleTab;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _Grabber()),
            _SheetHeader(title: widget.isSubtitles ? 'Subtítulos' : 'Audio'),
            if (widget.isSubtitles) ...[
              const SizedBox(height: 4),
              _TabBar(
                value: _styleTab,
                onChanged: (v) => setState(() => _styleTab = v),
              ),
              const SizedBox(height: 4),
            ] else
              const SizedBox(height: 10),
            if (showStyle)
              const _StyleSection()
            else
              StreamBuilder<List<MediaTrack>>(
                stream: widget.isSubtitles ? engine.subtitleTracksStream : engine.audioTracksStream,
                builder: (context, tracksSnap) {
                  final tracks = tracksSnap.data ?? const <MediaTrack>[];
                  return StreamBuilder<MediaTrack?>(
                    stream: widget.isSubtitles
                        ? engine.currentSubtitleTrackStream
                        : engine.currentAudioTrackStream,
                    builder: (context, currentSnap) {
                      final current = currentSnap.data;
                      return _TracksSection(
                        isSubtitles: widget.isSubtitles,
                        tracks: tracks,
                        current: current,
                        session: session,
                        engine: engine,
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  const _SheetHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
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
    );
  }
}

/// Segmented "Pistas" / "Estilo" switcher — same visual language as the
/// gold-filled active chip used elsewhere (e.g. SpeedPanel's presets).
class _TabBar extends StatelessWidget {
  final bool value; // false = Pistas, true = Estilo
  final ValueChanged<bool> onChanged;
  const _TabBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(child: _TabLabel(label: 'Pistas', active: !value, onTap: () => onChanged(false))),
          const SizedBox(width: 4),
          Expanded(child: _TabLabel(label: 'Estilo', active: value, onTap: () => onChanged(true))),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabLabel({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? KivoColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF231705) : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  final String label;
  const _SectionEyebrow({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TracksSection extends ConsumerWidget {
  final bool isSubtitles;
  final List<MediaTrack> tracks;
  final MediaTrack? current;
  final VideoSession? session;
  final PlaybackEngine engine;

  const _TracksSection({
    required this.isSubtitles,
    required this.tracks,
    required this.current,
    required this.session,
    required this.engine,
  });

  void _turnOff(WidgetRef ref) {
    engine.setSubtitleTrack(null);
    final s = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).set(s.copyWith(subtitlesEnabledByDefault: false));
  }

  void _turnOn(WidgetRef ref) {
    final s = ref.read(settingsProvider);
    final pick = selectSubtitleTrack(
      tracks: tracks,
      enabledByDefault: true,
      preferredLanguage: s.preferredSubtitleLanguage,
    );
    if (pick != null) engine.setSubtitleTrack(pick.id);
    ref.read(settingsProvider.notifier).set(s.copyWith(subtitlesEnabledByDefault: true));
  }

  void _pickTrack(BuildContext context, WidgetRef ref, MediaTrack t) {
    if (isSubtitles) {
      engine.setSubtitleTrack(t.id);
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).set(s.copyWith(
            subtitlesEnabledByDefault: true,
            preferredSubtitleLanguage: t.language ?? s.preferredSubtitleLanguage,
          ));
    } else {
      engine.setAudioTrack(t.id);
      final s = ref.read(settingsProvider);
      ref.read(settingsProvider.notifier).set(s.copyWith(
            preferredAudioLanguage: t.language ?? s.preferredAudioLanguage,
          ));
    }
    Navigator.of(context).pop();
  }

  void _pickExternal(BuildContext context, WidgetRef ref, ExternalSubtitle e) {
    engine.setExternalSubtitle(e.uri, title: e.displayName);
    final lang = languageFromFilename(e.displayName);
    final s = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).set(s.copyWith(
          subtitlesEnabledByDefault: true,
          preferredSubtitleLanguage: lang ?? s.preferredSubtitleLanguage,
        ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsOn = ref.watch(settingsProvider).subtitlesEnabledByDefault;

    return FutureBuilder<List<ExternalSubtitle>>(
      future: (isSubtitles && session?.folder != null)
          ? ref.read(subtitleFinderProvider).findNear(session!.folder!)
          : Future.value(const []),
      builder: (context, externalSnap) {
        final external = externalSnap.data ?? const <ExternalSubtitle>[];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isSubtitles) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF182036),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Mostrar subtítulos',
                          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: subsOn,
                      activeThumbColor: KivoColors.gold,
                      onChanged: (v) => v ? _turnOn(ref) : _turnOff(ref),
                    ),
                  ],
                ),
              ),
            ],
            if (tracks.isNotEmpty) ...[
              if (isSubtitles) const _SectionEyebrow(label: 'En el video'),
              for (final t in tracks)
                _TrackCard(
                  icon: isSubtitles ? Icons.closed_caption_outlined : Icons.graphic_eq_rounded,
                  label: t.title ?? t.language ?? t.id,
                  sublabel: t.isDefault ? 'Pista incrustada · predeterminada' : 'Pista incrustada',
                  active: current?.id == t.id,
                  onTap: () => _pickTrack(context, ref, t),
                ),
            ],
            if (isSubtitles && external.isNotEmpty) ...[
              const _SectionEyebrow(label: 'En la carpeta'),
              for (final e in external)
                _TrackCard(
                  icon: Icons.folder_outlined,
                  label: e.displayName,
                  sublabel: 'Archivo local',
                  active: current?.id == e.uri,
                  onTap: () => _pickExternal(context, ref, e),
                ),
            ],
            if (tracks.isEmpty && (!isSubtitles || external.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  isSubtitles ? 'Este video no tiene subtítulos disponibles.' : 'Este video no tiene otras pistas de audio.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TrackCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool active;
  final VoidCallback onTap;

  const _TrackCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? KivoColors.gold.withValues(alpha: 0.16) : const Color(0xFF182036),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? KivoColors.gold.withValues(alpha: 0.5) : Colors.transparent),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: active ? KivoColors.gold.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: active ? KivoColors.gold : Colors.white70),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? KivoColors.gold : Colors.white,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(sublabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
                  ],
                ),
              ),
              if (active) const Icon(Icons.check_rounded, size: 18, color: KivoColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

class KivoSettingsPatch {
  final double? fontSize;
  final int? textColor;
  final int? backgroundColor;
  const KivoSettingsPatch({this.fontSize, this.textColor, this.backgroundColor});
}

class _StyleSection extends ConsumerWidget {
  const _StyleSection();

  static const _textSwatches = [0xFFFFFFFF, 0xFF000000, 0xFFFFEB3B, 0xFF2D6CFF, 0xFFE8B84B];
  static const _bgSwatches = [
    (value: 0xB3000000, label: 'Semi-opaco'),
    (value: 0x00000000, label: 'Transparente'),
    (value: 0xFF000000, label: 'Opaco'),
  ];

  void _apply(WidgetRef ref, KivoSettingsPatch patch) {
    final s = ref.read(settingsProvider);
    final updated = s.copyWith(
      subtitleFontSize: patch.fontSize ?? s.subtitleFontSize,
      subtitleTextColor: patch.textColor ?? s.subtitleTextColor,
      subtitleBackgroundColor: patch.backgroundColor ?? s.subtitleBackgroundColor,
    );
    ref.read(settingsProvider.notifier).set(updated);
    ref.read(playbackEngineProvider).setSubtitleStyle(
          fontSize: updated.subtitleFontSize,
          textColorArgb: updated.subtitleTextColor,
          backgroundColorArgb: updated.subtitleBackgroundColor,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final fontSize = s.subtitleFontSize.clamp(16, 48);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live preview — same size/color/background PlaybackEngine.setSubtitleStyle
        // applies to the real video, so changes below are WYSIWYG.
        Container(
          height: 110,
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF182338), Color(0xFF070A12)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Color(s.subtitleBackgroundColor),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Estamos cerca de encontrarlo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(s.subtitleTextColor),
                  fontSize: fontSize.toDouble() * 0.62, // scaled to fit the preview box
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
        const _SectionEyebrow(label: 'Tamaño'),
        Row(
          children: [
            _StepButton(
              label: 'A',
              small: true,
              onTap: () => _apply(ref, KivoSettingsPatch(fontSize: (fontSize.toDouble() - 2).clamp(16, 48))),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: KivoColors.gold,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                  thumbColor: KivoColors.gold,
                  overlayColor: KivoColors.gold.withValues(alpha: 0.15),
                ),
                child: Slider(
                  min: 16,
                  max: 48,
                  value: fontSize.toDouble(),
                  onChanged: (v) => _apply(ref, KivoSettingsPatch(fontSize: v)),
                ),
              ),
            ),
            _StepButton(
              label: 'A',
              small: false,
              onTap: () => _apply(ref, KivoSettingsPatch(fontSize: (fontSize.toDouble() + 2).clamp(16, 48))),
            ),
            SizedBox(
              width: 30,
              child: Text(
                fontSize.round().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(color: KivoColors.gold, fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const _SectionEyebrow(label: 'Color de texto'),
        Row(
          children: [
            for (final c in _textSwatches)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _ColorSquare(
                  color: c,
                  active: s.subtitleTextColor == c,
                  onTap: () => _apply(ref, KivoSettingsPatch(textColor: c)),
                ),
              ),
          ],
        ),
        const _SectionEyebrow(label: 'Color de fondo'),
        Row(
          children: [
            for (final bg in _bgSwatches)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _BackgroundChip(
                    background: bg.value,
                    label: bg.label,
                    textColor: s.subtitleTextColor,
                    active: s.subtitleBackgroundColor == bg.value,
                    onTap: () => _apply(ref, KivoSettingsPatch(backgroundColor: bg.value)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final bool small;
  final VoidCallback onTap;
  const _StepButton({required this.label, required this.small, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: small ? 12 : 17)),
      ),
    );
  }
}

class _ColorSquare extends StatelessWidget {
  final int color;
  final bool active;
  final VoidCallback onTap;
  const _ColorSquare({required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLight = Color(color).computeLuminance() > 0.5;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: active
              ? [BoxShadow(color: KivoColors.gold.withValues(alpha: 0.6), blurRadius: 0, spreadRadius: 2)]
              : null,
        ),
        alignment: Alignment.center,
        child: active
            ? Icon(Icons.check_rounded, size: 15, color: isLight ? Colors.black87 : Colors.white)
            : null,
      ),
    );
  }
}

class _BackgroundChip extends StatelessWidget {
  final int background;
  final String label;
  final int textColor;
  final bool active;
  final VoidCallback onTap;

  const _BackgroundChip({
    required this.background,
    required this.label,
    required this.textColor,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: active ? KivoColors.gold : Colors.transparent, width: 2),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF223357), Color(0xFF0C1120)],
          ),
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 5,
              left: 0,
              right: 0,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8.5, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Color(background), borderRadius: BorderRadius.circular(3)),
                child: Text('Ab', style: TextStyle(color: Color(textColor), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
