import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// Título de la fila selectora de idioma en Ajustes → General.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get settingsLanguage;

  /// Opción del selector de idioma: seguir el idioma del sistema operativo.
  ///
  /// In es, this message translates to:
  /// **'Sistema'**
  String get settingsLanguageSystem;

  /// Opción del selector de idioma: fijar español, sin importar el idioma del sistema. El nombre del idioma se muestra siempre en ese mismo idioma, no se traduce.
  ///
  /// In es, this message translates to:
  /// **'Español'**
  String get settingsLanguageSpanish;

  /// Opción del selector de idioma: fijar inglés, sin importar el idioma del sistema. El nombre del idioma se muestra siempre en ese mismo idioma, no se traduce.
  ///
  /// In es, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Chip de sub-pestaña en la biblioteca: muestra todos los videos.
  ///
  /// In es, this message translates to:
  /// **'Todo'**
  String get libraryTabAll;

  /// Chip de sub-pestaña en la biblioteca: vista agrupada por carpeta.
  ///
  /// In es, this message translates to:
  /// **'Carpetas'**
  String get libraryTabFolders;

  /// Chip de sub-pestaña en la biblioteca: pestaña de listas de reproducción.
  ///
  /// In es, this message translates to:
  /// **'Listas'**
  String get libraryTabPlaylists;

  /// Etiqueta/semántica del chip de filtro «solo no vistos» en la biblioteca y en los resultados de búsqueda.
  ///
  /// In es, this message translates to:
  /// **'No vistos'**
  String get libraryUnwatchedFilter;

  /// Texto de ayuda del campo de búsqueda cuando la sub-pestaña Listas está activa.
  ///
  /// In es, this message translates to:
  /// **'Buscar listas'**
  String get librarySearchHintPlaylists;

  /// Texto de ayuda del campo de búsqueda en las sub-pestañas Todo/Carpetas.
  ///
  /// In es, this message translates to:
  /// **'Buscar videos o carpetas'**
  String get librarySearchHintVideos;

  /// Tooltip del icono de cerrar (X) que sale del modo búsqueda de la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'Cerrar búsqueda'**
  String get librarySearchClose;

  /// Tooltip del icono que abre la búsqueda de la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get librarySearchTooltip;

  /// Tooltip del icono de densidad de cuadrícula: nombra el número de columnas al que cambiará al tocarlo.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{Ver en 1 columna} other{Ver en {count} columnas}}'**
  String libraryDensityTooltip(int count);

  /// Acción de abrir un video directamente con el selector de archivos del sistema (tooltip de la AppBar y botones de los estados vacíos de la biblioteca).
  ///
  /// In es, this message translates to:
  /// **'Abrir archivo'**
  String get libraryOpenFile;

  /// Tooltip del icono de orden, compartido por el menú de orden de videos y el de listas.
  ///
  /// In es, this message translates to:
  /// **'Ordenar'**
  String get librarySortTooltip;

  /// Opción de orden: más nuevo primero (compartida por los menús de orden de videos y de listas).
  ///
  /// In es, this message translates to:
  /// **'Más reciente'**
  String get librarySortRecent;

  /// Opción de orden: alfabético ascendente (compartida por los menús de orden de videos y de listas).
  ///
  /// In es, this message translates to:
  /// **'Nombre A-Z'**
  String get librarySortNameAsc;

  /// Opción de orden: alfabético descendente (compartida por los menús de orden de videos y de listas).
  ///
  /// In es, this message translates to:
  /// **'Nombre Z-A'**
  String get librarySortNameDesc;

  /// Opción de orden de videos: duración más larga primero.
  ///
  /// In es, this message translates to:
  /// **'Duración: más larga'**
  String get librarySortDurationDesc;

  /// Opción de orden de videos: duración más corta primero.
  ///
  /// In es, this message translates to:
  /// **'Duración: más corta'**
  String get librarySortDurationAsc;

  /// Opción de orden de videos: tamaño de archivo más grande primero.
  ///
  /// In es, this message translates to:
  /// **'Tamaño: más pesado'**
  String get librarySortSizeDesc;

  /// Opción de orden de videos: tamaño de archivo más chico primero.
  ///
  /// In es, this message translates to:
  /// **'Tamaño: más liviano'**
  String get librarySortSizeAsc;

  /// Opción de orden de listas: las que tienen más videos primero.
  ///
  /// In es, this message translates to:
  /// **'Más videos primero'**
  String get playlistSortMostVideos;

  /// Opción de orden de listas: la reproducida más recientemente primero.
  ///
  /// In es, this message translates to:
  /// **'Última reproducida'**
  String get playlistSortLastPlayed;

  /// Estado vacío cuando una búsqueda en la biblioteca no encuentra videos.
  ///
  /// In es, this message translates to:
  /// **'No se encontraron videos para \"{query}\"'**
  String libraryNoSearchResults(String query);

  /// Botón que borra la búsqueda actual y la cierra (estados vacíos de búsqueda de videos y de listas).
  ///
  /// In es, this message translates to:
  /// **'Borrar búsqueda'**
  String get librarySearchClearAction;

  /// Título del estado vacío cuando el filtro «no vistos» oculta todos los videos.
  ///
  /// In es, this message translates to:
  /// **'Ya viste todo'**
  String get libraryEmptyAllWatchedTitle;

  /// Subtítulo del estado vacío cuando el filtro «no vistos» oculta todos los videos.
  ///
  /// In es, this message translates to:
  /// **'No queda ningún video sin ver.'**
  String get libraryEmptyAllWatchedSubtitle;

  /// Botón que desactiva el filtro «solo no vistos».
  ///
  /// In es, this message translates to:
  /// **'Quitar filtro'**
  String get libraryEmptyRemoveFilterAction;

  /// Título del estado vacío cuando Android concedió acceso parcial a los medios.
  ///
  /// In es, this message translates to:
  /// **'Kivo solo ve los videos que elegiste'**
  String get libraryEmptyLimitedAccessTitle;

  /// Subtítulo del estado vacío cuando Android concedió acceso parcial a los medios.
  ///
  /// In es, this message translates to:
  /// **'Amplía la selección para ver el resto de tu galería.'**
  String get libraryEmptyLimitedAccessSubtitle;

  /// Botón que vuelve a abrir el selector de acceso a medios del sistema.
  ///
  /// In es, this message translates to:
  /// **'Elegir más videos'**
  String get libraryEmptyChooseMoreAction;

  /// Título del estado vacío cuando el dispositivo no tiene ningún video.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay videos'**
  String get libraryEmptyNoVideosTitle;

  /// Subtítulo del estado vacío cuando el dispositivo no tiene ningún video.
  ///
  /// In es, this message translates to:
  /// **'Cuando grabes o descargues uno aparecerá aquí.'**
  String get libraryEmptyNoVideosSubtitle;

  /// Botón que vuelve a escanear el dispositivo en busca de videos nuevos.
  ///
  /// In es, this message translates to:
  /// **'Volver a buscar'**
  String get libraryEmptyRescanAction;

  /// Texto mostrado cuando Kivo todavía no tiene permiso de acceso a los medios.
  ///
  /// In es, this message translates to:
  /// **'Da acceso a tus videos para verlos aquí'**
  String get libraryAccessPromptTitle;

  /// Botón que solicita el permiso de biblioteca de medios; también la acción de aceptar del diálogo de «acceso a todos los archivos».
  ///
  /// In es, this message translates to:
  /// **'Dar acceso'**
  String get libraryAccessPromptAction;

  /// Título del estado vacío de una carpeta sin videos.
  ///
  /// In es, this message translates to:
  /// **'Esta carpeta quedó vacía'**
  String get folderEmptyTitle;

  /// Subtítulo del estado vacío de una carpeta sin videos, nombrando la carpeta.
  ///
  /// In es, this message translates to:
  /// **'Ya no queda ningún video en «{folder}».'**
  String folderEmptySubtitle(String folder);

  /// Botón genérico de volver atrás, por ejemplo al salir de una carpeta que quedó vacía.
  ///
  /// In es, this message translates to:
  /// **'Volver'**
  String get commonGoBack;

  /// Etiqueta de la pestaña inferior de la biblioteca.
  ///
  /// In es, this message translates to:
  /// **'Videos'**
  String get homeTabVideos;

  /// Etiqueta de la pestaña inferior de ajustes.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get homeTabSettings;

  /// Insignia pequeña sobre la miniatura de un video que nunca se reprodujo.
  ///
  /// In es, this message translates to:
  /// **'Nuevo'**
  String get videoTileNewBadge;

  /// Título de la tira horizontal de videos con reanudación pendiente, en la parte superior de la pestaña Todo.
  ///
  /// In es, this message translates to:
  /// **'Continuar viendo'**
  String get continueRowTitle;

  /// Acción de compartir, en la hoja de opciones de un video y en la barra de selección múltiple.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get commonShare;

  /// Etiqueta/título genérico de la acción de renombrar (hoja de opciones de video, acción de deslizar en una lista, título del diálogo de renombrar).
  ///
  /// In es, this message translates to:
  /// **'Renombrar'**
  String get commonRename;

  /// Fila «Detalles» en la hoja de opciones del video, reutilizada como título de la hoja de detalles.
  ///
  /// In es, this message translates to:
  /// **'Detalles'**
  String get videoSheetDetails;

  /// Fila de la hoja de opciones mostrada para un video ya visto.
  ///
  /// In es, this message translates to:
  /// **'Marcar como no visto'**
  String get videoSheetMarkUnwatched;

  /// Fila de la hoja de opciones mostrada para un video no visto.
  ///
  /// In es, this message translates to:
  /// **'Marcar como visto'**
  String get videoSheetMarkWatched;

  /// Fila de la hoja de opciones que borra la posición de reanudación de un video.
  ///
  /// In es, this message translates to:
  /// **'Quitar de Continuar viendo'**
  String get videoSheetClearResume;

  /// Snackbar que confirma que se borró la posición de reanudación.
  ///
  /// In es, this message translates to:
  /// **'Quitado de Continuar viendo'**
  String get videoSheetResumeCleared;

  /// Etiqueta de la acción «añadir a lista», y título de la propia hoja de añadir a lista.
  ///
  /// In es, this message translates to:
  /// **'Añadir a lista'**
  String get playlistAddToListLabel;

  /// Fila de la hoja de opciones que mueve un video al Vault.
  ///
  /// In es, this message translates to:
  /// **'Mover al Vault'**
  String get videoSheetMoveToVault;

  /// Acción corta y genérica de borrar, reutilizada en confirmaciones de borrado y acciones de deslizar.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get commonDelete;

  /// Título del diálogo, mostrado una sola vez, que ofrece dar acceso a todos los archivos.
  ///
  /// In es, this message translates to:
  /// **'Sin confirmaciones de Android'**
  String get allFilesAccessDialogTitle;

  /// Cuerpo del diálogo que ofrece dar acceso a todos los archivos.
  ///
  /// In es, this message translates to:
  /// **'Para borrar y renombrar sin que Android te pida confirmación cada vez, dale a Kivo acceso a los archivos.'**
  String get allFilesAccessDialogBody;

  /// Botón para rechazar el diálogo de acceso a todos los archivos.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get commonNotNow;

  /// Snackbar mostrado tras marcar un video como visto.
  ///
  /// In es, this message translates to:
  /// **'Marcado como visto'**
  String get videoSheetMarkedWatched;

  /// Snackbar mostrado tras marcar un video como no visto.
  ///
  /// In es, this message translates to:
  /// **'Marcado como no visto'**
  String get videoSheetMarkedUnwatched;

  /// Título/texto del botón de confirmar para mover uno o varios videos a la papelera del sistema (Android 11+).
  ///
  /// In es, this message translates to:
  /// **'Mover a la papelera'**
  String get trashMoveTitle;

  /// Título del diálogo de confirmación de borrado cuando el dispositivo no tiene papelera (borrado permanente).
  ///
  /// In es, this message translates to:
  /// **'Borrar video'**
  String get videoSheetDeleteTitle;

  /// Cuerpo del diálogo de confirmación al mover un video a la papelera.
  ///
  /// In es, this message translates to:
  /// **'¿Mover «{name}» a la papelera? Podrás recuperarlo durante 30 días desde la papelera del teléfono.'**
  String videoSheetTrashConfirmBody(String name);

  /// Cuerpo del diálogo de confirmación al borrar un video permanentemente.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar «{name}»? Esta acción no se puede deshacer.'**
  String videoSheetDeleteConfirmBody(String name);

  /// Botón genérico de cancelar en diálogos.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// Snackbar mostrado tras borrar un video.
  ///
  /// In es, this message translates to:
  /// **'Video borrado'**
  String get videoSheetDeletedSnackbar;

  /// Etiqueta de campo en la hoja de detalles del video y en el campo de texto del diálogo de renombrar.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get detailsLabelName;

  /// Etiqueta de fila en la hoja de detalles del video.
  ///
  /// In es, this message translates to:
  /// **'Carpeta'**
  String get detailsLabelFolder;

  /// Etiqueta de fila en la hoja de detalles del video.
  ///
  /// In es, this message translates to:
  /// **'Tamaño'**
  String get detailsLabelSize;

  /// Etiqueta de fila en la hoja de detalles del video.
  ///
  /// In es, this message translates to:
  /// **'Duración'**
  String get detailsLabelDuration;

  /// Etiqueta de fila en la hoja de detalles del video.
  ///
  /// In es, this message translates to:
  /// **'Resolución'**
  String get detailsLabelResolution;

  /// Etiqueta de fila en la hoja de detalles del video (fecha de alta).
  ///
  /// In es, this message translates to:
  /// **'Agregado'**
  String get detailsLabelAdded;

  /// Etiqueta de fila en la hoja de detalles del video. Sigla técnica, igual en ambos idiomas.
  ///
  /// In es, this message translates to:
  /// **'URI'**
  String get detailsLabelUri;

  /// Botón genérico de guardar en diálogos de renombrar/editar.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get commonSave;

  /// Título de la AppBar de selección: cantidad de videos seleccionados actualmente.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} seleccionado} other{{count} seleccionados}}'**
  String selectionCountLabel(int count);

  /// Tooltip del icono «seleccionar todo» en la AppBar de selección.
  ///
  /// In es, this message translates to:
  /// **'Seleccionar todo'**
  String get selectionSelectAll;

  /// Acción de la barra de selección múltiple: mover los videos seleccionados al Vault.
  ///
  /// In es, this message translates to:
  /// **'Al Vault'**
  String get selectionMoveToVault;

  /// Acción de la barra de selección múltiple: añadir los videos seleccionados a una lista.
  ///
  /// In es, this message translates to:
  /// **'A una lista'**
  String get selectionAddToList;

  /// Título del diálogo de confirmación de borrado múltiple cuando el dispositivo no tiene papelera.
  ///
  /// In es, this message translates to:
  /// **'Borrar videos'**
  String get selectionDeleteTitle;

  /// Cuerpo del diálogo de confirmación al mover varios videos seleccionados a la papelera.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{¿Mover 1 video a la papelera?\n\nPodrás recuperarlos durante 30 días desde la papelera del teléfono.} other{¿Mover {count} videos a la papelera?\n\nPodrás recuperarlos durante 30 días desde la papelera del teléfono.}}'**
  String selectionTrashConfirmBody(int count);

  /// Cuerpo del diálogo de confirmación al borrar varios videos seleccionados permanentemente.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{¿Borrar 1 video? Esta acción no se puede deshacer.} other{¿Borrar {count} videos? Esta acción no se puede deshacer.}}'**
  String selectionDeleteConfirmBody(int count);

  /// Snackbar mostrado tras mover los videos seleccionados a la papelera.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 video movido a la papelera} other{{count} videos movidos a la papelera}}'**
  String selectionTrashedSnackbar(int count);

  /// Snackbar mostrado tras borrar los videos seleccionados permanentemente.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 video borrado} other{{count} videos borrados}}'**
  String selectionDeletedSnackbar(int count);

  /// Título del estado vacío de la pestaña Carpetas.
  ///
  /// In es, this message translates to:
  /// **'No hay carpetas'**
  String get foldersEmptyTitle;

  /// Subtítulo del estado vacío de la pestaña Carpetas.
  ///
  /// In es, this message translates to:
  /// **'Tus videos aparecerán aquí agrupados por carpeta.'**
  String get foldersEmptySubtitle;

  /// Píldora pequeña en una tarjeta de carpeta con la cantidad de videos que contiene.
  ///
  /// In es, this message translates to:
  /// **'{count} vids'**
  String folderCardVideoCount(int count);

  /// Fila de la hoja de opciones al mantener presionada una carpeta.
  ///
  /// In es, this message translates to:
  /// **'Ocultar de la biblioteca'**
  String get folderHideTitle;

  /// Subtítulo aclaratorio de la fila «Ocultar de la biblioteca».
  ///
  /// In es, this message translates to:
  /// **'No se borra ni se mueve nada: solo deja de aparecer en Kivo.'**
  String get folderHideSubtitle;

  /// Snackbar mostrado tras ocultar una carpeta, nombrándola.
  ///
  /// In es, this message translates to:
  /// **'{folder} oculta'**
  String folderHiddenSnackbar(String folder);

  /// Acción genérica de deshacer en un SnackBarAction.
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get commonUndo;

  /// Título del estado vacío de la pestaña Listas cuando no existe ninguna.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tienes listas'**
  String get playlistsEmptyTitle;

  /// Subtítulo del estado vacío de la pestaña Listas cuando no existe ninguna.
  ///
  /// In es, this message translates to:
  /// **'Una lista es un orden que tú eliges: crea una y añade videos desde la selección o desde el menú de un video.'**
  String get playlistsEmptySubtitle;

  /// Etiqueta/título para crear una lista nueva (botón del estado vacío, título del diálogo de crear, botón flotante, fila de la hoja de añadir a lista).
  ///
  /// In es, this message translates to:
  /// **'Nueva lista'**
  String get playlistNewListLabel;

  /// Estado vacío cuando una búsqueda entre las listas no encuentra ninguna.
  ///
  /// In es, this message translates to:
  /// **'Ninguna lista coincide con \"{query}\"'**
  String playlistsNoSearchResults(String query);

  /// Botón genérico de confirmar creación en diálogos de crear lista.
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get commonCreate;

  /// Etiqueta de la barra de selección múltiple de listas: cantidad marcada.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 lista seleccionada} other{{count} listas seleccionadas}}'**
  String playlistsSelectedCount(int count);

  /// Título del diálogo de confirmación al borrar varias listas marcadas.
  ///
  /// In es, this message translates to:
  /// **'Borrar listas'**
  String get playlistsBulkDeleteTitle;

  /// Cuerpo del diálogo de confirmación al borrar varias listas marcadas.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{¿Borrar 1 lista? Esta acción no se puede deshacer. Los videos no se borran, solo las listas.} other{¿Borrar {count} listas? Esta acción no se puede deshacer. Los videos no se borran, solo las listas.}}'**
  String playlistsBulkDeleteBody(int count);

  /// Título del diálogo/menú para renombrar una lista (menú de la pantalla de lista y diálogo de renombrar de la pestaña Listas).
  ///
  /// In es, this message translates to:
  /// **'Renombrar lista'**
  String get playlistRenameTitle;

  /// Cantidad de videos mostrada en una fila de lista de reproducción.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{1 video} other{{count} videos}}'**
  String playlistRowVideoCount(int count);

  /// Se añade al conteo de videos de una fila de lista cuando algunas de sus entradas ya no se encuentran.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} no disponible} other{{count} no disponibles}}'**
  String playlistRowMissingCount(int count);

  /// Mensaje mostrado en la hoja de añadir a lista cuando no existe ninguna lista.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tienes listas. Crea una para empezar.'**
  String get playlistAddSheetEmpty;

  /// Snackbar mostrado tras añadir video(s) a una lista, nombrándola.
  ///
  /// In es, this message translates to:
  /// **'Añadido a «{name}»'**
  String playlistAddedSnackbar(String name);

  /// Etiqueta del botón flotante que reproduce toda la lista.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get playlistPlayLabel;

  /// Título del estado vacío de una lista sin videos.
  ///
  /// In es, this message translates to:
  /// **'Esta lista está vacía'**
  String get playlistEmptyTitle;

  /// Subtítulo del estado vacío de una lista sin videos.
  ///
  /// In es, this message translates to:
  /// **'Añade videos desde la selección o desde el menú de un video, con «Añadir a lista».'**
  String get playlistEmptySubtitle;

  /// Tooltip del botón que quita una entrada de la lista (fila disponible y fila no disponible).
  ///
  /// In es, this message translates to:
  /// **'Quitar de la lista'**
  String get playlistRemoveEntryTooltip;

  /// Snackbar mostrado tras quitar una entrada de la lista, nombrándola.
  ///
  /// In es, this message translates to:
  /// **'«{name}» quitado de la lista'**
  String playlistEntryRemovedSnackbar(String name);

  /// Snackbar mostrado al intentar reproducir una lista sin ninguna entrada disponible.
  ///
  /// In es, this message translates to:
  /// **'Nada disponible para reproducir ahora mismo'**
  String get playlistNothingToPlaySnackbar;

  /// Título del menú/diálogo para borrar una sola lista (distinto del borrado múltiple).
  ///
  /// In es, this message translates to:
  /// **'Borrar lista'**
  String get playlistDeleteTitle;

  /// Cuerpo del diálogo de confirmación al borrar una sola lista, nombrándola.
  ///
  /// In es, this message translates to:
  /// **'¿Borrar «{name}»? Esta acción no se puede deshacer. Los videos no se borran, solo la lista.'**
  String playlistDeleteConfirmBody(String name);

  /// Etiqueta mostrada en una fila de lista cuyo video original ya no se encuentra.
  ///
  /// In es, this message translates to:
  /// **'No disponible'**
  String get playlistEntryUnavailable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
