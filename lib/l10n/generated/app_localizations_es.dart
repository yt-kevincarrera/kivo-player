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

  @override
  String get playerAutoplayNextLabel => 'PRÓXIMO';

  @override
  String get playerAutoplayPlayAction => 'Reproducir';

  @override
  String get playerBookmarksTitle => 'Marcadores';

  @override
  String get playerBookmarksEmpty => 'Todavía no marcaste nada en este video.';

  @override
  String get playerBookmarksRenameDialogTitle => 'Nombrar marcador';

  @override
  String playerBookmarksDeletedUnnamedSnackbar(String time) {
    return 'Marcador borrado · $time';
  }

  @override
  String playerBookmarksDeletedNamedSnackbar(String name) {
    return '«$name» borrado';
  }

  @override
  String get playerChaptersTitle => 'Capítulos';

  @override
  String get playerChaptersEmpty => 'Este video no tiene capítulos.';

  @override
  String get playerChaptersPrevious => 'Anterior';

  @override
  String get playerChaptersNext => 'Siguiente';

  @override
  String get playerSpeedTooltip => 'Velocidad';

  @override
  String get playerLockScreenTooltip => 'Bloquear pantalla';

  @override
  String get playerAspectRatioTooltip => 'Relación de aspecto';

  @override
  String get playerRotateTooltip => 'Rotar';

  @override
  String playerSkipForwardTooltip(int seconds) {
    return 'Avanzar ${seconds}s';
  }

  @override
  String playerSkipBackTooltip(int seconds) {
    return 'Retroceder ${seconds}s';
  }

  @override
  String get playerPauseTooltip => 'Pausar';

  @override
  String get playerPlayTooltip => 'Reproducir';

  @override
  String get playerHoldToUnlockHint => 'mantén para desbloquear';

  @override
  String playerResumeUndoneMessage(String pos) {
    return 'Reanudado desde $pos';
  }

  @override
  String get playerResumeRestartAction => 'Reiniciar';

  @override
  String playerResumeAskMessage(String pos) {
    return '¿Reanudar desde $pos?';
  }

  @override
  String get playerResumeFromStartAction => 'Desde el inicio';

  @override
  String get playerResumeAction => 'Reanudar';

  @override
  String get playerBackTooltip => 'Atrás';

  @override
  String get playerInfoOverlayHideTooltip => 'Ocultar información en pantalla';

  @override
  String get playerInfoOverlayShowTooltip => 'Mostrar información en pantalla';

  @override
  String get playerSubtitlesTooltip => 'Subtítulos';

  @override
  String get playerPipTooltip => 'Imagen en imagen';

  @override
  String get playerAudioTooltip => 'Audio';

  @override
  String get playerMoreOptionsTooltip => 'Más opciones';

  @override
  String get playerLoopMarkA => 'Marcar A';

  @override
  String get playerLoopMarkB => 'Marcar B';

  @override
  String playerLoopPointALabel(String time) {
    return 'A $time';
  }

  @override
  String get playerLoopSubtitleIdle => 'Repetir un fragmento del video';

  @override
  String get playerLoopSubtitleMarking => 'Marcando…';

  @override
  String playerLoopSubtitleActive(String range) {
    return 'Activo · $range';
  }

  @override
  String playerMenuChaptersSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capítulos',
      one: '1 capítulo',
      zero: 'Sin capítulos',
    );
    return '$_temp0';
  }

  @override
  String get playerMenuSleepBadgeEpisode => 'Al terminar';

  @override
  String playerMenuSleepBadgeEpisodes(int count) {
    return '$count ep';
  }

  @override
  String get playerMenuMarkHere => 'Marcar aquí';

  @override
  String get playerMenuCapture => 'Capturar';

  @override
  String get playerMenuSleepTimer => 'Temporizador';

  @override
  String get playerMenuSync => 'Sincronizar';

  @override
  String get playerMenuGroupPlayback => 'Reproducción';

  @override
  String get playerMenuRepeat => 'Repetir';

  @override
  String get playerMenuOptionOff => 'No';

  @override
  String get playerMenuRepeatList => 'Lista';

  @override
  String get playerMenuRepeatVideoOption => 'Video';

  @override
  String get playerMenuShuffle => 'Aleatorio';

  @override
  String get playerMenuOptionOn => 'Sí';

  @override
  String get playerMenuAbLoop => 'Bucle A-B';

  @override
  String get playerMenuGroupGoTo => 'Ir a';

  @override
  String playerMenuBookmarksSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marcadores',
      one: '1 marcador',
      zero: 'Sin marcadores',
    );
    return '$_temp0';
  }

  @override
  String get playerMenuGroupAudio => 'Audio';

  @override
  String get playerMenuEqualizer => 'Ecualizador';

  @override
  String playerMenuBookmarkSavedSnackbar(String time) {
    return 'Marcador guardado · $time';
  }

  @override
  String get playerMenuBookmarkNameAction => 'Nombrar';

  @override
  String get playerMenuCaptureSavedSnackbar => 'Captura guardada';

  @override
  String get playerMenuCaptureViewAction => 'Ver';

  @override
  String get playerQueueNowBadge => 'AHORA';

  @override
  String get playerSleepPanelTitle => 'Temporizador de apagado';

  @override
  String get playerSleepDurationLabel => 'Duración';

  @override
  String playerSleepMinutesValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get playerSleepOrLabel => 'O bien';

  @override
  String playerSleepStartAfterEpisodes(int count) {
    return 'Iniciar · Tras $count episodios';
  }

  @override
  String get playerSleepStartAtEpisodeEnd =>
      'Iniciar · Al terminar el episodio';

  @override
  String playerSleepStartFixedMinutes(int minutes) {
    return 'Iniciar · $minutes min';
  }

  @override
  String playerSleepRemainingOfMinutes(int minutes) {
    return 'restante · de $minutes min';
  }

  @override
  String playerSleepEpisodesRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'episodios restantes',
      one: 'episodio restante',
    );
    return '$_temp0';
  }

  @override
  String get playerSleepUntilEpisodeEnd => 'hasta el final del episodio';

  @override
  String get playerSleepDeactivate => 'Desactivar';

  @override
  String playerSleepExtendByMinutes(int minutes) {
    return 'Extender +$minutes';
  }

  @override
  String get playerSleepEpisodeCardTitle => 'Al terminar el episodio';

  @override
  String get playerSleepEpisodeCardSubtitle =>
      'Se detiene cuando termine este video';

  @override
  String get playerSleepEpisodesCardTitle => 'Tras N episodios';

  @override
  String get playerSleepEpisodesCardSubtitle =>
      'Deja correr el autoplay y detiene';

  @override
  String get playerSleepPausingInLabel => 'Pausando en ';

  @override
  String get playerSleepExtendAction => 'Extender';

  @override
  String playerSpeedSavePreset(String rate) {
    return 'Guardar ${rate}x';
  }

  @override
  String get playerSpeedResetAction => 'Restablecer (1x)';

  @override
  String get playerAspectFit => 'Ajustar';

  @override
  String get playerAspectFill => 'Llenar';

  @override
  String get playerAspectStretch => 'Estirar';

  @override
  String get playerTracksTabLabel => 'Pistas';

  @override
  String get playerTracksStyleTabLabel => 'Estilo';

  @override
  String get playerTracksShowSubtitles => 'Mostrar subtítulos';

  @override
  String get playerTracksSectionInVideo => 'En el video';

  @override
  String get playerTracksEmbeddedDefault => 'Pista incrustada · predeterminada';

  @override
  String get playerTracksEmbedded => 'Pista incrustada';

  @override
  String get playerTracksSectionSync => 'Sincronía';

  @override
  String get playerTracksSyncSubtitles => 'Sincronizar subtítulos';

  @override
  String get playerTracksSyncAudio => 'Sincronizar audio';

  @override
  String get playerTracksSyncNeedsSubtitle =>
      'Activa un subtítulo para poder ajustarlo';

  @override
  String get playerTracksSyncHint => 'Ajustar el desfase mientras se reproduce';

  @override
  String get playerTracksSectionInFolder => 'En la carpeta';

  @override
  String get playerTracksLocalFile => 'Archivo local';

  @override
  String get playerTracksNoSubtitlesFound =>
      'Este video no trae subtítulos incrustados ni hay archivos junto a él.';

  @override
  String get playerTracksNoOtherAudioTracks =>
      'Este video no tiene otras pistas de audio.';

  @override
  String get playerTracksSectionFromDevice => 'Desde tu dispositivo';

  @override
  String get playerTracksLoadSubtitleAction => 'Cargar subtítulo…';

  @override
  String get playerTracksLoadSubtitleHint =>
      'Elegir un archivo .srt, .ass o .vtt';

  @override
  String get playerTracksBgTransparent => 'Transparente';

  @override
  String get playerTracksBgBlack => 'Negro';

  @override
  String get playerTracksBgWhite => 'Blanco';

  @override
  String get playerTracksStylePreviewSample => 'Estamos cerca de encontrarlo.';

  @override
  String get playerTracksSizeLabel => 'Tamaño';

  @override
  String get playerTracksTextColorLabel => 'Color de texto';

  @override
  String get playerTracksBackgroundColorLabel => 'Color de fondo';

  @override
  String get playerTracksResetStyleAction => 'Restablecer estilo';

  @override
  String get playerSyncDragHint => 'arrastra la barra o usa los botones';

  @override
  String get playerTutorialPageTaps => 'Toques';

  @override
  String playerTutorialDoubleTapBack(int seconds) {
    return 'Doble toque · −$seconds s';
  }

  @override
  String get playerTutorialDoubleTapPause => 'Doble toque · Pausa';

  @override
  String playerTutorialDoubleTapForward(int seconds) {
    return 'Doble toque · +$seconds s';
  }

  @override
  String get playerTutorialSingleTapToggleControls =>
      'Un toque · Mostrar u ocultar los controles';

  @override
  String get playerTutorialPageDrags => 'Arrastres';

  @override
  String get playerTutorialDragBrightness => 'Arrastra · Brillo';

  @override
  String playerTutorialDragVolume(int percent) {
    return 'Arrastra · Volumen (hasta $percent%)';
  }

  @override
  String get playerTutorialDragSeekPreview =>
      'Arrastra · Buscar con vista previa';

  @override
  String get playerTutorialDragEdgeMinimize =>
      'Arrastra en el borde · Minimizar';

  @override
  String get playerTutorialDragCenterRotate =>
      'Arrastra en el centro · Girar (con los controles ocultos)';

  @override
  String playerTutorialPinchZoom(String zoom) {
    return 'Pellizca · Zoom (hasta $zoom)';
  }

  @override
  String get playerTutorialZoomPan =>
      'Con zoom, arrastra · Encuadrar · Toca la píldora para volver a 1×';

  @override
  String playerTutorialHoldLeftSpeed(String speed) {
    return 'Mantén pulsado a la izquierda · $speed';
  }

  @override
  String get playerTutorialHoldRightLadder =>
      'Mantén y desliza arriba o abajo a la derecha · Escalera de velocidad';

  @override
  String get playerTutorialPageButtons => 'Botones';

  @override
  String get playerTutorialMinimize => 'Minimizar a la mini-barra';

  @override
  String get playerTutorialInfoOverlay => 'Información en pantalla';

  @override
  String get playerTutorialAudioTracks => 'Pistas de audio';

  @override
  String get playerTutorialMoreOptions =>
      'Más opciones · temporizador y bucle A-B';

  @override
  String get playerTutorialLockScreen => 'Bloquear la pantalla';

  @override
  String get playerTutorialQueueHint =>
      'Con más de un video en la carpeta aparece la cola sobre los botones';

  @override
  String get playerTutorialDoneAction => 'Entendido';

  @override
  String get playerTutorialNextAction => 'Siguiente';

  @override
  String get playerTutorialTopBarSection => 'Barra de arriba';

  @override
  String get playerTutorialBottomBarSection => 'Barra de abajo';
}
