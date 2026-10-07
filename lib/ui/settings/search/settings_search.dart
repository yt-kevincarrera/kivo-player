import '../../../core/settings/kivo_settings.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../player/decoder/decoder_mode.dart';

/// The screens a search result can open. Vault is here because its root row
/// is searchable too, but it never carries anchors: it is its own world.
enum SettingsPage { general, gestures, interface, advanced, equalizer, backup, about, vault }

/// Anchor ids shared by [settingsSearchEntries] and the `SettingAnchor`s in
/// each section. A constant on both sides so a typo is a compile error; an id
/// that has an entry but no anchor (or the reverse) is caught by
/// `settings_search_anchors_test`.
abstract final class SettingIds {
  // General
  static const theme = 'general.theme';
  static const accentColor = 'general.accentColor';
  static const iconStyle = 'general.iconStyle';
  static const language = 'general.language';
  static const haptics = 'general.haptics';
  static const hiddenFolders = 'general.hiddenFolders';
  // Reproducción y gestos
  static const gestureMap = 'gestures.map';
  static const skipBack = 'gestures.skipBack';
  static const skipForward = 'gestures.skipForward';
  static const doubleTapPause = 'gestures.doubleTapPause';
  static const centerSkip = 'gestures.centerSkip';
  static const horizontalSeek = 'gestures.horizontalSeek';
  static const pinchZoom = 'gestures.pinchZoom';
  static const zoomMax = 'gestures.zoomMax';
  static const zoomReset = 'gestures.zoomReset';
  static const brightnessSensitivity = 'gestures.brightness';
  static const volumeSensitivity = 'gestures.volume';
  static const seekSensitivity = 'gestures.seek';
  static const volumeBoostMax = 'gestures.volumeBoostMax';
  static const rememberSpeed = 'gestures.rememberSpeed';
  static const holdLeftSpeed = 'gestures.holdLeftSpeed';
  static const holdRightMax = 'gestures.holdRightMax';
  static const holdRightRelease = 'gestures.holdRightRelease';
  static const speedFineStep = 'gestures.speedFineStep';
  static const speedPresets = 'gestures.speedPresets';
  static const holdRightDetents = 'gestures.holdRightDetents';
  // Interfaz
  static const autoHide = 'interface.autoHide';
  static const rememberOrientation = 'interface.rememberOrientation';
  static const defaultAspect = 'interface.defaultAspect';
  static const showOverlay = 'interface.showOverlay';
  static const overlayContent = 'interface.overlayContent';
  static const overlayCorner = 'interface.overlayCorner';
  static const libraryColumns = 'interface.columns';
  // Reproducción avanzada
  static const resumeBehavior = 'advanced.resumeBehavior';
  static const resumeMinSeconds = 'advanced.resumeMinSeconds';
  static const incognito = 'advanced.incognito';
  static const incognitoTaps = 'advanced.incognitoTaps';
  static const classicSurface = 'advanced.classicSurface';
  static const autoplayNext = 'advanced.autoplayNext';
  static const pipAutoOnHome = 'advanced.pipAutoOnHome';
  static const minimizeKeepsPlaying = 'advanced.minimizeKeepsPlaying';
  static const decoderMode = 'advanced.decoderMode';
  static const decoderAutoFallback = 'advanced.decoderAutoFallback';
  static const decoderStallSeconds = 'advanced.decoderStallSeconds';
  static const decoderForget = 'advanced.decoderForget';
  static const nightMode = 'advanced.nightMode';
  static const nightModeLevel = 'advanced.nightModeLevel';
  static const voiceBoost = 'advanced.voiceBoost';
  static const voiceBoostLevel = 'advanced.voiceBoostLevel';
  static const subtitlesDefault = 'advanced.subtitlesDefault';
  static const preferredSubtitleLang = 'advanced.preferredSubtitleLang';
  static const preferredAudioLang = 'advanced.preferredAudioLang';
  static const allFilesAccess = 'advanced.allFilesAccess';
  // Ecualizador
  static const eqPresets = 'equalizer.presets';
  static const eqBands = 'equalizer.bands';
  static const eqPreamp = 'equalizer.preamp';
  // Copia de seguridad
  static const backupExport = 'backup.export';
  static const backupRestore = 'backup.restore';
  // Acerca de
  static const checkUpdates = 'about.checkUpdates';
  static const autoCheckUpdates = 'about.autoCheck';
  static const reportProblem = 'about.reportProblem';
  static const errorLog = 'about.errorLog';
  static const privacy = 'about.privacy';
  static const licenses = 'about.licenses';
}

