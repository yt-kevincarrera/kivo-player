import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
import '../settings/sections/advanced_playback_section.dart';
import '../settings/sections/equalizer_section.dart';
import '../settings/sections/about_section.dart';
import '../settings/sections/backup_section.dart';
import '../settings/sections/end_actions_settings_screen.dart';
import '../settings/sections/general_section.dart';
import '../settings/sections/hidden_folders_section.dart';
import '../settings/widgets/setting_choice.dart';
import '../player/tracks/track_picker.dart';
import '../../platform/storage_browser_provider.dart';
import '../../player/library/media_index.dart';
import '../settings/sections/interface_section.dart';
import '../vault/vault_entry_actions.dart';
import 'tv_focusable.dart';
import 'tv_panel.dart';
import '../player/state/aspect_state.dart';

Future<T?> showTvChoices<T>(
  BuildContext context,
  String title,
  List<(T, String, String?)> choices, {
  T? selected,
}) {
  return showTvPanelChoices<T>(context, title, choices, selected: selected);
}

Future<void> showTvRemoteGuide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => Dialog(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 760,
        maxHeight: MediaQuery.sizeOf(ctx).height * .85,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ctx.l10n.tvRemoteGuide,
              style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  ctx.l10n.tvRemoteGuideBody,
                  style: const TextStyle(fontSize: 21, height: 1.65),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TvButton(
              label: ctx.l10n.commonGoBack,
              autofocus: true,
              primary: true,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    ),
  ),
);

