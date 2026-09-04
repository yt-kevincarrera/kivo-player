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
}