typedef L10nText = String Function(AppLocalizations l10n);

/// One searchable thing: a whole page (`id == null`, opens it) or a single
/// setting inside one (opens the page and highlights the anchor).
class SettingsSearchEntry {
  final String? id;
  final SettingsPage page;
  final L10nText title;
  final L10nText? subtitle;

  /// The uppercase group label the setting sits under, for the result path.
  final L10nText? group;

  /// Comma-separated synonyms, matched but never shown.
  final L10nText? keywords;

  /// False drops the entry from results altogether (the hidden Vault).
  final bool Function(KivoSettings s)? available;

  /// False when the section currently hides this control behind another one;
  /// tapping the result then highlights [fallback] — the switch that reveals it.
  final bool Function(KivoSettings s)? shownWhen;
  final String? fallback;

  const SettingsSearchEntry.page(this.page, {required this.title, this.subtitle, this.keywords, this.available})
      : id = null,
        group = null,
        shownWhen = null,
        fallback = null;

  const SettingsSearchEntry(this.id, this.page,
      {required this.title, this.subtitle, this.group, this.keywords, this.shownWhen, this.fallback, this.available});
}

String pageTitle(AppLocalizations l10n, SettingsPage page) => switch (page) {
      SettingsPage.general => l10n.settingsGeneralTitle,
      SettingsPage.gestures => l10n.settingsPlaybackGesturesTitle,
      SettingsPage.interface => l10n.settingsInterfaceTitle,
      SettingsPage.advanced => l10n.settingsAdvancedPlaybackTitle,
      SettingsPage.equalizer => l10n.settingsEqualizerTitle,
      SettingsPage.backup => l10n.settingsBackupTitle,
      SettingsPage.about => l10n.settingsAboutTitle,
      // 'Vault' is a proper noun (product name), never translated.
      SettingsPage.vault => 'Vault',
    };

bool _decoderAuto(KivoSettings s) => s.decoderMode == DecoderMode.auto.id;

