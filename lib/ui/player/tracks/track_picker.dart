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
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const _TrackPickerSheet(isSubtitles: false),
  );
}

class _TrackPickerSheet extends ConsumerWidget {
  final bool isSubtitles;
  const _TrackPickerSheet({required this.isSubtitles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final session = ref.watch(currentVideoProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            StreamBuilder<List<MediaTrack>>(
              stream: isSubtitles ? engine.subtitleTracksStream : engine.audioTracksStream,
              builder: (context, tracksSnap) {
                final tracks = tracksSnap.data ?? const <MediaTrack>[];
                return StreamBuilder<MediaTrack?>(
                  stream: isSubtitles
                      ? engine.currentSubtitleTrackStream
                      : engine.currentAudioTrackStream,
                  builder: (context, currentSnap) {
                    final current = currentSnap.data;
                    return _buildList(context, ref, tracks, current, session, engine);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<MediaTrack> tracks,
    MediaTrack? current,
    VideoSession? session,
    PlaybackEngine engine,
  ) {
    return FutureBuilder<List<ExternalSubtitle>>(
      future: (isSubtitles && session?.folder != null)
          ? ref.read(subtitleFinderProvider).findNear(session!.folder!)
          : Future.value(const []),
      builder: (context, externalSnap) {
        final external = externalSnap.data ?? const <ExternalSubtitle>[];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSubtitles)
              _OptionTile(
                label: 'Desactivado',
                active: current == null,
                onTap: () {
                  engine.setSubtitleTrack(null);
                  final s = ref.read(settingsProvider);
                  ref.read(settingsProvider.notifier).set(s.copyWith(subtitlesEnabledByDefault: false));
                  Navigator.of(context).pop();
                },
              ),
            for (final t in tracks)
              _OptionTile(
                label: t.title ?? t.language ?? t.id,
                active: current?.id == t.id,
                onTap: () {
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
                },
              ),
            for (final e in external)
              _OptionTile(
                label: e.displayName,
                active: current?.id == e.uri,
                onTap: () {
                  engine.setExternalSubtitle(e.uri, title: e.displayName);
                  final lang = languageFromFilename(e.displayName);
                  final s = ref.read(settingsProvider);
                  ref.read(settingsProvider.notifier).set(s.copyWith(
                        subtitlesEnabledByDefault: true,
                        preferredSubtitleLanguage: lang ?? s.preferredSubtitleLanguage,
                      ));
                  Navigator.of(context).pop();
                },
              ),
            if (isSubtitles) ...[
              const Divider(color: Colors.white24, height: 24),
              const _SubtitleStylePanel(),
            ],
          ],
        );
      },
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _OptionTile({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        label,
        style: TextStyle(
          color: active ? KivoColors.gold : Colors.white,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: active ? const Icon(Icons.check, color: KivoColors.gold) : null,
    );
  }
}

class _SubtitleStylePanel extends ConsumerWidget {
  const _SubtitleStylePanel();

  static const _swatches = [0xFFFFFFFF, 0xFF000000, 0xFFFFEB3B, 0xFF2D6CFF, 0xFFE8B84B];

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tamaño', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Slider(
          min: 16,
          max: 48,
          value: s.subtitleFontSize.clamp(16, 48),
          activeColor: KivoColors.gold,
          onChanged: (v) => _apply(ref, KivoSettingsPatch(fontSize: v)),
        ),
        const Text('Color de texto', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Row(
          children: [
            for (final c in _swatches)
              _ColorSwatch(
                color: c,
                active: s.subtitleTextColor == c,
                onTap: () => _apply(ref, KivoSettingsPatch(textColor: c)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Color de fondo', style: TextStyle(color: Colors.white70, fontSize: 12)),
        Row(
          children: [
            _ColorSwatch(
              color: 0xB3000000,
              active: s.subtitleBackgroundColor == 0xB3000000,
              onTap: () => _apply(ref, const KivoSettingsPatch(backgroundColor: 0xB3000000)),
            ),
            _ColorSwatch(
              color: 0x00000000,
              active: s.subtitleBackgroundColor == 0x00000000,
              onTap: () => _apply(ref, const KivoSettingsPatch(backgroundColor: 0x00000000)),
            ),
            _ColorSwatch(
              color: 0xFF000000,
              active: s.subtitleBackgroundColor == 0xFF000000,
              onTap: () => _apply(ref, const KivoSettingsPatch(backgroundColor: 0xFF000000)),
            ),
          ],
        ),
      ],
    );
  }
}

class KivoSettingsPatch {
  final double? fontSize;
  final int? textColor;
  final int? backgroundColor;
  const KivoSettingsPatch({this.fontSize, this.textColor, this.backgroundColor});
}

class _ColorSwatch extends StatelessWidget {
  final int color;
  final bool active;
  final VoidCallback onTap;
  const _ColorSwatch({required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? KivoColors.gold : Colors.white24,
            width: active ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}
