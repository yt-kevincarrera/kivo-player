import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../core/settings/kivo_settings.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/interfaces/subtitle_finder.dart';
import '../../../platform/subtitle_finder_provider.dart';
import '../../../platform/subtitle_transcoder_provider.dart';
import '../../../player/audio/audio_pipeline_controller.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/engine/playback_engine.dart';
import '../../../player/open/video_source.dart';
import '../../../player/tracks/manual_subtitle_controller.dart';
import '../../../player/subtitles/secondary_subtitle.dart';
import '../../../player/subtitles/subtitle_render_controller.dart';
import '../../../player/tracks/subtitle_encodings.dart';
import '../../../player/tracks/subtitle_loader.dart';
import '../../../player/tracks/track_selection.dart';
import '../../widgets/failure_snack_bar.dart';
import '../subtitles/subtitle_text.dart';
import 'track_sync_hud.dart';

part 'subtitle_encoding_sheet.dart';
part 'subtitle_style_controls.dart';

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
    final accent = Color(ref.watch(settingsProvider).accentColor);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _Grabber()),
        _SheetHeader(
          title: widget.isSubtitles
              ? context.l10n.playerSubtitlesTooltip
              : context.l10n.playerAudioTooltip,
        ),
        if (widget.isSubtitles) ...[
          const SizedBox(height: 4),
          _TabBar(
            value: _styleTab,
            accent: accent,
            onChanged: (v) => setState(() => _styleTab = v),
          ),
          const SizedBox(height: 4),
        ] else
          const SizedBox(height: 10),
      ],
    );

    final body = showStyle
        ? const _StyleSection()
        : StreamBuilder<List<MediaTrack>>(
            stream: widget.isSubtitles
                ? engine.subtitleTracksStream
                : engine.audioTracksStream,
            initialData: widget.isSubtitles
                ? engine.currentSubtitleTracks
                : engine.currentAudioTracks,
            builder: (context, tracksSnap) {
              final tracks = tracksSnap.data ?? const <MediaTrack>[];
              return StreamBuilder<MediaTrack?>(
                stream: widget.isSubtitles
                    ? engine.currentSubtitleTrackStream
                    : engine.currentAudioTrackStream,
                initialData: widget.isSubtitles
                    ? engine.currentSubtitleTrack
                    : engine.currentAudioTrack,
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
          );

    // Subtitles switch between two tabs of differing content height — a
    // fixed sheet height with the body scrolling inside it keeps the sheet
    // itself from jumping size when the tab changes. Audio has no tabs, so
    // it keeps the simpler wrap-content sizing.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: widget.isSubtitles
            ? SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    // Outside the scroll: the sample must stay in sight
                    // while any option below is being adjusted.
                    if (showStyle) const _StylePreview(),
                    Expanded(child: SingleChildScrollView(child: body)),
                  ],
                ),
              )
            // Wraps its content, but capped and scrollable: with the "Mejorar el
            // sonido" cards it no longer fits a landscape phone's height.
            : ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, body],
                  ),
                ),
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
        // Expanded + ellipsis: a long title (or a long translation of one)
        // must shorten, never push the close button off the sheet.
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ),
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
            child: const Icon(
              Icons.close_rounded,
              size: 15,
              color: Colors.white70,
            ),
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
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _TabBar({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

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
          Expanded(
            child: _TabLabel(
              label: context.l10n.playerTracksTabLabel,
              active: !value,
              accent: accent,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabLabel(
              label: context.l10n.playerTracksStyleTabLabel,
              active: value,
              accent: accent,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  const _TabLabel({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? onAccent(accent) : Colors.white70,
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
    // No lone top line once the subtitles are off.
    clearSecondarySubtitle(ref);
    ref.read(subtitleLoaderProvider).clear();
    final s = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .set(s.copyWith(subtitlesEnabledByDefault: false));
  }

  void _turnOn(WidgetRef ref) {
    final s = ref.read(settingsProvider);
    final pick = selectSubtitleTrack(
      tracks: tracks,
      enabledByDefault: true,
      preferredLanguage: s.preferredSubtitleLanguage,
    );
    if (pick != null) engine.setSubtitleTrack(pick.id);
    ref
        .read(settingsProvider.notifier)
        .set(s.copyWith(subtitlesEnabledByDefault: true));
  }

  void _pickTrack(BuildContext context, WidgetRef ref, MediaTrack t) {
    if (isSubtitles) {
      // mpv refuses a track already held as the secondary: free it first.
      if (t.id == engine.secondarySubtitleTrackId) clearSecondarySubtitle(ref);
      engine.setSubtitleTrack(t.id);
      // An embedded track now: the encoding card no longer applies.
      ref.read(subtitleLoaderProvider).clear();
      final s = ref.read(settingsProvider);
      ref
          .read(settingsProvider.notifier)
          .set(
            s.copyWith(
              subtitlesEnabledByDefault: true,
              preferredSubtitleLanguage:
                  t.language ?? s.preferredSubtitleLanguage,
            ),
          );
    } else {
      engine.setAudioTrack(t.id);
      final s = ref.read(settingsProvider);
      ref
          .read(settingsProvider.notifier)
          .set(
            s.copyWith(
              preferredAudioLanguage: t.language ?? s.preferredAudioLanguage,
            ),
          );
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickManualSubtitle(BuildContext context, WidgetRef ref) async {
    // Both captured before the await, because the sheet is popped on every
    // outcome below and `context` is defunct from then on. The messenger has
    // to be the app-level one in any case: this sheet has no Scaffold, so a
    // SnackBar shown while it is still up lands on the player's Scaffold —
    // the route underneath, behind the bottom 60% of the screen the sheet
    // occupies. Keeping the sheet open is what hid the failure, not what
    // preserved it.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
    );
    final path = result?.files.single.path;
    if (path == null) return; // cancelled — leave the sheet as it was
    final ok = await ref.read(manualSubtitleProvider).load(path);
    _closeAndReport(messenger, navigator, ok: ok);
  }

  /// Closes the sheet and reports the outcome. Synchronous on purpose: the
  /// navigator's context is the one the "Detalles" sheet opens from, and
  /// touching it outside the async gap keeps it honest.
  void _closeAndReport(
    ScaffoldMessengerState messenger,
    NavigatorState navigator, {
    required bool ok,
  }) {
    navigator.pop();
    // A KV-502 from an earlier attempt must not still be sitting there after
    // this one worked.
    messenger.hideCurrentSnackBar();
    if (!ok) {
      showFailureSnackBarOn(messenger, navigator.context, KivoOp.subtitleLoad);
    }
  }

  void _pickExternal(BuildContext context, WidgetRef ref, ExternalSubtitle e) {
    final key = session?.resumeKey;
    if (key != null) {
      ref
          .read(subtitleLoaderProvider)
          .load(e.uri, title: e.displayName, resumeKey: key);
    } else {
      engine.setExternalSubtitle(e.uri, title: e.displayName);
    }
    final lang = languageFromFilename(e.displayName);
    final s = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .set(
          s.copyWith(
            subtitlesEnabledByDefault: true,
            preferredSubtitleLanguage: lang ?? s.preferredSubtitleLanguage,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final subsOn = s.subtitlesEnabledByDefault;
    final accent = Color(s.accentColor);
    final l10n = context.l10n;
    final activeExternal =
        isSubtitles ? ref.watch(activeExternalSubtitleProvider) : null;
    final audioSource =
        isSubtitles ? null : ref.watch(currentAudioSourceProvider);
    if (isSubtitles) ref.watch(secondarySubtitleRevisionProvider);
    final secondaryId = isSubtitles ? engine.secondarySubtitleTrackId : null;
    final secondaryChoices = isSubtitles
        ? secondaryCandidates(tracks, current,
            primaryMpvId: ref.watch(currentSubtitleMpvIdProvider))
        : const <MediaTrack>[];

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF182036),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.playerTracksShowSubtitles,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: subsOn,
                      activeThumbColor: accent,
                      onChanged: (v) => v ? _turnOn(ref) : _turnOff(ref),
                    ),
                  ],
                ),
              ),
            ],
            if (tracks.isNotEmpty) ...[
              if (isSubtitles) _SectionEyebrow(label: l10n.playerTracksSectionInVideo),
              for (final t in tracks)
                _TrackCard(
                  icon: isSubtitles
                      ? Icons.closed_caption_outlined
                      : Icons.graphic_eq_rounded,
                  label: t.title ?? t.language ?? t.id,
                  sublabel: t.isDefault
                      ? l10n.playerTracksEmbeddedDefault
                      : l10n.playerTracksEmbedded,
                  active: current?.id == t.id,
                  accent: accent,
                  onTap: () => _pickTrack(context, ref, t),
                ),
            ],
            _SectionEyebrow(label: l10n.playerTracksSectionSync),
            // Each picker opens the capsule on its own side; the capsule's
            // Sub|Audio switch moves between them from there. The subtitle row
            // is listed even with no subtitle showing — sub-delay would change
            // nothing then, so it is disabled rather than hidden.
            _TrackCard(
              icon: Icons.compare_arrows_rounded,
              label: isSubtitles
                  ? l10n.playerTracksSyncSubtitles
                  : l10n.playerTracksSyncAudio,
              sublabel: isSubtitles && current == null
                  ? l10n.playerTracksSyncNeedsSubtitle
                  : l10n.playerTracksSyncHint,
              active: false,
              enabled: !isSubtitles || current != null,
              accent: accent,
              onTap: () {
                Navigator.of(context).pop();
                ref.read(syncHudProvider.notifier).show(
                    isSubtitles ? SyncTarget.subtitles : SyncTarget.audio);
              },
            ),
            if (!isSubtitles) ...[
              _SectionEyebrow(label: l10n.playerTracksSectionEnhance),
              // Toggles in place (the sheet stays open) and says, for the track
              // playing right now, whether and how it acts — Modo noche can
              // only work on Dolby, and "on" must never look like it works
              // when it can't.
              _TrackCard(
                icon: Icons.nightlight_round,
                label: l10n.playerTracksNightMode,
                // Only Dolby tracks can be compressed, so on anything else the
                // card is disabled and says why, instead of letting the user
                // switch on something that cannot act. The setting itself is
                // untouched: it applies again as soon as a Dolby track plays.
                sublabel: audioSource == null
                    ? l10n.playerTracksReadingTrack
                    : !audioSource.isDolby
                        ? l10n.playerTracksNightModeNoEffect
                        : s.nightMode
                            ? l10n.playerTracksNightModeDolby
                            : l10n.playerTracksNightModeOffHint,
                active: s.nightMode && (audioSource?.isDolby ?? false),
                enabled: audioSource?.isDolby ?? false,
                accent: accent,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .set(s.copyWith(nightMode: !s.nightMode)),
              ),
              _TrackCard(
                icon: Icons.record_voice_over_outlined,
                label: l10n.playerTracksVoiceBoost,
                sublabel: !s.voiceBoost
                    ? l10n.playerTracksVoiceBoostOffHint
                    : audioSource == null
                        ? l10n.playerTracksEnhancePending
                        : audioSource.isMultichannel
                        ? l10n.playerTracksVoiceBoostSurround
                        : l10n.playerTracksVoiceBoostStereo,
                active: s.voiceBoost,
                accent: accent,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .set(s.copyWith(voiceBoost: !s.voiceBoost)),
              ),
            ],
            // Only for a text file Kivo loaded itself: embedded tracks are
            // UTF-8 by spec, and a binary VobSub has no encoding at all.
            if (activeExternal != null &&
                !activeExternal.binary &&
                current != null &&
                // A late load for the previous video must not put its card
                // (and its reload) on this one.
                activeExternal.resumeKey == session?.resumeKey)
              _TrackCard(
                icon: Icons.translate_rounded,
                label: l10n.playerTracksEncodingLabel,
                sublabel: encodingSummary(l10n, activeExternal),
                active: false,
                accent: accent,
                onTap: () => showSubtitleEncodingSheet(context),
              ),
            // Only alongside a primary: a lone line at the top with nothing at
            // the bottom is not a "second" subtitle.
            if (isSubtitles && current != null && secondaryChoices.isNotEmpty) ...[
              _SectionEyebrow(label: l10n.playerTracksSectionSecondary),
              _TrackCard(
                icon: Icons.subtitles_off_outlined,
                label: l10n.playerTracksSecondaryOff,
                sublabel: l10n.playerTracksSecondaryOffHint,
                active: secondaryId == null,
                accent: accent,
                onTap: () => pickSecondarySubtitle(ref, null),
              ),
              for (final t in secondaryChoices)
                _TrackCard(
                  icon: Icons.vertical_align_top_rounded,
                  label: t.title ?? t.language ?? t.id,
                  sublabel: l10n.playerTracksSecondaryHint,
                  active: secondaryId == t.id,
                  accent: accent,
                  onTap: () => pickSecondarySubtitle(ref, t),
                ),
            ],
            if (isSubtitles && external.isNotEmpty) ...[
              _SectionEyebrow(label: l10n.playerTracksSectionInFolder),
              for (final e in external)
                _TrackCard(
                  icon: Icons.folder_outlined,
                  label: e.displayName,
                  sublabel: l10n.playerTracksLocalFile,
                  // mpv lists an added file under its own numeric track id,
                  // never the uri, so the loader is what knows which one is on.
                  active: current != null &&
                      activeExternal?.sourceUri == e.uri,
                  accent: accent,
                  onTap: () => _pickExternal(context, ref, e),
                ),
            ],
            if (tracks.isEmpty && (!isSubtitles || external.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  // Never "no hay subtítulos disponibles": the "Cargar
                  // subtítulo…" card sits right below this line.
                  isSubtitles
                      ? l10n.playerTracksNoSubtitlesFound
                      : l10n.playerTracksNoOtherAudioTracks,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
            if (isSubtitles) ...[
              _SectionEyebrow(label: l10n.playerTracksSectionFromDevice),
              _TrackCard(
                icon: Icons.upload_file_outlined,
                label: l10n.playerTracksLoadSubtitleAction,
                sublabel: l10n.playerTracksLoadSubtitleHint,
                active: false,
                accent: accent,
                onTap: () => _pickManualSubtitle(context, ref),
              ),
            ],
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
  final Color accent;
  final VoidCallback onTap;

  /// A disabled card still lists the option — it just cannot be used yet, and
  /// its sublabel is expected to say why.
  final bool enabled;

  const _TrackCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.active,
    required this.accent,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.16)
                  : const Color(0xFF182036),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: active
                        ? accent.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: active ? accent : Colors.white70,
                  ),
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
                          color: active ? accent : Colors.white,
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        sublabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (active) Icon(Icons.check_rounded, size: 18, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Estilo preview, pinned above the scrolling options: whatever is being
/// adjusted, the sample stays in sight and changes as the finger moves. It is
/// the overlay's own widget, at the preview's scale — what shows here is what
/// shows over the video.
class _StylePreview extends ConsumerWidget {
  const _StylePreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Container(
      key: const Key('style-preview'),
      height: 96,
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF26324A), Color(0xFF070A12)],
        ),
      ),
      child: SubtitleText(
        text: context.l10n.playerTracksStylePreviewSample,
        settings: s,
        scale: 0.62,
      ),
    );
  }
}