final List<SettingsSearchEntry> settingsSearchEntries = [
  // ── Pages ──
  SettingsSearchEntry.page(SettingsPage.general,
      title: (l) => l.settingsGeneralTitle, subtitle: (l) => l.settingsGeneralNavSubtitle),
  SettingsSearchEntry.page(SettingsPage.gestures,
      title: (l) => l.settingsPlaybackGesturesTitle, subtitle: (l) => l.settingsPlaybackGesturesNavSubtitle),
  SettingsSearchEntry.page(SettingsPage.interface,
      title: (l) => l.settingsInterfaceTitle, subtitle: (l) => l.settingsInterfaceNavSubtitle),
  SettingsSearchEntry.page(SettingsPage.advanced,
      title: (l) => l.settingsAdvancedPlaybackTitle, subtitle: (l) => l.settingsAdvancedPlaybackNavSubtitle),
  SettingsSearchEntry.page(SettingsPage.equalizer,
      title: (l) => l.settingsEqualizerTitle,
      subtitle: (l) => l.settingsEqualizerNavSubtitle,
      keywords: (l) => l.settingsSearchKwEqualizer),
  SettingsSearchEntry.page(SettingsPage.backup,
      title: (l) => l.settingsBackupTitle,
      subtitle: (l) => l.settingsBackupNavSubtitle,
      keywords: (l) => l.settingsSearchKwBackup),
  SettingsSearchEntry.page(SettingsPage.about,
      title: (l) => l.settingsAboutTitle, subtitle: (l) => l.settingsAboutNavSubtitle),
  // A hidden entrance must stay hidden: search can't become the way in.
  SettingsSearchEntry.page(SettingsPage.vault,
      title: (l) => 'Vault',
      subtitle: (l) => l.settingsVaultNavSubtitle,
      keywords: (l) => l.settingsSearchKwVault,
      available: (s) => !s.vaultEntranceHidden),

  // ── General ──
  SettingsSearchEntry(SettingIds.theme, SettingsPage.general,
      title: (l) => l.settingsGeneralTheme,
      subtitle: (l) => l.settingsGeneralThemeSubtitle,
      group: (l) => l.settingsGeneralGroupAppearance,
      keywords: (l) => l.settingsSearchKwTheme),
  SettingsSearchEntry(SettingIds.accentColor, SettingsPage.general,
      title: (l) => l.settingsGeneralAccentColor,
      group: (l) => l.settingsGeneralGroupAppearance,
      keywords: (l) => l.settingsSearchKwAccent),
  SettingsSearchEntry(SettingIds.iconStyle, SettingsPage.general,
      title: (l) => l.settingsGeneralIcons,
      subtitle: (l) => l.settingsGeneralIconsSubtitle,
      group: (l) => l.settingsGeneralGroupAppearance),
  SettingsSearchEntry(SettingIds.language, SettingsPage.general,
      title: (l) => l.settingsLanguage,
      group: (l) => l.settingsGeneralGroupAppearance,
      keywords: (l) => l.settingsSearchKwLanguage),
  SettingsSearchEntry(SettingIds.haptics, SettingsPage.general,
      title: (l) => l.settingsGeneralHaptics,
      subtitle: (l) => l.settingsGeneralHapticsSubtitle,
      group: (l) => l.settingsGeneralGroupInteraction),
  SettingsSearchEntry(SettingIds.hiddenFolders, SettingsPage.general,
      title: (l) => l.settingsHiddenFoldersTitle,
      subtitle: (l) => l.settingsHiddenFoldersNavSubtitle,
      group: (l) => l.settingsGroupLibrary),

  // ── Reproducción y gestos ──
  SettingsSearchEntry(SettingIds.gestureMap, SettingsPage.gestures,
      title: (l) => l.settingsGesturesViewMap,
      subtitle: (l) => l.settingsGesturesViewMapSubtitle,
      group: (l) => l.settingsGesturesGroupLearn),
  SettingsSearchEntry(SettingIds.skipBack, SettingsPage.gestures,
      title: (l) => l.settingsGesturesSkipBack, group: (l) => l.settingsGesturesGroupDoubleTap),
  SettingsSearchEntry(SettingIds.skipForward, SettingsPage.gestures,
      title: (l) => l.settingsGesturesSkipForward, group: (l) => l.settingsGesturesGroupDoubleTap),
  SettingsSearchEntry(SettingIds.doubleTapPause, SettingsPage.gestures,
      title: (l) => l.settingsGesturesDoubleTapPause, group: (l) => l.settingsGesturesGroupDoubleTap),
  SettingsSearchEntry(SettingIds.centerSkip, SettingsPage.gestures,
      title: (l) => l.settingsGesturesCenterSkip, group: (l) => l.settingsGesturesGroupSeek),
  SettingsSearchEntry(SettingIds.horizontalSeek, SettingsPage.gestures,
      title: (l) => l.settingsGesturesHorizontalSeek, group: (l) => l.settingsGesturesGroupSeek),
  SettingsSearchEntry(SettingIds.pinchZoom, SettingsPage.gestures,
      title: (l) => l.settingsGesturesPinchZoom,
      subtitle: (l) => l.settingsGesturesPinchZoomSubtitle,
      group: (l) => l.settingsGesturesGroupZoom),
  SettingsSearchEntry(SettingIds.zoomMax, SettingsPage.gestures,
      title: (l) => l.settingsGesturesZoomMax, group: (l) => l.settingsGesturesGroupZoom),
  SettingsSearchEntry(SettingIds.zoomReset, SettingsPage.gestures,
      title: (l) => l.settingsGesturesZoomReset,
      subtitle: (l) => l.settingsGesturesZoomResetSubtitle,
      group: (l) => l.settingsGesturesGroupZoom),
  SettingsSearchEntry(SettingIds.brightnessSensitivity, SettingsPage.gestures,
      title: (l) => l.settingsGesturesBrightness, group: (l) => l.settingsGesturesGroupSensitivity),
  SettingsSearchEntry(SettingIds.volumeSensitivity, SettingsPage.gestures,
      title: (l) => l.settingsGesturesVolume, group: (l) => l.settingsGesturesGroupSensitivity),
  SettingsSearchEntry(SettingIds.seekSensitivity, SettingsPage.gestures,
      title: (l) => l.settingsGesturesSeek, group: (l) => l.settingsGesturesGroupSensitivity),
  SettingsSearchEntry(SettingIds.volumeBoostMax, SettingsPage.gestures,
      title: (l) => l.settingsGesturesVolumeBoostMax,
      group: (l) => l.settingsGesturesGroupSensitivity,
      keywords: (l) => l.settingsSearchKwVolumeBoost),
  SettingsSearchEntry(SettingIds.rememberSpeed, SettingsPage.gestures,
      title: (l) => l.settingsGesturesRememberSpeed, group: (l) => l.settingsGesturesGroupSpeed),
  SettingsSearchEntry(SettingIds.holdLeftSpeed, SettingsPage.gestures,
      title: (l) => l.settingsGesturesHoldLeftSpeed, group: (l) => l.settingsGesturesGroupSpeed),
  SettingsSearchEntry(SettingIds.holdRightMax, SettingsPage.gestures,
      title: (l) => l.settingsGesturesHoldRightMax, group: (l) => l.settingsGesturesGroupSpeed),
  SettingsSearchEntry(SettingIds.holdRightRelease, SettingsPage.gestures,
      title: (l) => l.settingsGesturesHoldRightRelease, group: (l) => l.settingsGesturesGroupSpeed),
  SettingsSearchEntry(SettingIds.speedFineStep, SettingsPage.gestures,
      title: (l) => l.settingsGesturesSpeedFineStep, group: (l) => l.settingsGesturesGroupSpeed),
  SettingsSearchEntry(SettingIds.speedPresets, SettingsPage.gestures,
      title: (l) => l.settingsGesturesSpeedPresets,
      subtitle: (l) => l.settingsGesturesSpeedPresetsSubtitle,
      group: (l) => l.settingsGesturesGroupSpeed,
      keywords: (l) => l.settingsSearchKwSpeedPresets),
  SettingsSearchEntry(SettingIds.holdRightDetents, SettingsPage.gestures,
      title: (l) => l.settingsGesturesHoldRightDetents,
      subtitle: (l) => l.settingsGesturesHoldRightDetentsSubtitle,
      group: (l) => l.settingsGesturesGroupSpeed),

  // ── Interfaz ──
  SettingsSearchEntry(SettingIds.autoHide, SettingsPage.interface,
      title: (l) => l.settingsInterfaceAutoHide, group: (l) => l.settingsInterfaceGroupControls),
  SettingsSearchEntry(SettingIds.rememberOrientation, SettingsPage.interface,
      title: (l) => l.settingsInterfaceRememberOrientation, group: (l) => l.settingsInterfaceGroupControls),
  SettingsSearchEntry(SettingIds.defaultAspect, SettingsPage.interface,
      title: (l) => l.settingsInterfaceDefaultAspect, group: (l) => l.settingsInterfaceGroupVideo),
  SettingsSearchEntry(SettingIds.showOverlay, SettingsPage.interface,
      title: (l) => l.settingsInterfaceShowOverlay, group: (l) => l.settingsInterfaceGroupOverlay),
  SettingsSearchEntry(SettingIds.overlayContent, SettingsPage.interface,
      title: (l) => l.settingsInterfaceOverlayContent,
      group: (l) => l.settingsInterfaceGroupOverlay,
      shownWhen: (s) => s.showInfoOverlay,
      fallback: SettingIds.showOverlay),
  SettingsSearchEntry(SettingIds.overlayCorner, SettingsPage.interface,
      title: (l) => l.settingsInterfaceOverlayCorner,
      group: (l) => l.settingsInterfaceGroupOverlay,
      shownWhen: (s) => s.showInfoOverlay,
      fallback: SettingIds.showOverlay),
  SettingsSearchEntry(SettingIds.libraryColumns, SettingsPage.interface,
      title: (l) => l.settingsInterfaceColumns,
      group: (l) => l.settingsGroupLibrary,
      keywords: (l) => l.settingsSearchKwColumns),

  // ── Reproducción avanzada ──
  SettingsSearchEntry(SettingIds.resumeBehavior, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedResumeBehavior, group: (l) => l.settingsAdvancedGroupContinueWatching),
  SettingsSearchEntry(SettingIds.resumeMinSeconds, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedResumeMinSeconds, group: (l) => l.settingsAdvancedGroupContinueWatching),
  SettingsSearchEntry(SettingIds.incognito, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedIncognito,
      subtitle: (l) => l.settingsAdvancedIncognitoSubtitle,
      group: (l) => l.settingsAdvancedGroupContinueWatching,
      keywords: (l) => l.settingsSearchKwIncognito),
  SettingsSearchEntry(SettingIds.incognitoTaps, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedIncognitoTaps,
      subtitle: (l) => l.settingsAdvancedIncognitoTapsSubtitle,
      group: (l) => l.settingsAdvancedGroupContinueWatching),
  SettingsSearchEntry(SettingIds.classicSurface, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedClassicSurface,
      subtitle: (l) => l.settingsAdvancedClassicSurfaceSubtitle,
      group: (l) => l.settingsAdvancedGroupContinueWatching),
  SettingsSearchEntry(SettingIds.autoplayNext, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedAutoplayNext, group: (l) => l.settingsAdvancedGroupPlayback),
  SettingsSearchEntry(SettingIds.pipAutoOnHome, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedPipAutoOnHome,
      group: (l) => l.settingsAdvancedGroupPlayback,
      keywords: (l) => l.settingsSearchKwPip),
  SettingsSearchEntry(SettingIds.minimizeKeepsPlaying, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedMinimizeKeepsPlaying,
      subtitle: (l) => l.settingsAdvancedMinimizeKeepsPlayingSubtitle,
      group: (l) => l.settingsAdvancedGroupPlayback,
      keywords: (l) => l.settingsSearchKwBackground),
  SettingsSearchEntry(SettingIds.decoderMode, SettingsPage.advanced,
      title: (l) => l.settingsDecoderMode,
      subtitle: (l) => l.settingsDecoderModeSubtitle,
      group: (l) => l.settingsAdvancedGroupDecoder,
      keywords: (l) => l.settingsSearchKwDecoder),
  SettingsSearchEntry(SettingIds.decoderAutoFallback, SettingsPage.advanced,
      title: (l) => l.settingsDecoderAutoFallback,
      subtitle: (l) => l.settingsDecoderAutoFallbackSubtitle,
      group: (l) => l.settingsAdvancedGroupDecoder,
      shownWhen: _decoderAuto,
      fallback: SettingIds.decoderMode),
  // Chains: hidden behind the fallback switch, which may itself be hidden
  // behind the mode — [resolveAnchor] walks it.
  SettingsSearchEntry(SettingIds.decoderStallSeconds, SettingsPage.advanced,
      title: (l) => l.settingsDecoderStallSeconds,
      group: (l) => l.settingsAdvancedGroupDecoder,
      shownWhen: (s) => _decoderAuto(s) && s.decoderAutoFallback,
      fallback: SettingIds.decoderAutoFallback),
  SettingsSearchEntry(SettingIds.decoderForget, SettingsPage.advanced,
      title: (l) => l.settingsDecoderForget,
      subtitle: (l) => l.settingsDecoderForgetSubtitle,
      group: (l) => l.settingsAdvancedGroupDecoder),
  SettingsSearchEntry(SettingIds.nightMode, SettingsPage.advanced,
      title: (l) => l.settingsNightMode,
      subtitle: (l) => l.settingsNightModeSubtitle,
      group: (l) => l.settingsAdvancedGroupAudio),
  SettingsSearchEntry(SettingIds.nightModeLevel, SettingsPage.advanced,
      title: (l) => l.settingsNightModeLevel,
      group: (l) => l.settingsAdvancedGroupAudio,
      shownWhen: (s) => s.nightMode,
      fallback: SettingIds.nightMode),
  SettingsSearchEntry(SettingIds.voiceBoost, SettingsPage.advanced,
      title: (l) => l.settingsVoiceBoost,
      subtitle: (l) => l.settingsVoiceBoostSubtitle,
      group: (l) => l.settingsAdvancedGroupAudio),
  SettingsSearchEntry(SettingIds.voiceBoostLevel, SettingsPage.advanced,
      title: (l) => l.settingsVoiceBoostLevel,
      group: (l) => l.settingsAdvancedGroupAudio,
      shownWhen: (s) => s.voiceBoost,
      fallback: SettingIds.voiceBoost),
  SettingsSearchEntry(SettingIds.subtitlesDefault, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedSubtitlesDefault, group: (l) => l.settingsAdvancedGroupSubtitlesAudio),
  SettingsSearchEntry(SettingIds.preferredSubtitleLang, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedPreferredSubtitleLang,
      subtitle: (l) => l.settingsAdvancedPreferredLangSubtitle,
      group: (l) => l.settingsAdvancedGroupSubtitlesAudio),
  SettingsSearchEntry(SettingIds.preferredAudioLang, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedPreferredAudioLang,
      subtitle: (l) => l.settingsAdvancedPreferredLangSubtitle,
      group: (l) => l.settingsAdvancedGroupSubtitlesAudio),
  SettingsSearchEntry(SettingIds.allFilesAccess, SettingsPage.advanced,
      title: (l) => l.settingsAdvancedAllFilesAccess,
      subtitle: (l) => l.settingsAdvancedAllFilesAccessPrompt,
      group: (l) => l.settingsAdvancedGroupStorage),

  // ── Ecualizador ──
  SettingsSearchEntry(SettingIds.eqPresets, SettingsPage.equalizer,
      title: (l) => l.settingsEqGroupPresets),
  SettingsSearchEntry(SettingIds.eqBands, SettingsPage.equalizer,
      title: (l) => l.settingsEqGroupBands),
  SettingsSearchEntry(SettingIds.eqPreamp, SettingsPage.equalizer,
      title: (l) => l.settingsEqPreampGain, group: (l) => l.settingsEqGroupPreamp),

  // ── Copia de seguridad ──
  SettingsSearchEntry(SettingIds.backupExport, SettingsPage.backup,
      title: (l) => l.settingsBackupExport, subtitle: (l) => l.settingsBackupExportSubtitle),
  SettingsSearchEntry(SettingIds.backupRestore, SettingsPage.backup,
      title: (l) => l.settingsBackupRestoreTitle, subtitle: (l) => l.settingsBackupRestoreSubtitle),

  // ── Acerca de ──
  SettingsSearchEntry(SettingIds.checkUpdates, SettingsPage.about,
      title: (l) => l.settingsAboutCheckForUpdates, keywords: (l) => l.settingsSearchKwUpdates),
  SettingsSearchEntry(SettingIds.autoCheckUpdates, SettingsPage.about,
      title: (l) => l.settingsAboutAutoCheck, subtitle: (l) => l.settingsAboutAutoCheckSubtitle),
  SettingsSearchEntry(SettingIds.reportProblem, SettingsPage.about,
      title: (l) => l.settingsAboutReportProblem, subtitle: (l) => l.settingsAboutReportProblemSubtitle),
  SettingsSearchEntry(SettingIds.errorLog, SettingsPage.about,
      title: (l) => l.settingsAboutErrorLogTitle, subtitle: (l) => l.settingsAboutErrorLogSubtitle),
  SettingsSearchEntry(SettingIds.privacy, SettingsPage.about,
      title: (l) => l.settingsAboutPrivacy, subtitle: (l) => l.settingsAboutPrivacySubtitle),
  SettingsSearchEntry(SettingIds.licenses, SettingsPage.about,
      title: (l) => l.settingsAboutLicenses, subtitle: (l) => l.settingsAboutLicensesSubtitle),
];

