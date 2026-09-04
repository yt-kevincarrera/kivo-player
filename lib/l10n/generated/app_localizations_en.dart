// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get libraryTabAll => 'All';

  @override
  String get libraryTabFolders => 'Folders';

  @override
  String get libraryTabPlaylists => 'Playlists';

  @override
  String get libraryUnwatchedFilter => 'Unwatched';

  @override
  String get librarySearchHintPlaylists => 'Search playlists';

  @override
  String get librarySearchHintVideos => 'Search videos or folders';

  @override
  String get librarySearchClose => 'Close search';

  @override
  String get librarySearchTooltip => 'Search';

  @override
  String libraryDensityTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View in $count columns',
      one: 'View in 1 column',
    );
    return '$_temp0';
  }

  @override
  String get libraryOpenFile => 'Open file';

  @override
  String get librarySortTooltip => 'Sort';

  @override
  String get librarySortRecent => 'Most recent';

  @override
  String get librarySortNameAsc => 'Name A-Z';

  @override
  String get librarySortNameDesc => 'Name Z-A';

  @override
  String get librarySortDurationDesc => 'Duration: longest';

  @override
  String get librarySortDurationAsc => 'Duration: shortest';

  @override
  String get librarySortSizeDesc => 'Size: largest';

  @override
  String get librarySortSizeAsc => 'Size: smallest';

  @override
  String get playlistSortMostVideos => 'Most videos first';

  @override
  String get playlistSortLastPlayed => 'Last played';

  @override
  String libraryNoSearchResults(String query) {
    return 'No videos found for \"$query\"';
  }

  @override
  String get librarySearchClearAction => 'Clear search';

  @override
  String get libraryEmptyAllWatchedTitle => 'You\'ve watched everything';

  @override
  String get libraryEmptyAllWatchedSubtitle =>
      'There\'s no unwatched video left.';

  @override
  String get libraryEmptyRemoveFilterAction => 'Remove filter';

  @override
  String get libraryEmptyLimitedAccessTitle =>
      'Kivo only sees the videos you picked';

  @override
  String get libraryEmptyLimitedAccessSubtitle =>
      'Widen the selection to see the rest of your gallery.';

  @override
  String get libraryEmptyChooseMoreAction => 'Choose more videos';

  @override
  String get libraryEmptyNoVideosTitle => 'No videos yet';

  @override
  String get libraryEmptyNoVideosSubtitle =>
      'It\'ll show up here once you record or download one.';

  @override
  String get libraryEmptyRescanAction => 'Scan again';

  @override
  String get libraryAccessPromptTitle =>
      'Grant access to your videos to see them here';

  @override
  String get libraryAccessPromptAction => 'Grant access';

  @override
  String get folderEmptyTitle => 'This folder is now empty';

  @override
  String folderEmptySubtitle(String folder) {
    return 'There\'s no video left in \"$folder\".';
  }

  @override
  String get commonGoBack => 'Go back';

  @override
  String get homeTabVideos => 'Videos';

  @override
  String get homeTabSettings => 'Settings';

  @override
  String get videoTileNewBadge => 'New';

  @override
  String get continueRowTitle => 'Continue watching';

  @override
  String get commonShare => 'Share';

  @override
  String get commonRename => 'Rename';

  @override
  String get videoSheetDetails => 'Details';

  @override
  String get videoSheetMarkUnwatched => 'Mark as unwatched';

  @override
  String get videoSheetMarkWatched => 'Mark as watched';

  @override
  String get videoSheetClearResume => 'Remove from Continue watching';

  @override
  String get videoSheetResumeCleared => 'Removed from Continue watching';

  @override
  String get playlistAddToListLabel => 'Add to playlist';

  @override
  String get videoSheetMoveToVault => 'Move to Vault';

  @override
  String get commonDelete => 'Delete';

  @override
  String get allFilesAccessDialogTitle => 'No Android confirmations';

  @override
  String get allFilesAccessDialogBody =>
      'To delete and rename without Android asking you to confirm every time, give Kivo access to your files.';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get videoSheetMarkedWatched => 'Marked as watched';

  @override
  String get videoSheetMarkedUnwatched => 'Marked as unwatched';

  @override
  String get trashMoveTitle => 'Move to trash';

  @override
  String get videoSheetDeleteTitle => 'Delete video';

  @override
  String videoSheetTrashConfirmBody(String name) {
    return 'Move \"$name\" to the trash? You can recover it from your phone\'s trash for 30 days.';
  }

  @override
  String videoSheetDeleteConfirmBody(String name) {
    return 'Delete \"$name\"? This can\'t be undone.';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get videoSheetDeletedSnackbar => 'Video deleted';

  @override
  String get detailsLabelName => 'Name';

  @override
  String get detailsLabelFolder => 'Folder';

  @override
  String get detailsLabelSize => 'Size';

  @override
  String get detailsLabelDuration => 'Duration';

  @override
  String get detailsLabelResolution => 'Resolution';

  @override
  String get detailsLabelAdded => 'Added';

  @override
  String get detailsLabelUri => 'URI';

  @override
  String get commonSave => 'Save';

  @override
  String selectionCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '$count selected',
    );
    return '$_temp0';
  }

  @override
  String get selectionSelectAll => 'Select all';

  @override
  String get selectionMoveToVault => 'To Vault';

  @override
  String get selectionAddToList => 'To a playlist';

  @override
  String get selectionDeleteTitle => 'Delete videos';

  @override
  String selectionTrashConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Move $count videos to the trash?\n\nYou can recover them from your phone\'s trash for 30 days.',
      one:
          'Move 1 video to the trash?\n\nYou can recover it from your phone\'s trash for 30 days.',
    );
    return '$_temp0';
  }

  @override
  String selectionDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count videos? This can\'t be undone.',
      one: 'Delete 1 video? This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String selectionTrashedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos moved to the trash',
      one: '1 video moved to the trash',
    );
    return '$_temp0';
  }

  @override
  String selectionDeletedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos deleted',
      one: '1 video deleted',
    );
    return '$_temp0';
  }

  @override
  String get foldersEmptyTitle => 'No folders';

  @override
  String get foldersEmptySubtitle =>
      'Your videos will show up here grouped by folder.';

  @override
  String folderCardVideoCount(int count) {
    return '$count vids';
  }

  @override
  String get folderHideTitle => 'Hide from library';

  @override
  String get folderHideSubtitle =>
      'Nothing is deleted or moved: it just stops showing up in Kivo.';

  @override
  String folderHiddenSnackbar(String folder) {
    return '$folder hidden';
  }

  @override
  String get commonUndo => 'Undo';

  @override
  String get playlistsEmptyTitle => 'You don\'t have any playlists yet';

  @override
  String get playlistsEmptySubtitle =>
      'A playlist is an order you choose: create one and add videos from selection or from a video\'s menu.';

  @override
  String get playlistNewListLabel => 'New playlist';

  @override
  String playlistsNoSearchResults(String query) {
    return 'No playlist matches \"$query\"';
  }

  @override
  String get commonCreate => 'Create';

  @override
  String playlistsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists selected',
      one: '1 playlist selected',
    );
    return '$_temp0';
  }

  @override
  String get playlistsBulkDeleteTitle => 'Delete playlists';

  @override
  String playlistsBulkDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Delete $count playlists? This can\'t be undone. The videos aren\'t deleted, only the playlists.',
      one:
          'Delete 1 playlist? This can\'t be undone. The videos aren\'t deleted, only the playlists.',
    );
    return '$_temp0';
  }

  @override
  String get playlistRenameTitle => 'Rename playlist';

  @override
  String playlistRowVideoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '1 video',
    );
    return '$_temp0';
  }

  @override
  String playlistRowMissingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unavailable',
      one: '$count unavailable',
    );
    return '$_temp0';
  }

  @override
  String get playlistAddSheetEmpty =>
      'You don\'t have any playlists yet. Create one to get started.';

  @override
  String playlistAddedSnackbar(String name) {
    return 'Added to \"$name\"';
  }

  @override
  String get playlistPlayLabel => 'Play';

  @override
  String get playlistEmptyTitle => 'This playlist is empty';

  @override
  String get playlistEmptySubtitle =>
      'Add videos from selection or from a video\'s menu, with \"Add to playlist\".';

  @override
  String get playlistRemoveEntryTooltip => 'Remove from playlist';

  @override
  String playlistEntryRemovedSnackbar(String name) {
    return '\"$name\" removed from the playlist';
  }

  @override
  String get playlistNothingToPlaySnackbar =>
      'Nothing available to play right now';

  @override
  String get playlistDeleteTitle => 'Delete playlist';

  @override
  String playlistDeleteConfirmBody(String name) {
    return 'Delete \"$name\"? This can\'t be undone. The videos aren\'t deleted, only the playlist.';
  }

  @override
  String get playlistEntryUnavailable => 'Unavailable';

  @override
  String get playerAutoplayNextLabel => 'NEXT';

  @override
  String get playerAutoplayPlayAction => 'Play';

  @override
  String get playerBookmarksTitle => 'Bookmarks';

  @override
  String get playerBookmarksEmpty =>
      'You haven\'t marked anything in this video yet.';

  @override
  String get playerBookmarksRenameDialogTitle => 'Name bookmark';

  @override
  String playerBookmarksDeletedUnnamedSnackbar(String time) {
    return 'Bookmark deleted · $time';
  }

  @override
  String playerBookmarksDeletedNamedSnackbar(String name) {
    return '\"$name\" deleted';
  }

  @override
  String get playerChaptersTitle => 'Chapters';

  @override
  String get playerChaptersEmpty => 'This video has no chapters.';

  @override
  String get playerChaptersPrevious => 'Previous';

  @override
  String get playerChaptersNext => 'Next';

  @override
  String get playerSpeedTooltip => 'Speed';

  @override
  String get playerLockScreenTooltip => 'Lock screen';

  @override
  String get playerAspectRatioTooltip => 'Aspect ratio';

  @override
  String get playerRotateTooltip => 'Rotate';

  @override
  String playerSkipForwardTooltip(int seconds) {
    return 'Forward ${seconds}s';
  }

  @override
  String playerSkipBackTooltip(int seconds) {
    return 'Back ${seconds}s';
  }

  @override
  String get playerPauseTooltip => 'Pause';

  @override
  String get playerPlayTooltip => 'Play';

  @override
  String get playerHoldToUnlockHint => 'hold to unlock';

  @override
  String playerResumeUndoneMessage(String pos) {
    return 'Resumed from $pos';
  }

  @override
  String get playerResumeRestartAction => 'Restart';

  @override
  String playerResumeAskMessage(String pos) {
    return 'Resume from $pos?';
  }

  @override
  String get playerResumeFromStartAction => 'From the start';

  @override
  String get playerResumeAction => 'Resume';

  @override
  String get playerBackTooltip => 'Back';

  @override
  String get playerInfoOverlayHideTooltip => 'Hide on-screen info';

  @override
  String get playerInfoOverlayShowTooltip => 'Show on-screen info';

  @override
  String get playerSubtitlesTooltip => 'Subtitles';

  @override
  String get playerPipTooltip => 'Picture in picture';

  @override
  String get playerAudioTooltip => 'Audio';

  @override
  String get playerMoreOptionsTooltip => 'More options';

  @override
  String get playerLoopMarkA => 'Mark A';

  @override
  String get playerLoopMarkB => 'Mark B';

  @override
  String playerLoopPointALabel(String time) {
    return 'A $time';
  }

  @override
  String get playerLoopSubtitleIdle => 'Repeat a section of the video';

  @override
  String get playerLoopSubtitleMarking => 'Marking…';

  @override
  String playerLoopSubtitleActive(String range) {
    return 'Active · $range';
  }

  @override
  String playerMenuChaptersSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
      zero: 'No chapters',
    );
    return '$_temp0';
  }

  @override
  String get playerMenuSleepBadgeEpisode => 'At the end';

  @override
  String playerMenuSleepBadgeEpisodes(int count) {
    return '$count ep';
  }

  @override
  String get playerMenuMarkHere => 'Mark here';

  @override
  String get playerMenuCapture => 'Capture';

  @override
  String get playerMenuSleepTimer => 'Sleep timer';

  @override
  String get playerMenuSync => 'Sync';

  @override
  String get playerMenuGroupPlayback => 'Playback';

  @override
  String get playerMenuRepeat => 'Repeat';

  @override
  String get playerMenuOptionOff => 'Off';

  @override
  String get playerMenuRepeatList => 'List';

  @override
  String get playerMenuRepeatVideoOption => 'Video';

  @override
  String get playerMenuShuffle => 'Shuffle';

  @override
  String get playerMenuOptionOn => 'On';

  @override
  String get playerMenuAbLoop => 'A-B loop';

  @override
  String get playerMenuGroupGoTo => 'Go to';

  @override
  String playerMenuBookmarksSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookmarks',
      one: '1 bookmark',
      zero: 'No bookmarks',
    );
    return '$_temp0';
  }

  @override
  String get playerMenuGroupAudio => 'Audio';

  @override
  String get playerMenuEqualizer => 'Equalizer';

  @override
  String playerMenuBookmarkSavedSnackbar(String time) {
    return 'Bookmark saved · $time';
  }

  @override
  String get playerMenuBookmarkNameAction => 'Name';

  @override
  String get playerMenuCaptureSavedSnackbar => 'Frame captured';

  @override
  String get playerMenuCaptureViewAction => 'View';

  @override
  String get playerQueueNowBadge => 'NOW';

  @override
  String get playerSleepPanelTitle => 'Sleep timer';

  @override
  String get playerSleepDurationLabel => 'Duration';

  @override
  String playerSleepMinutesValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get playerSleepOrLabel => 'Or';

  @override
  String playerSleepStartAfterEpisodes(int count) {
    return 'Start · After $count episodes';
  }

  @override
  String get playerSleepStartAtEpisodeEnd =>
      'Start · At the end of the episode';

  @override
  String playerSleepStartFixedMinutes(int minutes) {
    return 'Start · $minutes min';
  }

  @override
  String playerSleepRemainingOfMinutes(int minutes) {
    return 'remaining · of $minutes min';
  }

  @override
  String playerSleepEpisodesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'episodes remaining',
      one: 'episode remaining',
    );
    return '$_temp0';
  }

  @override
  String get playerSleepUntilEpisodeEnd => 'until the end of the episode';

  @override
  String get playerSleepDeactivate => 'Turn off';

  @override
  String playerSleepExtendByMinutes(int minutes) {
    return 'Extend +$minutes';
  }

  @override
  String get playerSleepEpisodeCardTitle => 'At the end of the episode';

  @override
  String get playerSleepEpisodeCardSubtitle => 'Stops when this video ends';

  @override
  String get playerSleepEpisodesCardTitle => 'After N episodes';

  @override
  String get playerSleepEpisodesCardSubtitle =>
      'Lets autoplay run and then stops';

  @override
  String get playerSleepPausingInLabel => 'Pausing in ';

  @override
  String get playerSleepExtendAction => 'Extend';

  @override
  String playerSpeedSavePreset(String rate) {
    return 'Save ${rate}x';
  }

  @override
  String get playerSpeedResetAction => 'Reset (1x)';

  @override
  String get playerAspectFit => 'Fit';

  @override
  String get playerAspectFill => 'Fill';

  @override
  String get playerAspectStretch => 'Stretch';

  @override
  String get playerTracksTabLabel => 'Tracks';

  @override
  String get playerTracksStyleTabLabel => 'Style';

  @override
  String get playerTracksShowSubtitles => 'Show subtitles';

  @override
  String get playerTracksSectionInVideo => 'In the video';

  @override
  String get playerTracksEmbeddedDefault => 'Embedded track · default';

  @override
  String get playerTracksEmbedded => 'Embedded track';

  @override
  String get playerTracksSectionSync => 'Sync';

  @override
  String get playerTracksSyncSubtitles => 'Sync subtitles';

  @override
  String get playerTracksSyncAudio => 'Sync audio';

  @override
  String get playerTracksSyncNeedsSubtitle => 'Turn on a subtitle to adjust it';

  @override
  String get playerTracksSyncHint => 'Adjust the offset during playback';

  @override
  String get playerTracksSectionInFolder => 'In the folder';

  @override
  String get playerTracksLocalFile => 'Local file';

  @override
  String get playerTracksNoSubtitlesFound =>
      'This video has no embedded subtitles and there are no files next to it.';

  @override
  String get playerTracksNoOtherAudioTracks =>
      'This video has no other audio tracks.';

  @override
  String get playerTracksSectionFromDevice => 'From your device';

  @override
  String get playerTracksLoadSubtitleAction => 'Load subtitle…';

  @override
  String get playerTracksLoadSubtitleHint => 'Choose a .srt, .ass or .vtt file';

  @override
  String get playerTracksBgTransparent => 'Transparent';

  @override
  String get playerTracksBgBlack => 'Black';

  @override
  String get playerTracksBgWhite => 'White';

  @override
  String get playerTracksStylePreviewSample => 'We\'re close to finding it.';

  @override
  String get playerTracksSizeLabel => 'Size';

  @override
  String get playerTracksTextColorLabel => 'Text color';

  @override
  String get playerTracksBackgroundColorLabel => 'Background color';

  @override
  String get playerTracksResetStyleAction => 'Reset style';

  @override
  String get playerSyncDragHint => 'drag the bar or use the buttons';

  @override
  String get playerTutorialPageTaps => 'Taps';

  @override
  String playerTutorialDoubleTapBack(int seconds) {
    return 'Double tap · −$seconds s';
  }

  @override
  String get playerTutorialDoubleTapPause => 'Double tap · Pause';

  @override
  String playerTutorialDoubleTapForward(int seconds) {
    return 'Double tap · +$seconds s';
  }

  @override
  String get playerTutorialSingleTapToggleControls =>
      'Single tap · Show or hide the controls';

  @override
  String get playerTutorialPageDrags => 'Drags';

  @override
  String get playerTutorialDragBrightness => 'Drag · Brightness';

  @override
  String playerTutorialDragVolume(int percent) {
    return 'Drag · Volume (up to $percent%)';
  }

  @override
  String get playerTutorialDragSeekPreview => 'Drag · Seek with preview';

  @override
  String get playerTutorialDragEdgeMinimize => 'Drag on the edge · Minimize';

  @override
  String get playerTutorialDragCenterRotate =>
      'Drag in the center · Rotate (with the controls hidden)';

  @override
  String playerTutorialPinchZoom(String zoom) {
    return 'Pinch · Zoom (up to $zoom)';
  }

  @override
  String get playerTutorialZoomPan =>
      'While zoomed, drag · Pan · Tap the pill to return to 1×';

  @override
  String playerTutorialHoldLeftSpeed(String speed) {
    return 'Hold on the left · $speed';
  }

  @override
  String get playerTutorialHoldRightLadder =>
      'Hold and slide up or down on the right · Speed ladder';

  @override
  String get playerTutorialPageButtons => 'Buttons';

  @override
  String get playerTutorialMinimize => 'Minimize to the mini-bar';

  @override
  String get playerTutorialInfoOverlay => 'On-screen info';

  @override
  String get playerTutorialAudioTracks => 'Audio tracks';

  @override
  String get playerTutorialMoreOptions =>
      'More options · sleep timer and A-B loop';

  @override
  String get playerTutorialLockScreen => 'Lock the screen';

  @override
  String get playerTutorialQueueHint =>
      'With more than one video in the folder, the queue appears above the buttons';

  @override
  String get playerTutorialDoneAction => 'Got it';

  @override
  String get playerTutorialNextAction => 'Next';

  @override
  String get playerTutorialTopBarSection => 'Top bar';

  @override
  String get playerTutorialBottomBarSection => 'Bottom bar';
}
