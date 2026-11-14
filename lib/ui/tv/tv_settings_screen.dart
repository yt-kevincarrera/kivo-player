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
import '../settings/sections/interface_section.dart';
import '../vault/vault_entry_actions.dart';
import 'tv_focusable.dart';
import '../player/state/aspect_state.dart';

Future<T?> showTvChoices<T>(
  BuildContext context,
  String title,
  List<(T, String, String?)> choices, {
  T? selected,
}) {
  final hasSelection = choices.any((choice) => choice.$1 == selected);
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .82,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: choices.indexed
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TvButton(
                              label: e.$2.$2,
                              subtitle: e.$2.$3,
                              autofocus: !hasSelection
                                  ? e.$1 == 0
                                  : e.$2.$1 == selected,
                              selected: e.$2.$1 == selected,
                              trailing: e.$2.$1 == selected
                                  ? const Icon(Icons.check)
                                  : null,
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(e.$2.$1),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TvButton(
                label: context.l10n.commonGoBack,
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
  void _page(Widget child) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => child));

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
      (Icons.tune, l.tvAdvanced),
    ];
    Widget toggle(
      String title,
      bool value,
      VoidCallback change, {
      String? subtitle,
    }) => TvButton(
      label: title,
      subtitle: subtitle,
      onPressed: change,
      toggled: value,
      trailing: ExcludeFocus(
        child: Switch(
          value: value,
          onChanged: null,
          thumbColor: WidgetStatePropertyAll(
            value ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ),
    );
    final rows = switch (_category) {
      0 => <Widget>[
        TvButton(
          key: const Key('tv-seek-setting'),
          label: l.tvRemoteStep,
          value: '${s.tvRemoteSeekSeconds} s',
          trailing: Text(
            '${s.tvRemoteSeekSeconds} s',
            style: const TextStyle(fontSize: 21),
          ),
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
        TvButton(
          label: l.tvImage,
          value: aspectLabelFor(l, aspectFromSetting(s.defaultAspectMode)),
          trailing: Text(
            aspectLabelFor(l, aspectFromSetting(s.defaultAspectMode)),
            style: const TextStyle(fontSize: 20),
          ),
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
        TvButton(
          label: l.tvMorePlayback,
          icon: Icons.tune,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
        TvButton(
          label: l.endActionsTitle,
          onPressed: () => _page(const EndActionsSettingsScreen()),
        ),
      ],
      1 => <Widget>[
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
        TvButton(
          label: l.settingsEqualizerTitle,
          icon: Icons.equalizer,
          onPressed: () => _page(const EqualizerSection()),
        ),
        TvButton(
          label: l.tvAudioSettings,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
      ],
      2 => <Widget>[
        toggle(
          l.settingsAdvancedSubtitlesDefault,
          s.subtitlesEnabledByDefault,
          () => n.set(
            s.copyWith(subtitlesEnabledByDefault: !s.subtitlesEnabledByDefault),
          ),
        ),
        TvButton(
          label: l.tvSubtitleSettings,
          icon: Icons.subtitles_outlined,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
      ],
      3 => <Widget>[
        TvButton(
          label: l.tvRemoteGuide,
          subtitle: l.tvFocusHint,
          icon: Icons.settings_remote_outlined,
          onPressed: () => showTvRemoteGuide(context),
        ),
        TvButton(
          label: l.tvRemoteStep,
          trailing: Text('${s.tvRemoteSeekSeconds} s'),
          onPressed: () => setState(() => _category = 0),
        ),
        TvButton(
          label: l.settingsInterfaceAutoHide,
          trailing: Text('${(s.controlsAutoHideMs / 1000).round()} s'),
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
      _ => <Widget>[
        TvButton(
          label: l.settingsGeneralTitle,
          onPressed: () => _page(const GeneralSettingsSection()),
        ),
        TvButton(
          label: l.settingsInterfaceTitle,
          onPressed: () => _page(const InterfaceSettingsSection()),
        ),
        TvButton(
          label: l.settingsAdvancedPlaybackTitle,
          onPressed: () => _page(const AdvancedPlaybackSection()),
        ),
        TvButton(
          label: l.settingsBackupTitle,
          onPressed: () => _page(const BackupSection()),
        ),
        if (!s.vaultEntranceHidden)
          TvButton(
            label: 'Vault',
            icon: Icons.lock_outline,
            onPressed: () => openVault(context),
          ),
        TvButton(
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
          (w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: w),
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
