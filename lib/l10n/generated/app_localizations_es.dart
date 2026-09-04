// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Sistema';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get libraryTabAll => 'Todo';

  @override
  String get libraryTabFolders => 'Carpetas';

  @override
  String get libraryTabPlaylists => 'Listas';

  @override
  String get libraryUnwatchedFilter => 'No vistos';

  @override
  String get librarySearchHintPlaylists => 'Buscar listas';

  @override
  String get librarySearchHintVideos => 'Buscar videos o carpetas';

  @override
  String get librarySearchClose => 'Cerrar búsqueda';

  @override
  String get librarySearchTooltip => 'Buscar';

  @override
  String libraryDensityTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver en $count columnas',
      one: 'Ver en 1 columna',
    );
    return '$_temp0';
  }

  @override
  String get libraryOpenFile => 'Abrir archivo';

  @override
  String get librarySortTooltip => 'Ordenar';

  @override
  String get librarySortRecent => 'Más reciente';

  @override
  String get librarySortNameAsc => 'Nombre A-Z';

  @override
  String get librarySortNameDesc => 'Nombre Z-A';

  @override
  String get librarySortDurationDesc => 'Duración: más larga';

  @override
  String get librarySortDurationAsc => 'Duración: más corta';

  @override
  String get librarySortSizeDesc => 'Tamaño: más pesado';

  @override
  String get librarySortSizeAsc => 'Tamaño: más liviano';

  @override
  String get playlistSortMostVideos => 'Más videos primero';

  @override
  String get playlistSortLastPlayed => 'Última reproducida';

  @override
  String libraryNoSearchResults(String query) {
    return 'No se encontraron videos para \"$query\"';
  }

  @override
  String get librarySearchClearAction => 'Borrar búsqueda';

  @override
  String get libraryEmptyAllWatchedTitle => 'Ya viste todo';

  @override
  String get libraryEmptyAllWatchedSubtitle => 'No queda ningún video sin ver.';

  @override
  String get libraryEmptyRemoveFilterAction => 'Quitar filtro';

  @override
  String get libraryEmptyLimitedAccessTitle =>
      'Kivo solo ve los videos que elegiste';

  @override
  String get libraryEmptyLimitedAccessSubtitle =>
      'Amplía la selección para ver el resto de tu galería.';

  @override
  String get libraryEmptyChooseMoreAction => 'Elegir más videos';

  @override
  String get libraryEmptyNoVideosTitle => 'Todavía no hay videos';

  @override
  String get libraryEmptyNoVideosSubtitle =>
      'Cuando grabes o descargues uno aparecerá aquí.';

  @override
  String get libraryEmptyRescanAction => 'Volver a buscar';

  @override
  String get libraryAccessPromptTitle =>
      'Da acceso a tus videos para verlos aquí';

  @override
  String get libraryAccessPromptAction => 'Dar acceso';

  @override
  String get folderEmptyTitle => 'Esta carpeta quedó vacía';

  @override
  String folderEmptySubtitle(String folder) {
    return 'Ya no queda ningún video en «$folder».';
  }

  @override
  String get commonGoBack => 'Volver';

  @override
  String get homeTabVideos => 'Videos';

  @override
  String get homeTabSettings => 'Ajustes';

  @override
  String get videoTileNewBadge => 'Nuevo';

  @override
  String get continueRowTitle => 'Continuar viendo';

  @override
  String get commonShare => 'Compartir';

  @override
  String get commonRename => 'Renombrar';

  @override
  String get videoSheetDetails => 'Detalles';

  @override
  String get videoSheetMarkUnwatched => 'Marcar como no visto';

  @override
  String get videoSheetMarkWatched => 'Marcar como visto';

  @override
  String get videoSheetClearResume => 'Quitar de Continuar viendo';

  @override
  String get videoSheetResumeCleared => 'Quitado de Continuar viendo';

  @override
  String get playlistAddToListLabel => 'Añadir a lista';

  @override
  String get videoSheetMoveToVault => 'Mover al Vault';

  @override
  String get commonDelete => 'Borrar';

  @override
  String get allFilesAccessDialogTitle => 'Sin confirmaciones de Android';

  @override
  String get allFilesAccessDialogBody =>
      'Para borrar y renombrar sin que Android te pida confirmación cada vez, dale a Kivo acceso a los archivos.';

  @override
  String get commonNotNow => 'Ahora no';

  @override
  String get videoSheetMarkedWatched => 'Marcado como visto';

  @override
  String get videoSheetMarkedUnwatched => 'Marcado como no visto';

  @override
  String get trashMoveTitle => 'Mover a la papelera';

  @override
  String get videoSheetDeleteTitle => 'Borrar video';

  @override
  String videoSheetTrashConfirmBody(String name) {
    return '¿Mover «$name» a la papelera? Podrás recuperarlo durante 30 días desde la papelera del teléfono.';
  }

  @override
  String videoSheetDeleteConfirmBody(String name) {
    return '¿Borrar «$name»? Esta acción no se puede deshacer.';
  }

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get videoSheetDeletedSnackbar => 'Video borrado';

  @override
  String get detailsLabelName => 'Nombre';

  @override
  String get detailsLabelFolder => 'Carpeta';

  @override
  String get detailsLabelSize => 'Tamaño';

  @override
  String get detailsLabelDuration => 'Duración';

  @override
  String get detailsLabelResolution => 'Resolución';

  @override
  String get detailsLabelAdded => 'Agregado';

  @override
  String get detailsLabelUri => 'URI';

  @override
  String get commonSave => 'Guardar';

  @override
  String selectionCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados',
      one: '$count seleccionado',
    );
    return '$_temp0';
  }

  @override
  String get selectionSelectAll => 'Seleccionar todo';

  @override
  String get selectionMoveToVault => 'Al Vault';

  @override
  String get selectionAddToList => 'A una lista';

  @override
  String get selectionDeleteTitle => 'Borrar videos';

  @override
  String selectionTrashConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '¿Mover $count videos a la papelera?\n\nPodrás recuperarlos durante 30 días desde la papelera del teléfono.',
      one:
          '¿Mover 1 video a la papelera?\n\nPodrás recuperarlos durante 30 días desde la papelera del teléfono.',
    );
    return '$_temp0';
  }

  @override
  String selectionDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Borrar $count videos? Esta acción no se puede deshacer.',
      one: '¿Borrar 1 video? Esta acción no se puede deshacer.',
    );
    return '$_temp0';
  }

  @override
  String selectionTrashedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos movidos a la papelera',
      one: '1 video movido a la papelera',
    );
    return '$_temp0';
  }

  @override
  String selectionDeletedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos borrados',
      one: '1 video borrado',
    );
    return '$_temp0';
  }

  @override
  String get foldersEmptyTitle => 'No hay carpetas';

  @override
  String get foldersEmptySubtitle =>
      'Tus videos aparecerán aquí agrupados por carpeta.';

  @override
  String folderCardVideoCount(int count) {
    return '$count vids';
  }

  @override
  String get folderHideTitle => 'Ocultar de la biblioteca';

  @override
  String get folderHideSubtitle =>
      'No se borra ni se mueve nada: solo deja de aparecer en Kivo.';

  @override
  String folderHiddenSnackbar(String folder) {
    return '$folder oculta';
  }

  @override
  String get commonUndo => 'Deshacer';

  @override
  String get playlistsEmptyTitle => 'Todavía no tienes listas';

  @override
  String get playlistsEmptySubtitle =>
      'Una lista es un orden que tú eliges: crea una y añade videos desde la selección o desde el menú de un video.';

  @override
  String get playlistNewListLabel => 'Nueva lista';

  @override
  String playlistsNoSearchResults(String query) {
    return 'Ninguna lista coincide con \"$query\"';
  }

  @override
  String get commonCreate => 'Crear';

  @override
  String playlistsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas seleccionadas',
      one: '1 lista seleccionada',
    );
    return '$_temp0';
  }

  @override
  String get playlistsBulkDeleteTitle => 'Borrar listas';

  @override
  String playlistsBulkDeleteBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '¿Borrar $count listas? Esta acción no se puede deshacer. Los videos no se borran, solo las listas.',
      one:
          '¿Borrar 1 lista? Esta acción no se puede deshacer. Los videos no se borran, solo las listas.',
    );
    return '$_temp0';
  }

  @override
  String get playlistRenameTitle => 'Renombrar lista';

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
      other: '$count no disponibles',
      one: '$count no disponible',
    );
    return '$_temp0';
  }

  @override
  String get playlistAddSheetEmpty =>
      'Todavía no tienes listas. Crea una para empezar.';

  @override
  String playlistAddedSnackbar(String name) {
    return 'Añadido a «$name»';
  }

  @override
  String get playlistPlayLabel => 'Reproducir';

  @override
  String get playlistEmptyTitle => 'Esta lista está vacía';

  @override
  String get playlistEmptySubtitle =>
      'Añade videos desde la selección o desde el menú de un video, con «Añadir a lista».';

  @override
  String get playlistRemoveEntryTooltip => 'Quitar de la lista';

  @override
  String playlistEntryRemovedSnackbar(String name) {
    return '«$name» quitado de la lista';
  }

  @override
  String get playlistNothingToPlaySnackbar =>
      'Nada disponible para reproducir ahora mismo';

  @override
  String get playlistDeleteTitle => 'Borrar lista';

  @override
  String playlistDeleteConfirmBody(String name) {
    return '¿Borrar «$name»? Esta acción no se puede deshacer. Los videos no se borran, solo la lista.';
  }

  @override
  String get playlistEntryUnavailable => 'No disponible';
}
