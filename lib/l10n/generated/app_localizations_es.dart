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

  @override
  String get settingsGeneralTitle => 'General';

  @override
  String get settingsGeneralNavSubtitle => 'Tema, color de acento, háptica';

  @override
  String get settingsGeneralGroupAppearance => 'Apariencia';

  @override
  String get settingsGeneralTheme => 'Tema';

  @override
  String get settingsGeneralThemeSubtitle => 'Claro, oscuro o según el sistema';

  @override
  String get settingsGeneralThemeAuto => 'Auto';

  @override
  String get settingsGeneralThemeDark => 'Oscuro';

  @override
  String get settingsGeneralThemeLight => 'Claro';

  @override
  String get settingsGeneralAccentColor => 'Color de acento';

  @override
  String get settingsGeneralIcons => 'Iconos';

  @override
  String get settingsGeneralIconsSubtitle => 'Duotono o plano (blanco)';

  @override
  String get settingsGeneralIconsDuotone => 'Duotono';

  @override
  String get settingsGeneralIconsFlat => 'Plano';

  @override
  String get settingsGeneralGroupInteraction => 'Interacción';

  @override
  String get settingsGeneralHaptics => 'Háptica en gestos';

  @override
  String get settingsGeneralHapticsSubtitle =>
      'Vibración sutil al cruzar umbrales';

  @override
  String get settingsGroupLibrary => 'Biblioteca';

  @override
  String get settingsHiddenFoldersTitle => 'Carpetas ocultas';

  @override
  String get settingsHiddenFoldersNavSubtitle =>
      'Carpetas que no aparecen en tu biblioteca';

  @override
  String get settingsHiddenFoldersEmpty =>
      'No has ocultado ninguna carpeta.\nMantén pulsada una carpeta en Videos para ocultarla.';

  @override
  String get settingsHiddenFoldersShowAction => 'Mostrar';

  @override
  String get settingsRootTitle => 'Ajustes';

  @override
  String get settingsPlaybackGesturesTitle => 'Reproducción y gestos';

  @override
  String get settingsPlaybackGesturesNavSubtitle =>
      'Saltos, sensibilidades, velocidad';

  @override
  String get settingsInterfaceTitle => 'Interfaz';

  @override
  String get settingsInterfaceNavSubtitle =>
      'Controles, overlay, aspecto, columnas';

  @override
  String get settingsAdvancedPlaybackTitle => 'Reproducción avanzada';

  @override
  String get settingsAdvancedPlaybackNavSubtitle =>
      'Continuar, autoplay, subtítulos, PiP';

  @override
  String get settingsEqualizerTitle => 'Ecualizador';

  @override
  String get settingsEqualizerNavSubtitle =>
      'Graves, voz, agudos y preamplificación';

  @override
  String get settingsBackupTitle => 'Copia de seguridad';

  @override
  String get settingsBackupNavSubtitle =>
      'Exporta o restaura tus listas, marcadores y ajustes';

  @override
  String get settingsAboutTitle => 'Acerca de';

  @override
  String get settingsAboutNavSubtitle => 'Versión y actualizaciones';

  @override
  String get settingsVaultNavSubtitle => 'Videos ocultos';

  @override
  String get settingsResetAction => 'Restablecer';

  @override
  String get settingsResetAllTitle => 'Restablecer valores';

  @override
  String get settingsResetAllBody =>
      '¿Restablecer todos los ajustes a sus valores por defecto?';

  @override
  String get settingsAboutDownloading => 'Descargando la actualización';

  @override
  String settingsAboutDownloadingSubtitleWithVersion(String version) {
    return 'Kivo $version · toca para ver el progreso';
  }

  @override
  String get settingsAboutDownloadingSubtitleNoVersion =>
      'Toca para ver el progreso';

  @override
  String get settingsAboutReady => 'Actualización lista para instalar';

  @override
  String settingsAboutReadySubtitleWithVersion(String version) {
    return 'Kivo $version · toca para instalarla';
  }

  @override
  String get settingsAboutReadySubtitleNoVersion => 'Toca para instalarla';

  @override
  String get settingsAboutCheckForUpdates => 'Buscar actualizaciones';

  @override
  String get settingsAboutUpToDateSnackbar => 'Estás al día ✓';

  @override
  String settingsAboutVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get settingsAboutTagline => 'Reproductor de video local';

  @override
  String get settingsAboutByAuthor => 'Por Kevin Carrera';

  @override
  String get settingsAboutErrorLogTitle => 'Registro de errores';

  @override
  String get settingsAboutErrorLogSubtitle =>
      'Los últimos fallos, con su detalle técnico';

  @override
  String get settingsAboutAutoCheck => 'Buscar automáticamente';

  @override
  String get settingsAboutAutoCheckSubtitle =>
      'Comprueba al abrir, máximo una vez al día';

  @override
  String get settingsAdvancedAutomaticOption => 'Automático';

  @override
  String settingsAdvancedLangChosen(String lang) {
    return '$lang (elegido)';
  }

  @override
  String get settingsAdvancedGroupContinueWatching => 'Continuar viendo';

  @override
  String get settingsAdvancedResumeBehavior => 'Al reabrir un video';

  @override
  String get settingsAdvancedResumeAsk => 'Preguntar';

  @override
  String get settingsAdvancedResumeOff => 'Desactivado';

  @override
  String get settingsAdvancedResumeMinSeconds =>
      'Mínimo para recordar posición';

  @override
  String get settingsAdvancedGroupPlayback => 'Reproducción';

  @override
  String get settingsAdvancedAutoplayNext =>
      'Reproducir el siguiente automáticamente';

  @override
  String get settingsAdvancedPipAutoOnHome =>
      'Miniatura flotante (PiP) al salir al inicio';

  @override
  String get settingsAdvancedMinimizeKeepsPlaying =>
      'Seguir reproduciendo al minimizar';

  @override
  String get settingsAdvancedMinimizeKeepsPlayingSubtitle =>
      'El audio continúa en la barra inferior en vez de pausarse';

  @override
  String get settingsAdvancedGroupSubtitlesAudio => 'Subtítulos y audio';

  @override
  String get settingsAdvancedSubtitlesDefault =>
      'Activar subtítulos por defecto';

  @override
  String get settingsAdvancedPreferredSubtitleLang =>
      'Idioma de subtítulos preferido';

  @override
  String get settingsAdvancedPreferredLangSubtitle =>
      'Se fija al elegir una pista; aquí puedes volver a Automático';

  @override
  String get settingsAdvancedPreferredAudioLang => 'Idioma de audio preferido';

  @override
  String get settingsAdvancedGroupStorage => 'Almacenamiento';

  @override
  String get settingsAdvancedAllFilesAccess => 'Acceso a todos los archivos';

  @override
  String get settingsAdvancedAllFilesAccessGranted => 'Concedido';

  @override
  String get settingsAdvancedAllFilesAccessPrompt =>
      'Toca para borrar y renombrar sin confirmación';

  @override
  String get settingsGesturesGroupLearn => 'Aprender';

  @override
  String get settingsGesturesViewMap => 'Ver el mapa de gestos';

  @override
  String get settingsGesturesViewMapSubtitle =>
      'Toques, arrastres y botones del reproductor';

  @override
  String get settingsGesturesGroupDoubleTap => 'Doble toque';

  @override
  String get settingsGesturesSkipBack => 'Saltar atrás';

  @override
  String get settingsGesturesSkipForward => 'Saltar adelante';

  @override
  String get settingsGesturesDoubleTapPause =>
      'Pausar con doble toque al centro';

  @override
  String get settingsGesturesGroupSeek => 'Salto y seek';

  @override
  String get settingsGesturesCenterSkip => 'Salto de los botones ±';

  @override
  String get settingsGesturesHorizontalSeek =>
      'Buscar deslizando en horizontal';

  @override
  String get settingsGesturesGroupZoom => 'Zoom';

  @override
  String get settingsGesturesPinchZoom => 'Zoom con pinch';

  @override
  String get settingsGesturesPinchZoomSubtitle =>
      'Pellizca para ampliar y arrastra para encuadrar';

  @override
  String get settingsGesturesZoomMax => 'Zoom máximo';

  @override
  String get settingsGesturesZoomReset => 'Reiniciar el zoom';

  @override
  String get settingsGesturesZoomResetSubtitle => 'Cuándo vuelve solo a 1×';

  @override
  String get settingsGesturesZoomResetExit => 'Al salir';

  @override
  String get settingsGesturesZoomResetVideo => 'Cada video';

  @override
  String get settingsGesturesZoomResetNever => 'Nunca';

  @override
  String get settingsGesturesGroupSensitivity => 'Sensibilidad de gestos';

  @override
  String get settingsGesturesBrightness => 'Brillo';

  @override
  String get settingsGesturesVolume => 'Volumen';

  @override
  String get settingsGesturesSeek => 'Seek';

  @override
  String get settingsGesturesVolumeBoostMax => 'Boost máximo de volumen';

  @override
  String get settingsGesturesGroupSpeed => 'Velocidad';

  @override
  String get settingsGesturesRememberSpeed => 'Recordar velocidad entre videos';

  @override
  String get settingsGesturesHoldLeftSpeed =>
      'Velocidad al mantener (izquierda)';

  @override
  String get settingsGesturesHoldRightMax => 'Velocidad máxima';

  @override
  String get settingsGesturesHoldRightRelease =>
      'Al soltar el acelerador, volver a la velocidad anterior';

  @override
  String get settingsGesturesSpeedFineStep => 'Paso fino de velocidad';

  @override
  String get settingsGesturesSpeedPresets => 'Velocidades preseleccionadas';

  @override
  String get settingsGesturesSpeedPresetsSubtitle =>
      'Las que aparecen en el panel de velocidad';

  @override
  String get settingsGesturesHoldRightDetents =>
      'Escalones del acelerador (hold derecho)';

  @override
  String get settingsGesturesHoldRightDetentsSubtitle =>
      'La escalera de velocidades al mantener a la derecha';

  @override
  String get settingsInterfaceGroupControls => 'Controles';

  @override
  String get settingsInterfaceAutoHide => 'Auto-ocultar controles';

  @override
  String get settingsInterfaceRememberOrientation =>
      'Recordar orientación entre videos';

  @override
  String get settingsInterfaceGroupVideo => 'Video';

  @override
  String get settingsInterfaceDefaultAspect => 'Aspecto por defecto';

  @override
  String get settingsInterfaceAspectFit => 'Ajustar';

  @override
  String get settingsInterfaceAspectFill => 'Llenar';

  @override
  String get settingsInterfaceAspectStretch => 'Estirar';

  @override
  String get settingsInterfaceGroupOverlay => 'Overlay de información';

  @override
  String get settingsInterfaceShowOverlay => 'Mostrar overlay de info';

  @override
  String get settingsInterfaceOverlayContent => 'Contenido';

  @override
  String get settingsInterfaceOverlayContentNameTime => 'Nombre y tiempo';

  @override
  String get settingsInterfaceOverlayContentNameOnly => 'Solo nombre';

  @override
  String get settingsInterfaceOverlayContentRemaining => 'Tiempo restante';

  @override
  String get settingsInterfaceOverlayCorner => 'Esquina';

  @override
  String get settingsInterfaceColumns => 'Columnas por defecto';

  @override
  String get settingsEqSwitchSubtitle =>
      'Aplica la curva de graves, voz y agudos al audio';

  @override
  String get settingsEqGroupPresets => 'Preajustes';

  @override
  String get settingsEqPresetFlat => 'Plano';

  @override
  String get settingsEqPresetBass => 'Graves';

  @override
  String get settingsEqPresetVoice => 'Voz';

  @override
  String get settingsEqPresetTreble => 'Agudos';

  @override
  String get settingsEqPresetCustom => 'Personalizado';

  @override
  String get settingsEqGroupBands => 'Bandas';

  @override
  String get settingsEqGroupPreamp => 'Preamplificación';

  @override
  String get settingsEqPreampGain => 'Ganancia general';

  @override
  String get settingsBackupExport => 'Exportar copia';

  @override
  String get settingsBackupExportSubtitle =>
      'Guarda tus listas, marcadores y ajustes en un archivo';

  @override
  String get settingsBackupRestoreTitle => 'Restaurar copia';

  @override
  String get settingsBackupRestoreSubtitle =>
      'Añade lo que haya en un archivo de copia guardado antes';

  @override
  String get settingsBackupExportSavedSnackbar => 'Copia guardada';

  @override
  String get settingsBackupExportCancelledSnackbar => 'Cancelado';

  @override
  String get settingsBackupReadFileFailedSnackbar =>
      'No se pudo leer el archivo';

  @override
  String get settingsBackupRestoreConfirmAction => 'Restaurar';

  @override
  String get settingsBackupRestoredSnackbar => 'Copia restaurada';

  @override
  String get settingsBackupReadFailedDialogTitle => 'No se pudo leer la copia';

  @override
  String settingsBackupRestoreItemPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas',
      one: '1 lista',
    );
    return '$_temp0';
  }

  @override
  String settingsBackupRestoreItemBookmarks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marcadores',
      one: '1 marcador',
    );
    return '$_temp0';
  }

  @override
  String settingsBackupRestoreItemPositions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count posiciones',
      one: '1 posición',
    );
    return '$_temp0';
  }

  @override
  String settingsBackupRestoreItemWatchedVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos vistos',
      one: '1 video visto',
    );
    return '$_temp0';
  }

  @override
  String settingsBackupRestoreItemHiddenVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos ocultos',
      one: '1 video oculto',
    );
    return '$_temp0';
  }

  @override
  String settingsBackupRestoreItemTrackSettings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ajustes de pista',
      one: '1 ajuste de pista',
    );
    return '$_temp0';
  }

  @override
  String get settingsBackupRestoreJoinWord => 'y';

  @override
  String settingsBackupRestoreWillAdd(String items) {
    return 'Se añadirán $items.';
  }

  @override
  String get settingsBackupRestoreNothingNew => 'No hay nada nuevo que añadir.';

  @override
  String get settingsBackupRestoreSettingsReplace =>
      'Los ajustes se reemplazarán.';

  @override
  String get settingsErrorLogCopyAllTooltip => 'Copiar todo';

  @override
  String get settingsErrorLogClearTooltip => 'Borrar registro';

  @override
  String get settingsErrorLogCopiedSnackbar => 'Registro copiado';

  @override
  String get settingsErrorLogEmpty => 'Sin errores registrados';

  @override
  String get settingsErrorLogAgeJustNow => 'ahora mismo';

  @override
  String settingsErrorLogAgeMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String settingsErrorLogAgeHours(int count) {
    return 'hace $count h';
  }

  @override
  String settingsErrorLogAgeDays(int count) {
    return 'hace $count d';
  }

  @override
  String settingsErrorLogDetailLine(String version, int sdk) {
    return 'Kivo $version · Android API $sdk';
  }

  @override
  String get settingsColorPickerTitle => 'Personalizado';

  @override
  String get settingsColorPickerHue => 'Matiz';

  @override
  String get settingsColorPickerSaturation => 'Saturación';

  @override
  String get settingsColorPickerBrightness => 'Brillo';

  @override
  String get settingsColorPickerApplyAction => 'Aplicar';

  @override
  String get settingsSpeedAddDialogTitle => 'Añadir velocidad';

  @override
  String get settingsSpeedAddAction => 'Añadir';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get updateGenericTitle => 'Actualización';

  @override
  String updateTitleWithVersion(String version) {
    return 'Nueva versión $version';
  }

  @override
  String get updateNoActiveDownload => 'Ya no hay ninguna descarga en curso.';

  @override
  String get updateNoNotesAvailable =>
      'Hay una versión más reciente disponible.';

  @override
  String get updateCanLeaveHint => 'Puedes salir de Kivo: la descarga sigue.';

  @override
  String get updateReadyCaption => 'Listo para instalar';

  @override
  String get updateReadyHint => 'Pulsa Instalar para continuar.';

  @override
  String updateFailedMessage(String message, String code) {
    return '$message ($code).\nPuedes reintentar o bajarla desde el navegador.';
  }

  @override
  String get updateSkipVersionAction => 'Omitir esta versión';

  @override
  String get updateOpenInBrowserAction => 'Abrir en navegador';

  @override
  String get updateDownloadAction => 'Descargar';

  @override
  String get updateHideAction => 'Ocultar';

  @override
  String get updateInstallAction => 'Instalar';

  @override
  String get updateDiscardReadyAction => 'Descartar';

  @override
  String get updateRetryAction => 'Reintentar';

  @override
  String get updateInstallNeedsPermissionSnackbar =>
      'Permite instalar apps para continuar, luego pulsa Instalar.';

  @override
  String get updateStatusQueued => 'En cola…';

  @override
  String get updateStatusPausedNetwork => 'En pausa · esperando conexión';

  @override
  String get updateStatusPausedRetry => 'En pausa · reintentando';

  @override
  String updateStatusSizePercent(String size, int percent) {
    return '$size · $percent %';
  }
}