class TvSettingsScreen extends ConsumerStatefulWidget {
  const TvSettingsScreen({super.key});
  @override
  ConsumerState<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends ConsumerState<TvSettingsScreen> {
  int _category = 0;
  Future<void> _page(Widget child) async {
    final invoker = FocusManager.instance.primaryFocus;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => child));
    if (mounted && invoker?.context != null) invoker!.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final categories = [
      (Icons.play_circle_outline, l.tvPlayback),
      (Icons.volume_up_outlined, l.playerAudioTooltip),
      (Icons.subtitles_outlined, l.playerSubtitlesTooltip),
      (Icons.settings_remote_outlined, l.tvAccessibility),
      (Icons.video_library_outlined, l.tvLibraryComplete),
      (Icons.tune, l.tvAdvanced),
    ];
    Widget toggle(
      String title,
      bool value,
      VoidCallback change, {
      String? subtitle,
    }) => TvOptionRow(
      label: title,
      subtitle: subtitle,
      onPressed: change,
      toggled: value,
    );
    final rows = switch (_category) {
      0 => <Widget>[
        TvOptionRow(
          key: const Key('tv-seek-setting'),
          label: l.tvRemoteStep,
          value: '${s.tvRemoteSeekSeconds} s',
          onPressed: () async {
            final value = await showTvChoices<int>(
              context,
              l.tvRemoteStep,
              [1, 3, 5, 10, 15, 30, 60].map((i) => (i, '$i s', null)).toList(),
              selected: s.tvRemoteSeekSeconds,
            );
            if (value != null && mounted) {
              n.set(
                ref.read(settingsProvider).copyWith(tvRemoteSeekSeconds: value),
              );
            }
          },
        ),
        toggle(
          l.tvProgressiveSeek,
          s.tvRemoteProgressiveSeek,
          () => n.set(
            s.copyWith(tvRemoteProgressiveSeek: !s.tvRemoteProgressiveSeek),
          ),
          subtitle: l.tvProgressiveSeekHint,
        ),
        TvOptionRow(
          label: l.tvImage,
          value: aspectLabelFor(l, aspectFromSetting(s.defaultAspectMode)),
          onPressed: () async {
            final value = await showTvChoices<String>(context, l.tvImage, [
              ('fit', l.playerAspectFit, l.tvFitHint),
              ('fill', l.playerAspectFill, l.tvFillHint),
              ('stretch', l.playerAspectStretch, l.tvStretchHint),
            ], selected: s.defaultAspectMode);
            if (value != null && mounted) {
              n.set(
                ref.read(settingsProvider).copyWith(defaultAspectMode: value),
              );
            }
          },
        ),
        toggle(
          l.tvRememberPosition,
          s.resumeBehavior != 'off',
          () => n.set(
            s.copyWith(
              resumeBehavior: s.resumeBehavior == 'off' ? 'auto' : 'off',
            ),
          ),
        ),
        toggle(
          l.settingsAdvancedAutoplayNext,
          s.autoplayNext,
          () => n.set(s.copyWith(autoplayNext: !s.autoplayNext)),
        ),
        TvOptionRow(
          label: l.tvMorePlayback,
          icon: Icons.tune,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
        TvOptionRow(
          label: l.endActionsTitle,
          onPressed: () => _page(const EndActionsSettingsScreen()),
        ),
      ],
      1 => <Widget>[
        SettingChoice<String?>(
          title: l.settingsAdvancedPreferredAudioLang,
          value: s.preferredAudioLanguage,
          options: [
            (null, l.settingsAdvancedAutomaticOption),
            if (s.preferredAudioLanguage != null)
              (
                s.preferredAudioLanguage,
                l.settingsAdvancedLangChosen(s.preferredAudioLanguage!),
              ),
          ],
          onChanged: (value) => n.set(
            ref.read(settingsProvider).copyWith(preferredAudioLanguage: value),
          ),
        ),
        toggle(
          l.settingsVoiceBoost,
          s.voiceBoost,
          () => n.set(s.copyWith(voiceBoost: !s.voiceBoost)),
        ),
        toggle(
          l.settingsNightMode,
          s.nightMode,
          () => n.set(s.copyWith(nightMode: !s.nightMode)),
        ),
        TvOptionRow(
          label: l.settingsEqualizerTitle,
          icon: Icons.equalizer,
          onPressed: () => _page(const EqualizerSection()),
        ),
        TvOptionRow(
          label: l.tvAudioSettings,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
      ],
      2 => <Widget>[
        TvOptionRow(
          label: l.playerTracksStyleTabLabel,
          icon: Icons.format_size,
          onPressed: () => showTvSubtitleStyle(context),
        ),
        SettingChoice<String?>(
          title: l.settingsAdvancedPreferredSubtitleLang,
          value: s.preferredSubtitleLanguage,
          options: [
            (null, l.settingsAdvancedAutomaticOption),
            if (s.preferredSubtitleLanguage != null)
              (
                s.preferredSubtitleLanguage,
                l.settingsAdvancedLangChosen(s.preferredSubtitleLanguage!),
              ),
          ],
          onChanged: (value) => n.set(
            ref
                .read(settingsProvider)
                .copyWith(preferredSubtitleLanguage: value),
          ),
        ),
        toggle(
          l.settingsAdvancedSubtitlesDefault,
          s.subtitlesEnabledByDefault,
          () => n.set(
            s.copyWith(subtitlesEnabledByDefault: !s.subtitlesEnabledByDefault),
          ),
        ),
        TvOptionRow(
          label: l.tvSubtitleSettings,
          icon: Icons.subtitles_outlined,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
      ],
      3 => <Widget>[
        TvOptionRow(
          label: l.tvRemoteGuide,
          subtitle: l.tvFocusHint,
          icon: Icons.settings_remote_outlined,
          onPressed: () => showTvRemoteGuide(context),
        ),
        TvOptionRow(
          label: l.tvRemoteStep,
          value: '${s.tvRemoteSeekSeconds} s',
          onPressed: () => setState(() => _category = 0),
        ),
        TvOptionRow(
          label: l.settingsInterfaceAutoHide,
          value: '${(s.controlsAutoHideMs / 1000).round()} s',
          onPressed: () async {
            final value = await showTvChoices<int>(
              context,
              l.settingsInterfaceAutoHide,
              [3, 5, 8, 10, 15].map((i) => (i, '$i s', null)).toList(),
            );
            if (value != null && mounted) {
              n.set(
                ref
                    .read(settingsProvider)
                    .copyWith(controlsAutoHideMs: value * 1000),
              );
            }
          },
        ),
      ],
      4 => <Widget>[
        TvOptionRow(
          label: l.tvRefresh,
          icon: Icons.refresh,
          onPressed: () async {
            final browser = ref.read(storageBrowserProvider);
            final index = ref.read(mediaIndexProvider.notifier);
            final volumes = await browser.volumes();
            for (final volume in volumes.where((v) => v.removable)) {
              await browser
                  .rescan(volume.path)
                  .timeout(const Duration(seconds: 30));
            }
            await index.refresh();
          },
        ),
        TvOptionRow(
          label: l.settingsHiddenFoldersTitle,
          icon: Icons.folder_off_outlined,
          onPressed: () => _page(const HiddenFoldersSection()),
        ),
      ],
      _ => <Widget>[
        TvOptionRow(
          label: l.settingsGeneralTitle,
          onPressed: () => _page(const GeneralSettingsSection()),
        ),
        TvOptionRow(
          label: l.settingsInterfaceTitle,
          onPressed: () => _page(const InterfaceSettingsSection()),
        ),
        TvOptionRow(
          label: l.settingsAdvancedPlaybackTitle,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
        TvOptionRow(
          label: l.settingsBackupTitle,
          onPressed: () => _page(const BackupSection()),
        ),
        if (!s.vaultEntranceHidden)
          TvOptionRow(
            label: 'Vault',
            icon: Icons.lock_outline,
            onPressed: () => openVault(context),
          ),
        TvOptionRow(
          label: l.settingsAboutTitle,
          onPressed: () => _page(const AboutSection()),
        ),
      ],
    };
    final menu = ListView(
      padding: const EdgeInsets.all(5),
      children: categories.indexed
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TvButton(
                label: e.$2.$2,
                icon: e.$2.$1,
                autofocus: e.$1 == 0,
                selected: _category == e.$1,
                onPressed: () => setState(() => _category = e.$1),
              ),
            ),
          )
          .toList(),
    );
    final content = ListView(
      key: ValueKey(_category),
      padding: const EdgeInsets.all(6),
      children: [
        Text(
          categories[_category].$2,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        ...rows.map(
          (w) => Padding(padding: const EdgeInsets.only(bottom: 6), child: w),
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 25, 40, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 28,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TvButton(
                    label: l.commonGoBack,
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    l.tvSettings,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaledMenu = math.min(
                      330.0,
                      240 * MediaQuery.textScalerOf(context).scale(1),
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: scaledMenu, child: menu),
                        const VerticalDivider(width: 42),
                        Expanded(child: content),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(l.tvNavigationHint, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