/// One ranked result, with its text already resolved for the current locale.
class SettingsSearchHit {
  final SettingsSearchEntry entry;
  final String title;

  /// «Page › Group» for a setting; the page's own subtitle for a page.
  final String path;

  /// [start, end) ranges of [title] that matched a query word, for bolding.
  final List<(int, int)> titleMatches;

  const SettingsSearchHit(this.entry, this.title, this.path, this.titleMatches);
}

const _folds = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Lower-cases and strips accents ONE CODE UNIT AT A TIME, so the result is
/// always exactly as long as [s] — match offsets in the folded text are valid
/// offsets in the original, which is what lets the UI bold the real title.
String foldForSearch(String s) {
  final out = StringBuffer();
  for (final unit in s.codeUnits) {
    final ch = String.fromCharCode(unit);
    final lower = ch.toLowerCase();
    // A few characters lower-case to two (İ → i̇); keep those as-is rather
    // than break the length invariant.
    final l = lower.length == 1 ? lower : ch;
    out.write(_folds[l] ?? l);
  }
  return out.toString();
}

List<String> _words(String query) =>
    foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Every available entry whose title, subtitle, path or synonyms contain ALL
/// the words of [query] (accent- and case-insensitive), best first: every
/// word in the title beats only some of them there (the rest matched through
/// subtitle, path or synonyms), and within each, a title that starts with the
/// first word beats one that merely contains it.
/// Ties keep index order, which already reads page → group → row.
List<SettingsSearchHit> searchSettings(String query, AppLocalizations l10n, KivoSettings s,
    {List<SettingsSearchEntry>? entries}) {
  final words = _words(query);
  if (words.isEmpty) return const [];
  final ranked = <(int rank, int index, SettingsSearchHit hit)>[];
  final all = entries ?? settingsSearchEntries;
  for (var i = 0; i < all.length; i++) {
    final e = all[i];
    if (e.available != null && !e.available!(s)) continue;
    final title = e.title(l10n);
    final path = e.id == null
        ? (e.subtitle?.call(l10n) ?? '')
        : [pageTitle(l10n, e.page), if (e.group != null) e.group!(l10n)].join(' › ');
    final ft = foldForSearch(title);
    final haystack = foldForSearch(
        [title, e.subtitle?.call(l10n) ?? '', path, e.keywords?.call(l10n) ?? ''].join('\n'));
    if (!words.every(haystack.contains)) continue;

    final matches = <(int, int)>[];
    for (final w in words) {
      final at = ft.indexOf(w);
      if (at >= 0) matches.add((at, at + w.length));
    }
    final rank = (words.every(ft.contains) ? 0 : 2) + (ft.startsWith(words.first) ? 0 : 1);
    ranked.add((rank, i, SettingsSearchHit(e, title, path, _merge(matches))));
  }
  ranked.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final r in ranked) r.$3];
}

List<(int, int)> _merge(List<(int, int)> ranges) {
  if (ranges.isEmpty) return ranges;
  final sorted = [...ranges]..sort((a, b) => a.$1 - b.$1);
  final out = [sorted.first];
  for (final r in sorted.skip(1)) {
    final last = out.last;
    if (r.$1 <= last.$2) {
      out[out.length - 1] = (last.$1, r.$2 > last.$2 ? r.$2 : last.$2);
    } else {
      out.add(r);
    }
  }
  return out;
}

/// The anchor to highlight for [entry] given the current settings: its own,
/// or — while the section hides it — the control that reveals it, walking the
/// chain (stall seconds → auto fallback → decoder mode). Null for pages.
String? resolveAnchor(SettingsSearchEntry entry, KivoSettings s, {List<SettingsSearchEntry>? entries}) {
  final all = entries ?? settingsSearchEntries;
  var e = entry;
  while (e.shownWhen != null && !e.shownWhen!(s) && e.fallback != null) {
    e = all.firstWhere((x) => x.id == e.fallback);
  }
  return e.id;
}
