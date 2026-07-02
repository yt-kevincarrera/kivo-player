class KivoSettings {
  final int doubleTapSkipLeft;
  final int doubleTapSkipRight;
  final bool doubleTapCenterPause;
  final double brightnessSensitivity;
  final double volumeSensitivity;
  final double seekSensitivity;
  final bool horizontalSeek;
  final bool hapticsOnGestures;
  final int volumeBoostMax;
  final double holdLeftSpeed;
  final double holdRightMin;
  final double holdRightMax;
  final List<double> holdRightDetents;
  final bool holdRightReleaseToNormal;
  final double speedFineStep;
  final List<double> speedPresets;
  final bool rememberSpeed;
  final int centerSkipSeconds;
  final int controlsAutoHideMs;
  final bool showInfoOverlay;
  final String infoOverlayContent; // 'name_time' | 'name' | 'remaining' | 'clock'
  final String infoOverlayCorner;  // 'tl' | 'tr' | 'bl' | 'br'
  final String defaultAspectMode;  // 'fit' | 'fill' | 'stretch' | '16:9' | '4:3' | 'original'
  final String resumeBehavior;     // 'auto' | 'ask' | 'off'
  final int resumeMinSeconds;
  final bool rememberOrientationLock;
  final int accentColor;
  final int libraryColumns;
  final String themeMode; // 'auto' | 'light' | 'dark'
  final String librarySort; // LibrarySort enum name — see lib/player/library/library_filter.dart
  final bool subtitlesEnabledByDefault;
  final String? preferredSubtitleLanguage;
  final String? preferredAudioLanguage;
  final double subtitleFontSize;
  final int subtitleTextColor;
  final int subtitleBackgroundColor; // ARGB, default is transparent

  const KivoSettings({
    required this.doubleTapSkipLeft,
    required this.doubleTapSkipRight,
    required this.doubleTapCenterPause,
    required this.brightnessSensitivity,
    required this.volumeSensitivity,
    required this.seekSensitivity,
    required this.horizontalSeek,
    required this.hapticsOnGestures,
    required this.volumeBoostMax,
    required this.holdLeftSpeed,
    required this.holdRightMin,
    required this.holdRightMax,
    required this.holdRightDetents,
    required this.holdRightReleaseToNormal,
    required this.speedFineStep,
    required this.speedPresets,
    required this.rememberSpeed,
    required this.centerSkipSeconds,
    required this.controlsAutoHideMs,
    required this.showInfoOverlay,
    required this.infoOverlayContent,
    required this.infoOverlayCorner,
    required this.defaultAspectMode,
    required this.resumeBehavior,
    required this.resumeMinSeconds,
    required this.rememberOrientationLock,
    required this.accentColor,
    required this.libraryColumns,
    required this.themeMode,
    required this.librarySort,
    required this.subtitlesEnabledByDefault,
    required this.preferredSubtitleLanguage,
    required this.preferredAudioLanguage,
    required this.subtitleFontSize,
    required this.subtitleTextColor,
    required this.subtitleBackgroundColor,
  });

  factory KivoSettings.defaults() => const KivoSettings(
        doubleTapSkipLeft: 10,
        doubleTapSkipRight: 10,
        doubleTapCenterPause: true,
        brightnessSensitivity: 1.0,
        volumeSensitivity: 1.0,
        seekSensitivity: 1.0,
        horizontalSeek: true,
        hapticsOnGestures: true,
        volumeBoostMax: 150,
        holdLeftSpeed: 2.0,
        holdRightMin: 1.0,
        holdRightMax: 4.0,
        holdRightDetents: [1.0, 1.25, 1.5, 2.0, 3.0, 4.0],
        holdRightReleaseToNormal: true,
        speedFineStep: 0.01,
        speedPresets: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
        rememberSpeed: false,
        centerSkipSeconds: 10,
        controlsAutoHideMs: 3000,
        showInfoOverlay: true,
        infoOverlayContent: 'name_time',
        infoOverlayCorner: 'tl',
        defaultAspectMode: 'fit',
        resumeBehavior: 'auto',
        resumeMinSeconds: 5,
        rememberOrientationLock: true,
        accentColor: 0xFFE8B84B,
        libraryColumns: 1,
        themeMode: 'auto',
        librarySort: 'recent',
        subtitlesEnabledByDefault: true,
        preferredSubtitleLanguage: null,
        preferredAudioLanguage: null,
        subtitleFontSize: 26.0,
        subtitleTextColor: 0xFFFFFFFF,
        subtitleBackgroundColor: 0x00000000,
      );

  KivoSettings copyWith({
    int? doubleTapSkipLeft,
    int? doubleTapSkipRight,
    bool? doubleTapCenterPause,
    double? brightnessSensitivity,
    double? volumeSensitivity,
    double? seekSensitivity,
    bool? horizontalSeek,
    bool? hapticsOnGestures,
    int? volumeBoostMax,
    double? holdLeftSpeed,
    double? holdRightMin,
    double? holdRightMax,
    List<double>? holdRightDetents,
    bool? holdRightReleaseToNormal,
    double? speedFineStep,
    List<double>? speedPresets,
    bool? rememberSpeed,
    int? centerSkipSeconds,
    int? controlsAutoHideMs,
    bool? showInfoOverlay,
    String? infoOverlayContent,
    String? infoOverlayCorner,
    String? defaultAspectMode,
    String? resumeBehavior,
    int? resumeMinSeconds,
    bool? rememberOrientationLock,
    int? accentColor,
    int? libraryColumns,
    String? themeMode,
    String? librarySort,
    bool? subtitlesEnabledByDefault,
    String? preferredSubtitleLanguage,
    String? preferredAudioLanguage,
    double? subtitleFontSize,
    int? subtitleTextColor,
    int? subtitleBackgroundColor,
  }) {
    return KivoSettings(
      doubleTapSkipLeft: doubleTapSkipLeft ?? this.doubleTapSkipLeft,
      doubleTapSkipRight: doubleTapSkipRight ?? this.doubleTapSkipRight,
      doubleTapCenterPause: doubleTapCenterPause ?? this.doubleTapCenterPause,
      brightnessSensitivity: brightnessSensitivity ?? this.brightnessSensitivity,
      volumeSensitivity: volumeSensitivity ?? this.volumeSensitivity,
      seekSensitivity: seekSensitivity ?? this.seekSensitivity,
      horizontalSeek: horizontalSeek ?? this.horizontalSeek,
      hapticsOnGestures: hapticsOnGestures ?? this.hapticsOnGestures,
      volumeBoostMax: volumeBoostMax ?? this.volumeBoostMax,
      holdLeftSpeed: holdLeftSpeed ?? this.holdLeftSpeed,
      holdRightMin: holdRightMin ?? this.holdRightMin,
      holdRightMax: holdRightMax ?? this.holdRightMax,
      holdRightDetents: holdRightDetents ?? this.holdRightDetents,
      holdRightReleaseToNormal: holdRightReleaseToNormal ?? this.holdRightReleaseToNormal,
      speedFineStep: speedFineStep ?? this.speedFineStep,
      speedPresets: speedPresets ?? this.speedPresets,
      rememberSpeed: rememberSpeed ?? this.rememberSpeed,
      centerSkipSeconds: centerSkipSeconds ?? this.centerSkipSeconds,
      controlsAutoHideMs: controlsAutoHideMs ?? this.controlsAutoHideMs,
      showInfoOverlay: showInfoOverlay ?? this.showInfoOverlay,
      infoOverlayContent: infoOverlayContent ?? this.infoOverlayContent,
      infoOverlayCorner: infoOverlayCorner ?? this.infoOverlayCorner,
      defaultAspectMode: defaultAspectMode ?? this.defaultAspectMode,
      resumeBehavior: resumeBehavior ?? this.resumeBehavior,
      resumeMinSeconds: resumeMinSeconds ?? this.resumeMinSeconds,
      rememberOrientationLock: rememberOrientationLock ?? this.rememberOrientationLock,
      accentColor: accentColor ?? this.accentColor,
      libraryColumns: libraryColumns ?? this.libraryColumns,
      themeMode: themeMode ?? this.themeMode,
      librarySort: librarySort ?? this.librarySort,
      subtitlesEnabledByDefault: subtitlesEnabledByDefault ?? this.subtitlesEnabledByDefault,
      preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      preferredAudioLanguage: preferredAudioLanguage ?? this.preferredAudioLanguage,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleTextColor: subtitleTextColor ?? this.subtitleTextColor,
      subtitleBackgroundColor: subtitleBackgroundColor ?? this.subtitleBackgroundColor,
    );
  }

  Map<String, dynamic> toMap() => {
        'doubleTapSkipLeft': doubleTapSkipLeft,
        'doubleTapSkipRight': doubleTapSkipRight,
        'doubleTapCenterPause': doubleTapCenterPause,
        'brightnessSensitivity': brightnessSensitivity,
        'volumeSensitivity': volumeSensitivity,
        'seekSensitivity': seekSensitivity,
        'horizontalSeek': horizontalSeek,
        'hapticsOnGestures': hapticsOnGestures,
        'volumeBoostMax': volumeBoostMax,
        'holdLeftSpeed': holdLeftSpeed,
        'holdRightMin': holdRightMin,
        'holdRightMax': holdRightMax,
        'holdRightDetents': holdRightDetents,
        'holdRightReleaseToNormal': holdRightReleaseToNormal,
        'speedFineStep': speedFineStep,
        'speedPresets': speedPresets,
        'rememberSpeed': rememberSpeed,
        'centerSkipSeconds': centerSkipSeconds,
        'controlsAutoHideMs': controlsAutoHideMs,
        'showInfoOverlay': showInfoOverlay,
        'infoOverlayContent': infoOverlayContent,
        'infoOverlayCorner': infoOverlayCorner,
        'defaultAspectMode': defaultAspectMode,
        'resumeBehavior': resumeBehavior,
        'resumeMinSeconds': resumeMinSeconds,
        'rememberOrientationLock': rememberOrientationLock,
        'accentColor': accentColor,
        'libraryColumns': libraryColumns,
        'themeMode': themeMode,
        'librarySort': librarySort,
        'subtitlesEnabledByDefault': subtitlesEnabledByDefault,
        'preferredSubtitleLanguage': preferredSubtitleLanguage,
        'preferredAudioLanguage': preferredAudioLanguage,
        'subtitleFontSize': subtitleFontSize,
        'subtitleTextColor': subtitleTextColor,
        'subtitleBackgroundColor': subtitleBackgroundColor,
      };

  factory KivoSettings.fromMap(Map<String, dynamic> m) {
    final d = KivoSettings.defaults();
    return KivoSettings(
      doubleTapSkipLeft: m['doubleTapSkipLeft'] ?? d.doubleTapSkipLeft,
      doubleTapSkipRight: m['doubleTapSkipRight'] ?? d.doubleTapSkipRight,
      doubleTapCenterPause: m['doubleTapCenterPause'] ?? d.doubleTapCenterPause,
      brightnessSensitivity: (m['brightnessSensitivity'] ?? d.brightnessSensitivity).toDouble(),
      volumeSensitivity: (m['volumeSensitivity'] ?? d.volumeSensitivity).toDouble(),
      seekSensitivity: (m['seekSensitivity'] ?? d.seekSensitivity).toDouble(),
      horizontalSeek: m['horizontalSeek'] ?? d.horizontalSeek,
      hapticsOnGestures: m['hapticsOnGestures'] ?? d.hapticsOnGestures,
      volumeBoostMax: m['volumeBoostMax'] ?? d.volumeBoostMax,
      holdLeftSpeed: (m['holdLeftSpeed'] ?? d.holdLeftSpeed).toDouble(),
      holdRightMin: (m['holdRightMin'] ?? d.holdRightMin).toDouble(),
      holdRightMax: (m['holdRightMax'] ?? d.holdRightMax).toDouble(),
      holdRightDetents: (m['holdRightDetents'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? d.holdRightDetents,
      holdRightReleaseToNormal: m['holdRightReleaseToNormal'] ?? d.holdRightReleaseToNormal,
      speedFineStep: (m['speedFineStep'] ?? d.speedFineStep).toDouble(),
      speedPresets: (m['speedPresets'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? d.speedPresets,
      rememberSpeed: m['rememberSpeed'] ?? d.rememberSpeed,
      centerSkipSeconds: m['centerSkipSeconds'] ?? d.centerSkipSeconds,
      controlsAutoHideMs: m['controlsAutoHideMs'] ?? d.controlsAutoHideMs,
      showInfoOverlay: m['showInfoOverlay'] ?? d.showInfoOverlay,
      infoOverlayContent: m['infoOverlayContent'] ?? d.infoOverlayContent,
      infoOverlayCorner: m['infoOverlayCorner'] ?? d.infoOverlayCorner,
      defaultAspectMode: m['defaultAspectMode'] ?? d.defaultAspectMode,
      resumeBehavior: m['resumeBehavior'] ?? d.resumeBehavior,
      resumeMinSeconds: m['resumeMinSeconds'] ?? d.resumeMinSeconds,
      rememberOrientationLock: m['rememberOrientationLock'] ?? d.rememberOrientationLock,
      accentColor: m['accentColor'] ?? d.accentColor,
      libraryColumns: m['libraryColumns'] ?? d.libraryColumns,
      themeMode: m['themeMode'] ?? d.themeMode,
      librarySort: m['librarySort'] ?? d.librarySort,
      subtitlesEnabledByDefault: m['subtitlesEnabledByDefault'] ?? d.subtitlesEnabledByDefault,
      preferredSubtitleLanguage: m['preferredSubtitleLanguage'] ?? d.preferredSubtitleLanguage,
      preferredAudioLanguage: m['preferredAudioLanguage'] ?? d.preferredAudioLanguage,
      subtitleFontSize: (m['subtitleFontSize'] ?? d.subtitleFontSize).toDouble(),
      subtitleTextColor: m['subtitleTextColor'] ?? d.subtitleTextColor,
      subtitleBackgroundColor: m['subtitleBackgroundColor'] ?? d.subtitleBackgroundColor,
    );
  }
}
