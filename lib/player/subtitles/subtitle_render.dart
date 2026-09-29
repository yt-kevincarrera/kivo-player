/// Who puts the current subtitle on screen.
enum SubtitleDrawer {
  /// No subtitle track selected.
  none,

  /// Kivo's own overlay, from mpv's plain `sub-text`, in the user's style.
  kivo,

  /// mpv itself (libass / its bitmap renderer), inside the video.
  mpv,
}

/// Picture subtitles: there is no text to draw, only images mpv renders.
const bitmapSubtitleCodecs = {
  'hdmv_pgs_subtitle',
  'dvd_subtitle',
  'dvb_subtitle',
  'xsub',
};

/// Styled subtitles whose look is part of the file.
const assSubtitleCodecs = {'ass', 'ssa'};

bool isBitmapSubtitle(String? codec) =>
    codec != null && bitmapSubtitleCodecs.contains(codec);

bool isAssSubtitle(String? codec) =>
    codec != null && assSubtitleCodecs.contains(codec);

/// The one rule for who draws, given the current track.
///
/// Kivo draws plain text because Flutter's text stack falls back across every
/// script, where libass on Android sees only the font Kivo hands it. mpv
/// draws what only it can: pictures (PGS, VobSub), and ASS when the user
/// wants the file's own styling — but only if a font for libass could be
/// prepared ([fontsReady]); otherwise ASS text would come out as boxes, and
/// Kivo's plain rendering is the better failure.
///
/// An unknown codec with a track selected is treated as text: the only cost
/// of being wrong is a picture subtitle appearing a moment late.
SubtitleDrawer drawerFor({
  required bool hasTrack,
  required String? codec,
  required bool respectAssStyle,
  required bool fontsReady,
}) {
  if (!hasTrack) return SubtitleDrawer.none;
  if (isBitmapSubtitle(codec)) return SubtitleDrawer.mpv;
  if (isAssSubtitle(codec) && respectAssStyle && fontsReady) {
    return SubtitleDrawer.mpv;
  }
  return SubtitleDrawer.kivo;
}
