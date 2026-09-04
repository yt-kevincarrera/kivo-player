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

  /// Eyebrow del corner card de autoplay que anuncia el siguiente video pendiente.
  ///
  /// In es, this message translates to:
  /// **'PRÓXIMO'**
  String get playerAutoplayNextLabel;

  /// Botón del corner card de autoplay que confirma el avance inmediato al siguiente video.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get playerAutoplayPlayAction;

  /// Título de la hoja de marcadores, reutilizado como título de la fila «Marcadores» en el menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Marcadores'**
  String get playerBookmarksTitle;

  /// Estado vacío de la hoja de marcadores cuando el video no tiene ninguno.
  ///
  /// In es, this message translates to:
  /// **'Todavía no marcaste nada en este video.'**
  String get playerBookmarksEmpty;

  /// Título del diálogo para nombrar o renombrar un marcador.
  ///
  /// In es, this message translates to:
  /// **'Nombrar marcador'**
  String get playerBookmarksRenameDialogTitle;

  /// Snackbar al borrar un marcador sin nombre; {time} ya viene formateado por fmtDuration.
  ///
  /// In es, this message translates to:
  /// **'Marcador borrado · {time}'**
  String playerBookmarksDeletedUnnamedSnackbar(String time);

  /// Snackbar al borrar un marcador con nombre, nombrándolo.
  ///
  /// In es, this message translates to:
  /// **'«{name}» borrado'**
  String playerBookmarksDeletedNamedSnackbar(String name);

  /// Título de la hoja de capítulos, reutilizado como título de la fila «Capítulos» en el menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Capítulos'**
  String get playerChaptersTitle;

  /// Estado vacío de la hoja de capítulos cuando el video no tiene ninguno.
  ///
  /// In es, this message translates to:
  /// **'Este video no tiene capítulos.'**
  String get playerChaptersEmpty;

  /// Botón que salta al capítulo anterior, en la hoja de capítulos.
  ///
  /// In es, this message translates to:
  /// **'Anterior'**
  String get playerChaptersPrevious;

  /// Botón que salta al siguiente capítulo, en la hoja de capítulos.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get playerChaptersNext;

  /// Tooltip del botón de velocidad en la barra inferior del reproductor, reutilizado como rótulo en el tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Velocidad'**
  String get playerSpeedTooltip;

  /// Tooltip del botón que bloquea la pantalla, en la barra inferior del reproductor.
  ///
  /// In es, this message translates to:
  /// **'Bloquear pantalla'**
  String get playerLockScreenTooltip;

  /// Tooltip del botón de relación de aspecto en la barra inferior, reutilizado como rótulo en el tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Relación de aspecto'**
  String get playerAspectRatioTooltip;

  /// Tooltip del botón de rotar en la barra inferior, reutilizado como rótulo en el tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Rotar'**
  String get playerRotateTooltip;

  /// Tooltip del botón central de avance rápido, nombrando los segundos configurados.
  ///
  /// In es, this message translates to:
  /// **'Avanzar {seconds}s'**
  String playerSkipForwardTooltip(int seconds);

  /// Tooltip del botón central de retroceso rápido, nombrando los segundos configurados.
  ///
  /// In es, this message translates to:
  /// **'Retroceder {seconds}s'**
  String playerSkipBackTooltip(int seconds);

  /// Tooltip del botón central de reproducir/pausar cuando el video está reproduciéndose.
  ///
  /// In es, this message translates to:
  /// **'Pausar'**
  String get playerPauseTooltip;

  /// Tooltip del botón central de reproducir/pausar cuando el video está pausado.
  ///
  /// In es, this message translates to:
  /// **'Reproducir'**
  String get playerPlayTooltip;

  /// Instrucción bajo el candado de la pantalla bloqueada del reproductor.
  ///
  /// In es, this message translates to:
  /// **'mantén para desbloquear'**
  String get playerHoldToUnlockHint;

  /// Toast que confirma que el video se reanudó desde una posición guardada; {pos} ya viene formateado por fmtDuration.
  ///
  /// In es, this message translates to:
  /// **'Reanudado desde {pos}'**
  String playerResumeUndoneMessage(String pos);

  /// Botón del toast de reanudación que reinicia el video desde el principio.
  ///
  /// In es, this message translates to:
  /// **'Reiniciar'**
  String get playerResumeRestartAction;

  /// Pregunta del prompt de reanudación; {pos} ya viene formateado por fmtDuration.
  ///
  /// In es, this message translates to:
  /// **'¿Reanudar desde {pos}?'**
  String playerResumeAskMessage(String pos);

  /// Botón del prompt de reanudación que empieza el video desde el principio.
  ///
  /// In es, this message translates to:
  /// **'Desde el inicio'**
  String get playerResumeFromStartAction;

  /// Botón del prompt de reanudación que continúa desde la posición guardada.
  ///
  /// In es, this message translates to:
  /// **'Reanudar'**
  String get playerResumeAction;

  /// Tooltip del botón de volver, en la barra superior del reproductor.
  ///
  /// In es, this message translates to:
  /// **'Atrás'**
  String get playerBackTooltip;

  /// Tooltip del botón de información cuando la superposición está visible.
  ///
  /// In es, this message translates to:
  /// **'Ocultar información en pantalla'**
  String get playerInfoOverlayHideTooltip;

  /// Tooltip del botón de información cuando la superposición está oculta.
  ///
  /// In es, this message translates to:
  /// **'Mostrar información en pantalla'**
  String get playerInfoOverlayShowTooltip;

  /// Tooltip del botón de subtítulos en la barra superior, reutilizado como título de la hoja de subtítulos y como rótulo en el tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Subtítulos'**
  String get playerSubtitlesTooltip;

  /// Tooltip del botón de imagen en imagen, reutilizado como rótulo en el tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Imagen en imagen'**
  String get playerPipTooltip;

  /// Tooltip del botón de audio en la barra superior, reutilizado como título de la hoja de pistas de audio.
  ///
  /// In es, this message translates to:
  /// **'Audio'**
  String get playerAudioTooltip;

  /// Tooltip del botón que abre el menú ⋮, en la barra superior del reproductor.
  ///
  /// In es, this message translates to:
  /// **'Más opciones'**
  String get playerMoreOptionsTooltip;

  /// Texto de la píldora de bucle A-B mientras espera que se marque el punto A.
  ///
  /// In es, this message translates to:
  /// **'Marcar A'**
  String get playerLoopMarkA;

  /// Texto de la píldora de bucle A-B mientras espera que se marque el punto B.
  ///
  /// In es, this message translates to:
  /// **'Marcar B'**
  String get playerLoopMarkB;

  /// Recordatorio del punto A ya marcado, junto a la píldora, mientras se espera el punto B; {time} ya viene formateado por fmtDuration.
  ///
  /// In es, this message translates to:
  /// **'A {time}'**
  String playerLoopPointALabel(String time);

  /// Subtítulo de la fila «Bucle A-B» del menú ⋮ cuando no hay bucle marcado.
  ///
  /// In es, this message translates to:
  /// **'Repetir un fragmento del video'**
  String get playerLoopSubtitleIdle;

  /// Subtítulo de la fila «Bucle A-B» del menú ⋮ mientras se está marcando el punto A o B.
  ///
  /// In es, this message translates to:
  /// **'Marcando…'**
  String get playerLoopSubtitleMarking;

  /// Subtítulo de la fila «Bucle A-B» del menú ⋮ con el bucle activo; {range} ya viene formateado por fmtDuration.
  ///
  /// In es, this message translates to:
  /// **'Activo · {range}'**
  String playerLoopSubtitleActive(String range);

  /// Subtítulo de la fila «Capítulos» del menú ⋮ con la cantidad de capítulos del video.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Sin capítulos} =1{1 capítulo} other{{count} capítulos}}'**
  String playerMenuChaptersSubtitle(int count);

  /// Insignia de la tile «Temporizador» del menú ⋮ cuando el temporizador está en modo «al terminar el episodio».
  ///
  /// In es, this message translates to:
  /// **'Al terminar'**
  String get playerMenuSleepBadgeEpisode;

  /// Insignia de la tile «Temporizador» del menú ⋮ cuando el temporizador cuenta episodios restantes.
  ///
  /// In es, this message translates to:
  /// **'{count} ep'**
  String playerMenuSleepBadgeEpisodes(int count);

  /// Tile del menú ⋮ que guarda un marcador en la posición actual.
  ///
  /// In es, this message translates to:
  /// **'Marcar aquí'**
  String get playerMenuMarkHere;

  /// Tile del menú ⋮ que captura el fotograma actual.
  ///
  /// In es, this message translates to:
  /// **'Capturar'**
  String get playerMenuCapture;

  /// Tile del menú ⋮ que abre el panel del temporizador de apagado.
  ///
  /// In es, this message translates to:
  /// **'Temporizador'**
  String get playerMenuSleepTimer;

  /// Tile del menú ⋮ que abre el panel de sincronía de audio/subtítulos.
  ///
  /// In es, this message translates to:
  /// **'Sincronizar'**
  String get playerMenuSync;

  /// Título del grupo de filas Repetir/Aleatorio/Bucle A-B en el menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Reproducción'**
  String get playerMenuGroupPlayback;

  /// Fila del menú ⋮ con el selector de modo de repetición.
  ///
  /// In es, this message translates to:
  /// **'Repetir'**
  String get playerMenuRepeat;

  /// Segmento «apagado» de los selectores Repetir/Aleatorio del menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'No'**
  String get playerMenuOptionOff;

  /// Segmento del selector de Repetir: repetir toda la lista/cola.
  ///
  /// In es, this message translates to:
  /// **'Lista'**
  String get playerMenuRepeatList;

  /// Segmento del selector de Repetir: repetir solo el video actual.
  ///
  /// In es, this message translates to:
  /// **'Video'**
  String get playerMenuRepeatVideoOption;

  /// Fila del menú ⋮ con el selector de orden aleatorio.
  ///
  /// In es, this message translates to:
  /// **'Aleatorio'**
  String get playerMenuShuffle;

  /// Segmento «encendido» del selector Aleatorio del menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Sí'**
  String get playerMenuOptionOn;

  /// Fila del menú ⋮ que arma o cancela el bucle A-B.
  ///
  /// In es, this message translates to:
  /// **'Bucle A-B'**
  String get playerMenuAbLoop;

  /// Título del grupo de filas Capítulos/Marcadores en el menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Ir a'**
  String get playerMenuGroupGoTo;

  /// Subtítulo de la fila «Marcadores» del menú ⋮ con la cantidad de marcadores del video.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =0{Sin marcadores} =1{1 marcador} other{{count} marcadores}}'**
  String playerMenuBookmarksSubtitle(int count);

  /// Título del grupo de la fila Ecualizador en el menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Audio'**
  String get playerMenuGroupAudio;

  /// Fila del menú ⋮ que abre el ecualizador.
  ///
  /// In es, this message translates to:
  /// **'Ecualizador'**
  String get playerMenuEqualizer;

  /// Snackbar tras guardar un marcador con «Marcar aquí»; {time} ya viene formateado por fmtDuration.
  ///
  /// In es, this message translates to:
  /// **'Marcador guardado · {time}'**
  String playerMenuBookmarkSavedSnackbar(String time);

  /// Acción del snackbar de marcador guardado que abre el diálogo para nombrarlo.
  ///
  /// In es, this message translates to:
  /// **'Nombrar'**
  String get playerMenuBookmarkNameAction;

  /// Snackbar mostrado tras capturar un fotograma con éxito.
  ///
  /// In es, this message translates to:
  /// **'Captura guardada'**
  String get playerMenuCaptureSavedSnackbar;

  /// Acción del snackbar de captura guardada que abre la imagen.
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get playerMenuCaptureViewAction;

  /// Insignia sobre la miniatura del video actual, en la tira de la cola.
  ///
  /// In es, this message translates to:
  /// **'AHORA'**
  String get playerQueueNowBadge;

  /// Título del panel del temporizador de apagado.
  ///
  /// In es, this message translates to:
  /// **'Temporizador de apagado'**
  String get playerSleepPanelTitle;

  /// Eyebrow sobre el selector de minutos, en el panel del temporizador.
  ///
  /// In es, this message translates to:
  /// **'Duración'**
  String get playerSleepDurationLabel;

  /// Valor del selector de minutos, en el panel del temporizador.
  ///
  /// In es, this message translates to:
  /// **'{minutes} min'**
  String playerSleepMinutesValue(int minutes);

  /// Eyebrow entre el selector de minutos y las tarjetas de episodio, en el panel del temporizador.
  ///
  /// In es, this message translates to:
  /// **'O bien'**
  String get playerSleepOrLabel;

  /// Botón principal del panel del temporizador cuando se eligió «tras N episodios».
  ///
  /// In es, this message translates to:
  /// **'Iniciar · Tras {count} episodios'**
  String playerSleepStartAfterEpisodes(int count);

  /// Botón principal del panel del temporizador cuando se eligió «al terminar el episodio».
  ///
  /// In es, this message translates to:
  /// **'Iniciar · Al terminar el episodio'**
  String get playerSleepStartAtEpisodeEnd;

  /// Botón principal del panel del temporizador cuando se eligió una duración fija.
  ///
  /// In es, this message translates to:
  /// **'Iniciar · {minutes} min'**
  String playerSleepStartFixedMinutes(int minutes);

  /// Subtítulo bajo el tiempo restante, en el panel del temporizador con duración fija activa.
  ///
  /// In es, this message translates to:
  /// **'restante · de {minutes} min'**
  String playerSleepRemainingOfMinutes(int minutes);

  /// Subtítulo bajo el contador de episodios, en el panel del temporizador con modo episodios activo. El número ya se muestra por separado arriba.
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{episodio restante} other{episodios restantes}}'**
  String playerSleepEpisodesRemaining(int count);

  /// Subtítulo bajo el tiempo restante, en el panel del temporizador con modo «al terminar el episodio» activo.
  ///
  /// In es, this message translates to:
  /// **'hasta el final del episodio'**
  String get playerSleepUntilEpisodeEnd;

  /// Botón que cancela el temporizador de apagado activo, en el panel del temporizador y en el toast de aviso.
  ///
  /// In es, this message translates to:
  /// **'Desactivar'**
  String get playerSleepDeactivate;

  /// Botón que extiende el temporizador de apagado activo en su misma duración, en el panel del temporizador.
  ///
  /// In es, this message translates to:
  /// **'Extender +{minutes}'**
  String playerSleepExtendByMinutes(int minutes);

  /// Título de la tarjeta que arma el temporizador para detenerse al terminar el episodio.
  ///
  /// In es, this message translates to:
  /// **'Al terminar el episodio'**
  String get playerSleepEpisodeCardTitle;

  /// Subtítulo aclaratorio de la tarjeta «Al terminar el episodio».
  ///
  /// In es, this message translates to:
  /// **'Se detiene cuando termine este video'**
  String get playerSleepEpisodeCardSubtitle;

  /// Título de la tarjeta que arma el temporizador para detenerse tras una cantidad de episodios elegida con los botones −/+ de la propia tarjeta.
  ///
  /// In es, this message translates to:
  /// **'Tras N episodios'**
  String get playerSleepEpisodesCardTitle;

  /// Subtítulo aclaratorio de la tarjeta «Tras N episodios».
  ///
  /// In es, this message translates to:
  /// **'Deja correr el autoplay y detiene'**
  String get playerSleepEpisodesCardSubtitle;

  /// Prefijo del toast de aviso del temporizador, seguido del tiempo restante con su propio estilo (texto enriquecido, no interpolado). Conserva el espacio final.
  ///
  /// In es, this message translates to:
  /// **'Pausando en '**
  String get playerSleepPausingInLabel;

  /// Botón del toast de aviso del temporizador que lo extiende en su misma duración.
  ///
  /// In es, this message translates to:
  /// **'Extender'**
  String get playerSleepExtendAction;

  /// Botón del panel de velocidad que guarda la velocidad actual como preset nuevo; {rate} ya viene formateado (dos decimales redondeados).
  ///
  /// In es, this message translates to:
  /// **'Guardar {rate}x'**
  String playerSpeedSavePreset(String rate);

  /// Botón del panel de velocidad que vuelve la velocidad a 1x.
  ///
  /// In es, this message translates to:
  /// **'Restablecer (1x)'**
  String get playerSpeedResetAction;

  /// Nombre del modo de aspecto «ajustar al recuadro», mostrado en el flash al cambiar de modo.
  ///
  /// In es, this message translates to:
  /// **'Ajustar'**
  String get playerAspectFit;

  /// Nombre del modo de aspecto «llenar la pantalla», mostrado en el flash al cambiar de modo.
  ///
  /// In es, this message translates to:
  /// **'Llenar'**
  String get playerAspectFill;

  /// Nombre del modo de aspecto «estirar», mostrado en el flash al cambiar de modo.
  ///
  /// In es, this message translates to:
  /// **'Estirar'**
  String get playerAspectStretch;

  /// Pestaña de la hoja de subtítulos que lista las pistas disponibles.
  ///
  /// In es, this message translates to:
  /// **'Pistas'**
  String get playerTracksTabLabel;

  /// Pestaña de la hoja de subtítulos que edita el estilo (tamaño y color).
  ///
  /// In es, this message translates to:
  /// **'Estilo'**
  String get playerTracksStyleTabLabel;

  /// Interruptor que activa o desactiva los subtítulos, en la hoja de subtítulos.
  ///
  /// In es, this message translates to:
  /// **'Mostrar subtítulos'**
  String get playerTracksShowSubtitles;

  /// Eyebrow de la sección con las pistas incrustadas en el archivo, en la hoja de pistas.
  ///
  /// In es, this message translates to:
  /// **'En el video'**
  String get playerTracksSectionInVideo;

  /// Subtítulo de una pista incrustada marcada como predeterminada por el archivo.
  ///
  /// In es, this message translates to:
  /// **'Pista incrustada · predeterminada'**
  String get playerTracksEmbeddedDefault;

  /// Subtítulo de una pista incrustada normal (no predeterminada).
  ///
  /// In es, this message translates to:
  /// **'Pista incrustada'**
  String get playerTracksEmbedded;

  /// Eyebrow de la sección de sincronía, en la hoja de pistas.
  ///
  /// In es, this message translates to:
  /// **'Sincronía'**
  String get playerTracksSectionSync;

  /// Tarjeta que abre el panel de sincronía, en la hoja de subtítulos.
  ///
  /// In es, this message translates to:
  /// **'Sincronizar subtítulos'**
  String get playerTracksSyncSubtitles;

  /// Tarjeta que abre el panel de sincronía, en la hoja de audio.
  ///
  /// In es, this message translates to:
  /// **'Sincronizar audio'**
  String get playerTracksSyncAudio;

  /// Subtítulo de la tarjeta de sincronía cuando no hay ningún subtítulo activo todavía.
  ///
  /// In es, this message translates to:
  /// **'Activa un subtítulo para poder ajustarlo'**
  String get playerTracksSyncNeedsSubtitle;

  /// Subtítulo de la tarjeta de sincronía cuando ya se puede ajustar el desfase.
  ///
  /// In es, this message translates to:
  /// **'Ajustar el desfase mientras se reproduce'**
  String get playerTracksSyncHint;

  /// Eyebrow de la sección con los archivos de subtítulo encontrados junto al video, en la hoja de subtítulos.
  ///
  /// In es, this message translates to:
  /// **'En la carpeta'**
  String get playerTracksSectionInFolder;

  /// Subtítulo de una pista de subtítulo encontrada como archivo junto al video.
  ///
  /// In es, this message translates to:
  /// **'Archivo local'**
  String get playerTracksLocalFile;

  /// Estado vacío de la hoja de subtítulos cuando no hay pistas incrustadas ni archivos cercanos.
  ///
  /// In es, this message translates to:
  /// **'Este video no trae subtítulos incrustados ni hay archivos junto a él.'**
  String get playerTracksNoSubtitlesFound;

  /// Estado vacío de la hoja de audio cuando el video no tiene otras pistas.
  ///
  /// In es, this message translates to:
  /// **'Este video no tiene otras pistas de audio.'**
  String get playerTracksNoOtherAudioTracks;

  /// Eyebrow de la sección con la acción de cargar un subtítulo manualmente, en la hoja de subtítulos.
  ///
  /// In es, this message translates to:
  /// **'Desde tu dispositivo'**
  String get playerTracksSectionFromDevice;

  /// Tarjeta que abre el selector de archivos para cargar un subtítulo manualmente.
  ///
  /// In es, this message translates to:
  /// **'Cargar subtítulo…'**
  String get playerTracksLoadSubtitleAction;

  /// Subtítulo de la tarjeta «Cargar subtítulo…», con los formatos aceptados.
  ///
  /// In es, this message translates to:
  /// **'Elegir un archivo .srt, .ass o .vtt'**
  String get playerTracksLoadSubtitleHint;

  /// Opción de fondo de subtítulo: sin fondo, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Transparente'**
  String get playerTracksBgTransparent;

  /// Opción de fondo de subtítulo: negro, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Negro'**
  String get playerTracksBgBlack;

  /// Opción de fondo de subtítulo: blanco, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Blanco'**
  String get playerTracksBgWhite;

  /// Frase de muestra mostrada en la vista previa en vivo del estilo de subtítulo, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Estamos cerca de encontrarlo.'**
  String get playerTracksStylePreviewSample;

  /// Eyebrow sobre el control de tamaño de fuente, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Tamaño'**
  String get playerTracksSizeLabel;

  /// Eyebrow sobre las muestras de color de texto, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Color de texto'**
  String get playerTracksTextColorLabel;

  /// Eyebrow sobre las muestras de color de fondo, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Color de fondo'**
  String get playerTracksBackgroundColorLabel;

  /// Botón que restaura el estilo de subtítulo a los valores por defecto, en la pestaña Estilo.
  ///
  /// In es, this message translates to:
  /// **'Restablecer estilo'**
  String get playerTracksResetStyleAction;

  /// Instrucción bajo la barra de arrastre del panel de sincronía de audio/subtítulos.
  ///
  /// In es, this message translates to:
  /// **'arrastra la barra o usa los botones'**
  String get playerSyncDragHint;

  /// Título de la primera página del tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Toques'**
  String get playerTutorialPageTaps;

  /// Rótulo del tutorial de gestos para el doble toque que retrocede, con los segundos configurados.
  ///
  /// In es, this message translates to:
  /// **'Doble toque · −{seconds} s'**
  String playerTutorialDoubleTapBack(int seconds);

  /// Rótulo del tutorial de gestos para el doble toque central que pausa.
  ///
  /// In es, this message translates to:
  /// **'Doble toque · Pausa'**
  String get playerTutorialDoubleTapPause;

  /// Rótulo del tutorial de gestos para el doble toque que avanza, con los segundos configurados.
  ///
  /// In es, this message translates to:
  /// **'Doble toque · +{seconds} s'**
  String playerTutorialDoubleTapForward(int seconds);

  /// Rótulo del tutorial de gestos para el toque simple que muestra u oculta los controles.
  ///
  /// In es, this message translates to:
  /// **'Un toque · Mostrar u ocultar los controles'**
  String get playerTutorialSingleTapToggleControls;

  /// Título de la segunda página del tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Arrastres'**
  String get playerTutorialPageDrags;

  /// Rótulo del tutorial de gestos para el arrastre vertical de brillo.
  ///
  /// In es, this message translates to:
  /// **'Arrastra · Brillo'**
  String get playerTutorialDragBrightness;

  /// Rótulo del tutorial de gestos para el arrastre vertical de volumen, con el máximo configurado.
  ///
  /// In es, this message translates to:
  /// **'Arrastra · Volumen (hasta {percent}%)'**
  String playerTutorialDragVolume(int percent);

  /// Rótulo del tutorial de gestos para el arrastre horizontal de búsqueda.
  ///
  /// In es, this message translates to:
  /// **'Arrastra · Buscar con vista previa'**
  String get playerTutorialDragSeekPreview;

  /// Rótulo del tutorial de gestos para el arrastre en los bordes laterales que minimiza.
  ///
  /// In es, this message translates to:
  /// **'Arrastra en el borde · Minimizar'**
  String get playerTutorialDragEdgeMinimize;

  /// Rótulo del tutorial de gestos para el arrastre central que gira la pantalla.
  ///
  /// In es, this message translates to:
  /// **'Arrastra en el centro · Girar (con los controles ocultos)'**
  String get playerTutorialDragCenterRotate;

  /// Rótulo del tutorial de gestos para el pellizco de zoom, con el máximo configurado ya formateado (p. ej. «8×»).
  ///
  /// In es, this message translates to:
  /// **'Pellizca · Zoom (hasta {zoom})'**
  String playerTutorialPinchZoom(String zoom);

  /// Rótulo del tutorial de gestos para el encuadre con zoom activo.
  ///
  /// In es, this message translates to:
  /// **'Con zoom, arrastra · Encuadrar · Toca la píldora para volver a 1×'**
  String get playerTutorialZoomPan;

  /// Rótulo del tutorial de gestos para mantener pulsado a la izquierda, con la velocidad configurada ya formateada (p. ej. «2×»).
  ///
  /// In es, this message translates to:
  /// **'Mantén pulsado a la izquierda · {speed}'**
  String playerTutorialHoldLeftSpeed(String speed);

  /// Rótulo del tutorial de gestos para mantener y deslizar a la derecha.
  ///
  /// In es, this message translates to:
  /// **'Mantén y desliza arriba o abajo a la derecha · Escalera de velocidad'**
  String get playerTutorialHoldRightLadder;

  /// Título de la tercera página del tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Botones'**
  String get playerTutorialPageButtons;

  /// Rótulo del tutorial de gestos para el botón de minimizar.
  ///
  /// In es, this message translates to:
  /// **'Minimizar a la mini-barra'**
  String get playerTutorialMinimize;

  /// Rótulo del tutorial de gestos para el botón de información en pantalla.
  ///
  /// In es, this message translates to:
  /// **'Información en pantalla'**
  String get playerTutorialInfoOverlay;

  /// Rótulo del tutorial de gestos para el botón de pistas de audio.
  ///
  /// In es, this message translates to:
  /// **'Pistas de audio'**
  String get playerTutorialAudioTracks;

  /// Rótulo del tutorial de gestos para el botón que abre el menú ⋮.
  ///
  /// In es, this message translates to:
  /// **'Más opciones · temporizador y bucle A-B'**
  String get playerTutorialMoreOptions;

  /// Rótulo del tutorial de gestos para el botón de bloquear pantalla.
  ///
  /// In es, this message translates to:
  /// **'Bloquear la pantalla'**
  String get playerTutorialLockScreen;

  /// Nota final de la página «Botones» del tutorial de gestos, sobre la tira de cola.
  ///
  /// In es, this message translates to:
  /// **'Con más de un video en la carpeta aparece la cola sobre los botones'**
  String get playerTutorialQueueHint;

  /// Botón que cierra el tutorial de gestos, en su última página.
  ///
  /// In es, this message translates to:
  /// **'Entendido'**
  String get playerTutorialDoneAction;

  /// Botón que avanza a la siguiente página del tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get playerTutorialNextAction;

  /// Título de la sección de la barra superior, en la página «Botones» del tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Barra de arriba'**
  String get playerTutorialTopBarSection;

  /// Título de la sección de la barra inferior, en la página «Botones» del tutorial de gestos.
  ///
  /// In es, this message translates to:
  /// **'Barra de abajo'**
  String get playerTutorialBottomBarSection;
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