class _StyleSection extends ConsumerWidget {
  const _StyleSection();

  static const _textSwatches = [
    0xFFFFFFFF,
    0xFF000000,
    0xFFFFEB3B,
    0xFF2D6CFF,
    0xFFE8B84B,
  ];
  static const _outlineSwatches = [
    0xFF000000,
    0xFFFFFFFF,
    0xFF3A3A3A,
    0xFF1B2A4A,
  ];
  List<({int value, String label})> _bgSwatches(AppLocalizations l10n) => [
        (value: 0x00000000, label: l10n.playerTracksBgTransparent),
        (value: 0xFF000000, label: l10n.playerTracksBgBlack),
        (value: 0xFFFFFFFF, label: l10n.playerTracksBgWhite),
      ];

  void _set(WidgetRef ref, KivoSettings Function(KivoSettings) f) {
    // Kivo's own overlay (and the pinned preview) draw from the settings:
    // nothing to push to mpv.
    ref.read(settingsProvider.notifier).set(f(ref.read(settingsProvider)));
  }

  void _reset(WidgetRef ref) {
    final d = KivoSettings.defaults();
    _set(
        ref,
        (s) => s.copyWith(
              subtitleFontSize: d.subtitleFontSize,
              subtitleTextColor: d.subtitleTextColor,
              subtitleBackgroundColor: d.subtitleBackgroundColor,
              subtitleOutlineWidth: d.subtitleOutlineWidth,
              subtitleOutlineColor: d.subtitleOutlineColor,
              subtitleShadow: d.subtitleShadow,
              subtitleBold: d.subtitleBold,
              subtitleFontFamily: d.subtitleFontFamily,
              subtitleBottomMargin: d.subtitleBottomMargin,
              secondarySubtitleTopMargin: d.secondarySubtitleTopMargin,
              subtitleRespectAss: d.subtitleRespectAss,
            ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final accent = Color(s.accentColor);
    final l10n = context.l10n;
    final fontSize = s.subtitleFontSize.clamp(16, 48).toDouble();
    final fonts = [
      ('default', l10n.playerTracksFontDefault),
      ('serif', l10n.playerTracksFontSerif),
      ('mono', l10n.playerTracksFontMono),
      ('condensed', l10n.playerTracksFontCondensed),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StyleGroup(title: l10n.playerTracksGroupText, children: [
          _RowLabel(l10n.playerTracksSizeLabel),
          Row(
            children: [
              // The size-adjust glyph (small/large), not a language.
              _StepButton(
                label: 'A',
                small: true,
                onTap: () => _set(
                    ref,
                    (x) => x.copyWith(
                        subtitleFontSize: (fontSize - 2).clamp(16, 48))),
              ),
              Expanded(
                child: _StyleSlider(
                  value: fontSize,
                  min: 16,
                  max: 48,
                  divisions: 32,
                  accent: accent,
                  valueLabel: fontSize.round().toString(),
                  valueWidth: 30,
                  onChanged: (v) =>
                      _set(ref, (x) => x.copyWith(subtitleFontSize: v)),
                ),
              ),
              _StepButton(
                label: 'A',
                small: false,
                onTap: () => _set(
                    ref,
                    (x) => x.copyWith(
                        subtitleFontSize: (fontSize + 2).clamp(16, 48))),
              ),
            ],
          ),
          _RowLabel(l10n.playerTracksFontLabel),
          Row(
            children: [
              for (final (id, label) in fonts)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FontChip(
                      label: label,
                      family: subtitleFontFamily(id),
                      active: s.subtitleFontFamily == id,
                      accent: accent,
                      onTap: () =>
                          _set(ref, (x) => x.copyWith(subtitleFontFamily: id)),
                    ),
                  ),
                ),
            ],
          ),
          _RowLabel(l10n.playerTracksTextColorLabel),
          Row(
            children: [
              for (final c in _textSwatches)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ColorSquare(
                    color: c,
                    active: s.subtitleTextColor == c,
                    accent: accent,
                    onTap: () =>
                        _set(ref, (x) => x.copyWith(subtitleTextColor: c)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _StyleSwitch(
            label: l10n.playerTracksBoldLabel,
            value: s.subtitleBold,
            accent: accent,
            onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleBold: v)),
          ),
        ]),
        _StyleGroup(title: l10n.playerTracksGroupOutline, children: [
          _RowLabel(l10n.playerTracksOutlineWidthLabel),
          _StyleSlider(
            value: s.subtitleOutlineWidth,
            min: 0,
            max: 5,
            divisions: 10,
            accent: accent,
            valueLabel: s.subtitleOutlineWidth == 0
                ? l10n.playerTracksOutlineNone
                : s.subtitleOutlineWidth.toStringAsFixed(1),
            onChanged: (v) =>
                _set(ref, (x) => x.copyWith(subtitleOutlineWidth: v)),
          ),
          if (s.subtitleOutlineWidth > 0) ...[
            _RowLabel(l10n.playerTracksOutlineColorLabel),
            Row(
              children: [
                for (final c in _outlineSwatches)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _ColorSquare(
                      color: c,
                      active: s.subtitleOutlineColor == c,
                      accent: accent,
                      onTap: () => _set(
                          ref, (x) => x.copyWith(subtitleOutlineColor: c)),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          _StyleSwitch(
            label: l10n.playerTracksShadowLabel,
            value: s.subtitleShadow,
            accent: accent,
            onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleShadow: v)),
          ),
        ]),
        _StyleGroup(title: l10n.playerTracksGroupBackground, children: [
          Row(
            children: [
              for (final bg in _bgSwatches(l10n))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _BackgroundChip(
                      background: bg.value,
                      label: bg.label,
                      textColor: s.subtitleTextColor,
                      active: s.subtitleBackgroundColor == bg.value,
                      accent: accent,
                      onTap: () => _set(ref,
                          (x) => x.copyWith(subtitleBackgroundColor: bg.value)),
                    ),
                  ),
                ),
            ],
          ),
        ]),
        _StyleGroup(title: l10n.playerTracksGroupPosition, children: [
          _RowLabel(l10n.playerTracksPositionPrimaryLabel),
          _StyleSlider(
            value: s.subtitleBottomMargin,
            min: 0,
            max: 40,
            divisions: 40,
            accent: accent,
            valueLabel:
                l10n.playerTracksPositionValue(s.subtitleBottomMargin.round()),
            onChanged: (v) =>
                _set(ref, (x) => x.copyWith(subtitleBottomMargin: v)),
          ),
          _RowLabel(l10n.playerTracksSectionSecondary),
          _StyleSlider(
            value: s.secondarySubtitleTopMargin,
            min: 0,
            max: 40,
            divisions: 40,
            accent: accent,
            valueLabel: l10n
                .playerTracksPositionValue(s.secondarySubtitleTopMargin.round()),
            onChanged: (v) =>
                _set(ref, (x) => x.copyWith(secondarySubtitleTopMargin: v)),
          ),
          _Hint(l10n.playerTracksPositionDragHint),
        ]),
        _StyleGroup(title: l10n.playerTracksGroupAss, children: [
          _StyleSwitch(
            label: l10n.playerTracksRespectAss,
            hint: l10n.playerTracksRespectAssHint,
            value: s.subtitleRespectAss,
            accent: accent,
            onChanged: (v) =>
                _set(ref, (x) => x.copyWith(subtitleRespectAss: v)),
          ),
          _Hint(l10n.playerTracksPictureSubsNote),
        ]),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: accent),
            onPressed: () => _reset(ref),
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: Text(l10n.playerTracksResetStyleAction),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final bool small;
  final VoidCallback onTap;
  const _StepButton({
    required this.label,
    required this.small,
    required this.onTap,
  });

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
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: small ? 12 : 17,
          ),
        ),
      ),
    );
  }
}

class _ColorSquare extends StatelessWidget {
  final int color;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  const _ColorSquare({
    required this.color,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.6),
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: active
            ? Icon(Icons.check_rounded, size: 15, color: onAccent(Color(color)))
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
  final Color accent;
  final VoidCallback onTap;

  const _BackgroundChip({
    required this.background,
    required this.label,
    required this.textColor,
    required this.active,
    required this.accent,
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
          border: Border.all(
            color: active ? accent : Colors.transparent,
            width: 2,
          ),
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
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Color(background),
                  borderRadius: BorderRadius.circular(3),
                ),
                // 'Ab' is a generic font-sample glyph pair for the background
                // swatch preview, not language — not translated.
                child: Text(
                  'Ab',
                  style: TextStyle(
                    color: Color(textColor),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
