import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/all_files_access_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAdvancedPlaybackTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
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
