import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
import '../vault/vault_entry_actions.dart';
import 'search/settings_search.dart';
import 'search/settings_search_state.dart';
import 'sections/about_section.dart';
import 'sections/advanced_playback_section.dart';
import 'sections/backup_section.dart';
import 'sections/equalizer_section.dart';
import 'sections/general_section.dart';
import 'sections/interface_section.dart';
import 'sections/playback_gestures_section.dart';
import 'widgets/setting_tiles.dart';
import '../widgets/readable_width.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _pageFor(SettingsPage page) => switch (page) {
        SettingsPage.general => const GeneralSettingsSection(),
        SettingsPage.gestures => const PlaybackGesturesSection(),
        SettingsPage.interface => const InterfaceSettingsSection(),
        SettingsPage.advanced => const AdvancedPlaybackSection(),
        SettingsPage.equalizer => const EqualizerSection(),
        SettingsPage.backup => const BackupSection(),
        SettingsPage.about => const AboutSection(),
        // Opened through openVault, never pushed as a page; see _openHit.
        SettingsPage.vault => const SizedBox.shrink(),
      };

  void _push(SettingsPage page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _pageFor(page)));

  Future<void> _openHit(SettingsSearchHit hit) async {
    FocusScope.of(context).unfocus();
    if (hit.entry.page == SettingsPage.vault) {
      openVault(context);
      return;
    }
    final highlight = ref.read(settingsHighlightProvider.notifier);
    highlight.state = resolveAnchor(hit.entry, ref.read(settingsProvider));
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _pageFor(hit.entry.page)));
    // The anchor clears it on reveal; this covers one that never mounted, so
    // a stale id can't flash a row the next time that section is opened.
    highlight.state = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final searching = ref.watch(settingsSearchActiveProvider);
    final query = ref.watch(settingsSearchQueryProvider);
    // Closed from anywhere (the ✕, or HomeShell's back handler): drop the text.
    ref.listen(settingsSearchActiveProvider, (_, active) {
      if (!active) _searchController.clear();
    });

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          // Left-anchored like the library's: centred, the narrow title and
          // the full-width field would slide sideways as they crossfade.
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previousChildren, if (currentChild != null) currentChild],
          ),
          child: searching
              ? TextField(
                  key: const ValueKey('settings-search-field'),
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(hintText: l10n.settingsSearchHint, border: InputBorder.none),
                  onChanged: (q) => ref.read(settingsSearchQueryProvider.notifier).state = q,
                )
              : Text(l10n.settingsRootTitle, key: const ValueKey('settings-title')),
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: searching
                ? IconButton(
                    key: const ValueKey('settings-search-close'),
                    tooltip: l10n.settingsSearchClose,
                    icon: const Icon(Icons.close),
                    onPressed: () => closeSettingsSearch(ref),
                  )
                : IconButton(
                    key: const ValueKey('settings-search-open'),
                    tooltip: l10n.settingsSearchTooltip,
                    icon: const Icon(Icons.search),
                    onPressed: () => ref.read(settingsSearchActiveProvider.notifier).state = true,
                  ),
          ),
        ],
      ),
      // An empty query hasn't failed to match anything yet: keep the normal
      // list under the field instead of a blank page.
      body: searching && query.trim().isNotEmpty ? _results(context, query) : _root(context),
    );
  }

  Widget _results(BuildContext context, String query) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final hits = searchSettings(query, l10n, ref.watch(settingsProvider));
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.settingsSearchEmpty(query.trim()),
              key: const Key('settings-search-empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: readablePadding(context, const EdgeInsets.fromLTRB(14, 10, 14, 28)),
      children: [
        SettingsCard(children: [
          for (final hit in hits)
            _SearchResultRow(
              key: ValueKey('settings-hit-${hit.entry.id ?? hit.entry.page.name}'),
              hit: hit,
              onTap: () => _openHit(hit),
            ),
        ]),
      ],
    );
  }

  Widget _root(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: readablePadding(context, const EdgeInsets.fromLTRB(14, 10, 14, 28)),
      children: [
        SettingsCard(children: [
          SettingNavRow(
            icon: Icons.tune, title: l10n.settingsGeneralTitle, subtitle: l10n.settingsGeneralNavSubtitle,
            onTap: () => _push(SettingsPage.general)),
          SettingNavRow(
            icon: Icons.videogame_asset_outlined,
            title: l10n.settingsPlaybackGesturesTitle,
            subtitle: l10n.settingsPlaybackGesturesNavSubtitle,
            onTap: () => _push(SettingsPage.gestures)),
          SettingNavRow(
            icon: Icons.dashboard_customize_outlined,
            title: l10n.settingsInterfaceTitle,
            subtitle: l10n.settingsInterfaceNavSubtitle,
            onTap: () => _push(SettingsPage.interface)),
          SettingNavRow(
            icon: Icons.play_circle_outline,
            title: l10n.settingsAdvancedPlaybackTitle,
            subtitle: l10n.settingsAdvancedPlaybackNavSubtitle,
            onTap: () => _push(SettingsPage.advanced)),
          SettingNavRow(
            icon: Icons.equalizer_rounded,
            title: l10n.settingsEqualizerTitle,
            subtitle: l10n.settingsEqualizerNavSubtitle,
            onTap: () => _push(SettingsPage.equalizer)),
          SettingNavRow(
            icon: Icons.save_outlined,
            title: l10n.settingsBackupTitle,
            subtitle: l10n.settingsBackupNavSubtitle,
            onTap: () => _push(SettingsPage.backup)),
          SettingNavRow(
            icon: Icons.info_outline, title: l10n.settingsAboutTitle, subtitle: l10n.settingsAboutNavSubtitle,
            onTap: () => _push(SettingsPage.about)),
          if (!ref.watch(settingsProvider).vaultEntranceHidden)
            SettingNavRow(
              // 'Vault' is a proper noun (product name), never translated.
              icon: Icons.lock_outline, title: 'Vault', subtitle: l10n.settingsVaultNavSubtitle,
              onTap: () => openVault(context)),
        ]),
        const SizedBox(height: 18),
        _ResetTile(
          onReset: () => ref.read(settingsProvider.notifier).set(KivoSettings.defaults()),
        ),
      ],
    );
  }
}

/// One search result: the title with the typed words lit in the accent
/// colour, and where it lives underneath.
class _SearchResultRow extends StatelessWidget {
  final SettingsSearchHit hit;
  final VoidCallback onTap;
  const _SearchResultRow({super.key, required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: cs.onSurface);
    final lit = base.copyWith(fontWeight: FontWeight.w800, color: cs.secondary);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in hit.titleMatches) {
      if (start > at) spans.add(TextSpan(text: hit.title.substring(at, start)));
      spans.add(TextSpan(text: hit.title.substring(start, end), style: lit));
      at = end;
    }
    if (at < hit.title.length) spans.add(TextSpan(text: hit.title.substring(at)));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(TextSpan(style: base, children: spans)),
                  if (hit.path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(hit.path, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ResetTile extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetTile({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          // Pop with the dialog's own context: showDialog pushes on the root
          // Navigator, but this tile sits in HomeShell's nested tab one.
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.settingsResetAllTitle),
            content: Text(l10n.settingsResetAllBody),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(l10n.settingsResetAction)),
            ],
          ),
        );
        if (ok == true) onReset();
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(l10n.settingsResetAllTitle,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.error)),
      ),
    );
  }
}
