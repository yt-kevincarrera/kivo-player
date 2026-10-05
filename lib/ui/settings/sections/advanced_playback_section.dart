import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/all_files_access_provider.dart';
import '../../../player/audio/audio_pipeline.dart';
import '../../../player/decoder/decoder_controller.dart';
import '../../../player/decoder/decoder_mode.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';
import '../../widgets/readable_width.dart';

class AdvancedPlaybackSection extends ConsumerWidget {
  const AdvancedPlaybackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;

    List<(String?, String)> langOptions(String? current) => [
          (null, l10n.settingsAdvancedAutomaticOption),
          if (current != null) (current, l10n.settingsAdvancedLangChosen(current)),
        ];

    final levelOptions = [
      (EnhancementLevel.soft.id, l10n.settingsLevelSoft),
      (EnhancementLevel.medium.id, l10n.settingsLevelMedium),
      (EnhancementLevel.strong.id, l10n.settingsLevelStrong),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAdvancedPlaybackTitle)),
      body: ListView(
        padding: readablePadding(context, const EdgeInsets.fromLTRB(14, 12, 14, 28)),
        children: [
          _label(context, l10n.settingsAdvancedGroupContinueWatching),
          SettingsCard(children: [
            SettingChoice<String>(
              title: l10n.settingsAdvancedResumeBehavior, value: s.resumeBehavior,
              options: [
                ('auto', l10n.settingsAdvancedAutomaticOption),
                ('ask', l10n.settingsAdvancedResumeAsk),
                ('off', l10n.settingsAdvancedResumeOff),
              ],
              onChanged: (v) => n.set(s.copyWith(resumeBehavior: v))),
            SettingStepper(
              title: l10n.settingsAdvancedResumeMinSeconds, value: s.resumeMinSeconds,
              min: 0, max: 120, step: 5, label: (v) => '$v s',
              onChanged: (v) => n.set(s.copyWith(resumeMinSeconds: v))),
            SettingSwitch(
              title: l10n.settingsAdvancedIncognito,
              subtitle: l10n.settingsAdvancedIncognitoSubtitle,
              value: s.incognito,
              onChanged: (v) => n.set(s.copyWith(incognito: v))),
            SettingSegmented<int>(
              title: l10n.settingsAdvancedIncognitoTaps,
              subtitle: l10n.settingsAdvancedIncognitoTapsSubtitle,
              options: [
                (0, l10n.settingsAdvancedIncognitoTapsOff),
                for (final c in const [2, 3, 4, 5, 6]) (c, '$c'),
              ],
              value: s.incognitoTapCount,
              onChanged: (v) => n.set(s.copyWith(incognitoTapCount: v))),
            SettingSwitch(
              title: l10n.settingsAdvancedClassicSurface,
              subtitle: l10n.settingsAdvancedClassicSurfaceSubtitle,
              value: s.classicVideoSurface,
              onChanged: (v) => n.set(s.copyWith(classicVideoSurface: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsAdvancedGroupPlayback),
          SettingsCard(children: [
            SettingSwitch(
              title: l10n.settingsAdvancedAutoplayNext, value: s.autoplayNext,
              onChanged: (v) => n.set(s.copyWith(autoplayNext: v))),
            SettingSwitch(
              title: l10n.settingsAdvancedPipAutoOnHome, value: s.pipAutoOnHome,
              onChanged: (v) => n.set(s.copyWith(pipAutoOnHome: v))),
            SettingSwitch(
              title: l10n.settingsAdvancedMinimizeKeepsPlaying,
              subtitle: l10n.settingsAdvancedMinimizeKeepsPlayingSubtitle,
              value: s.minimizeKeepsPlaying,
              onChanged: (v) => n.set(s.copyWith(minimizeKeepsPlaying: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsAdvancedGroupDecoder),
          SettingsCard(children: [
            SettingChoice<String>(
              title: l10n.settingsDecoderMode,
              subtitle: l10n.settingsDecoderModeSubtitle,
              value: s.decoderMode,
              options: [
                (DecoderMode.auto.id, l10n.settingsDecoderAuto),
                (DecoderMode.hardware.id, l10n.settingsDecoderHardware),
                (DecoderMode.software.id, l10n.settingsDecoderSoftware),
              ],
              onChanged: (v) => n.set(s.copyWith(decoderMode: v))),
            // Both only mean something in Automático: Hardware and Software
            // never switch on their own.
            if (s.decoderMode == DecoderMode.auto.id) ...[
              SettingSwitch(
                title: l10n.settingsDecoderAutoFallback,
                subtitle: l10n.settingsDecoderAutoFallbackSubtitle,
                value: s.decoderAutoFallback,
                onChanged: (v) => n.set(s.copyWith(decoderAutoFallback: v))),
              if (s.decoderAutoFallback)
                SettingStepper(
                  title: l10n.settingsDecoderStallSeconds,
                  value: s.decoderStallSeconds,
                  min: 1, max: 10, step: 1, label: (v) => '$v s',
                  onChanged: (v) => n.set(s.copyWith(decoderStallSeconds: v))),
            ],
            SettingNavRow(
              icon: Icons.restart_alt_rounded,
              title: l10n.settingsDecoderForget,
              subtitle: l10n.settingsDecoderForgetSubtitle,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final count =
                    await ref.read(decoderControllerProvider).forgetAll();
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                      content: Text(l10n.settingsDecoderForgotSnackbar(count))));
              },
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsAdvancedGroupAudio),
          SettingsCard(children: [
            SettingSwitch(
              title: l10n.settingsNightMode,
              subtitle: l10n.settingsNightModeSubtitle,
              value: s.nightMode,
              onChanged: (v) => n.set(s.copyWith(nightMode: v))),
            if (s.nightMode)
              SettingChoice<String>(
                title: l10n.settingsNightModeLevel,
                value: s.nightModeLevel,
                options: levelOptions,
                onChanged: (v) => n.set(s.copyWith(nightModeLevel: v))),
            SettingSwitch(
              title: l10n.settingsVoiceBoost,
              subtitle: l10n.settingsVoiceBoostSubtitle,
              value: s.voiceBoost,
              onChanged: (v) => n.set(s.copyWith(voiceBoost: v))),
            if (s.voiceBoost)
              SettingChoice<String>(
                title: l10n.settingsVoiceBoostLevel,
                value: s.voiceBoostLevel,
                options: levelOptions,
                onChanged: (v) => n.set(s.copyWith(voiceBoostLevel: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsAdvancedGroupSubtitlesAudio),
          SettingsCard(children: [
            SettingSwitch(
              title: l10n.settingsAdvancedSubtitlesDefault, value: s.subtitlesEnabledByDefault,
              onChanged: (v) => n.set(s.copyWith(subtitlesEnabledByDefault: v))),
            SettingChoice<String?>(
              title: l10n.settingsAdvancedPreferredSubtitleLang,
              subtitle: l10n.settingsAdvancedPreferredLangSubtitle,
              value: s.preferredSubtitleLanguage, options: langOptions(s.preferredSubtitleLanguage),
              onChanged: (v) => n.set(s.copyWith(preferredSubtitleLanguage: v))),
            SettingChoice<String?>(
              title: l10n.settingsAdvancedPreferredAudioLang,
              subtitle: l10n.settingsAdvancedPreferredLangSubtitle,
              value: s.preferredAudioLanguage, options: langOptions(s.preferredAudioLanguage),
              onChanged: (v) => n.set(s.copyWith(preferredAudioLanguage: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsAdvancedGroupStorage),
          SettingsCard(children: [
            Builder(builder: (context) {
              final granted = ref.watch(allFilesAccessGrantedProvider).valueOrNull ?? false;
              return SettingNavRow(
                icon: Icons.folder_open_outlined,
                title: l10n.settingsAdvancedAllFilesAccess,
                subtitle: granted
                    ? l10n.settingsAdvancedAllFilesAccessGranted
                    : l10n.settingsAdvancedAllFilesAccessPrompt,
                onTap: () async {
                  await ref.read(allFilesAccessProvider).request();
                  ref.invalidate(allFilesAccessGrantedProvider);
                },
              );
            }),
          ]),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.secondary)),
      );
}
