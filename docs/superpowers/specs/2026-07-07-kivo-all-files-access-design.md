# Kivo — Borrar/renombrar sin confirmación repetida (All-files-access)

**Fecha:** 2026-07-07
**Estado:** Aprobado para plan
**Alcance:** Eliminar el diálogo de consentimiento del sistema que aparece **cada vez** al borrar/renombrar un video (scoped storage) pidiendo `MANAGE_EXTERNAL_STORAGE` ("Acceso a todos los archivos") una sola vez; con el permiso, las operaciones se hacen en silencio. Sub-proyecto A de dos (B = multi-selección por long-press, después). Vault/ocultar = futuro, fuera de alcance.

---

## Contexto

El menú ⋮ (feature recién entregada, ver `2026-07-07-kivo-library-file-ops-design.md`) borra/renombra vía MediaStore. En Android 11+ (scoped storage), modificar un archivo que la app no creó **obliga** a un diálogo de consentimiento del sistema (`MediaStore.createDeleteRequest` / `createWriteRequest`) en **cada** operación — el usuario lo reporta como "extremadamente molesto". Ese diálogo es del SO, no de la app.

La única forma de eliminar ese nag repetido es el permiso especial **`MANAGE_EXTERNAL_STORAGE`** ("Acceso a todos los archivos"). Con él concedido, `contentResolver.delete`/`update` sobre medios de otras apps **no** dispara el consentimiento — la operación es silenciosa.

Estado actual relevante:
- Permisos en `AndroidManifest.xml`: `READ_MEDIA_VIDEO` (13+), `READ_EXTERNAL_STORAGE` (≤32). **No** hay `MANAGE_EXTERNAL_STORAGE`.
- `permission_handler: ^11.3.1` está en `pubspec.yaml` (expone `Permission.manageExternalStorage`).
- El nativo de borrar/renombrar vive en el handler del canal `kivo/media` en `MainActivity.kt` (flujo de consentimiento vía `startIntentSenderForResult` + `onActivityResult`, hecho en el sub-proyecto anterior).
- `VideoActionsController` (`lib/player/library/video_actions.dart`) orquesta delete/rename + efectos; `VideoOptionsSheet`/`showVideoOptions` (`lib/ui/home/widgets/video_options_sheet.dart`) es la UI. El borrado ya muestra un `AlertDialog` propio de confirmación.
- Toolkit de ajustes en `lib/ui/settings/widgets/setting_tiles.dart` (`SettingNavRow`, `SettingSwitch`, …); secciones en `lib/ui/settings/sections/` (la avanzada = `advanced_playback_section.dart`). `KivoSettings` usa el patrón de 6 puntos de inserción (field, ctor, defaults, copyWith param+body, toMap, fromMap) — ej. `pipAutoOnHome`.

---

## 1. Permiso: interfaz `AllFilesAccess`

Frontera de plataforma nueva (Dart puro; `permission_handler` maneja el intent a Ajustes, sin código nativo).

`lib/platform/interfaces/all_files_access.dart`:

```dart
/// Acceso "a todos los archivos" (Android MANAGE_EXTERNAL_STORAGE). Permite
/// borrar/renombrar medios sin el consentimiento por-operación del sistema.
abstract class AllFilesAccess {
  /// True si el permiso está concedido AHORA.
  Future<bool> isGranted();

  /// Abre la pantalla especial de Ajustes para concederlo. Devuelve el estado
  /// resultante (true si quedó concedido al volver).
  Future<bool> request();
}
```

`lib/platform/android/android_all_files_access.dart`:

```dart
import 'package:permission_handler/permission_handler.dart';
import '../interfaces/all_files_access.dart';

class AndroidAllFilesAccess implements AllFilesAccess {
  @override
  Future<bool> isGranted() async => Permission.manageExternalStorage.status.then((s) => s.isGranted);

  @override
  Future<bool> request() async {
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }
}
```

`lib/platform/all_files_access_provider.dart`: `allFilesAccessProvider` (Provider throws-until-overridden), override en `main.dart` con `AndroidAllFilesAccess()`.

> Nota de implementación: verificar en `permission_handler` ^11 que `Permission.manageExternalStorage.request()` abre la pantalla de acceso especial (no un prompt runtime normal). Si el `.request()` no navegara bien en alguna versión, usar `openAppSettings()` como respaldo — a resolver en el plan.

## 2. Manifest

Agregar a `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

(Lint advierte que es un permiso restringido por Play Store; irrelevante para esta app personal sideloaded. No cambia `requestLegacyExternalStorage`.)

## 3. Ruta silenciosa nativa

En el handler `kivo/media` de `MainActivity.kt`, ramificar `delete` y `rename` por si se tiene acceso total:

- **`delete`**: si `Environment.isExternalStorageManager()` (API 30+ y permiso concedido) → `contentResolver.delete(uri, null, null)` directo → `result.success("ok")` inmediato (sin intent-sender, sin `onActivityResult`). En cualquier excepción → `"error"`. **Si no** → el flujo de consentimiento actual (`createDeleteRequest` / `RecoverableSecurityException`) queda **intacto como fallback**.
- **`rename`**: si `Environment.isExternalStorageManager()` → derivar la extensión con `queryDisplayName` (como hoy), `contentResolver.update(uri, ContentValues(DISPLAY_NAME=finalName))` directo → `{status: ok, newName: finalName}`. **Si no** → el flujo `createWriteRequest` actual como fallback.
- API < 30 no tiene `isExternalStorageManager`; ahí el código directo actual (`resolver.delete/update`) ya funciona con `WRITE_EXTERNAL_STORAGE` — sin cambios.

El `pendingFileOpResult`/`onActivityResult` solo se usan en la rama de consentimiento (fallback); la rama silenciosa no los toca.

## 4. Cómo se concede el permiso

Dos entradas, sin nag por-operación (las ops siempre funcionan gracias al fallback):

### 4.1 Ofrecimiento en el primer uso
La **primera vez** que el usuario borra o renombra **sin** el permiso concedido, tras confirmar la acción, se muestra **una vez** un diálogo explicativo:

> **Sin confirmaciones de Android**
> Para borrar y renombrar sin que Android te pida confirmación cada vez, dale a Kivo acceso a los archivos.
> [Ahora no] [Dar acceso]

- **[Dar acceso]** → `await allFilesAccess.request()` (abre Ajustes; resuelve al volver).
- **[Ahora no]** → no se pide nada.
- En ambos casos, **después** del diálogo la UI llama al controlador de la misma forma; **el nativo decide** silencioso-vs-consentimiento según `isExternalStorageManager()` en ese instante. Así no hay lógica de "reanudar la operación pendiente": si el usuario concedió durante el ofrecimiento, esta misma operación ya sale silenciosa; si no, cae al consentimiento del SO. Sin ramas especiales.
- Se marca un flag persistente para **no volver a ofrecerlo** automáticamente (la fila de Ajustes queda como vía permanente).

Flag nuevo en `KivoSettings`: `bool offeredAllFilesAccess` (default `false`), con los 6 puntos de inserción (field, ctor, `defaults()`, `copyWith` param+body, `toMap`, `fromMap`). Se pone `true` la primera vez que se muestra el diálogo.

### 4.2 Fila permanente en Ajustes
En `advanced_playback_section.dart`, una `SettingNavRow` (o equivalente del toolkit) "Acceso a todos los archivos":
- Subtítulo dinámico: "Concedido" / "Toca para permitir borrar y renombrar sin confirmación".
- Al tocar → `allFilesAccess.request()`; refresca el estado al volver.
- El estado se lee con un `FutureProvider`/`autoDispose` que consulta `allFilesAccess.isGranted()` (se invalida al volver de Ajustes).

## 5. Confirmación (resultante)

Con el permiso concedido:
- **Borrar** = 1 `AlertDialog` propio corto (ya existe, se conserva; el usuario eligió una confirmación rápida) → borrado silencioso. **Cero** diálogos del SO.
- **Renombrar** = solo su diálogo de texto (ya existe) → aplicado en silencio. **Cero** diálogos del SO.

Sin el permiso, el comportamiento actual (confirm propio + consentimiento del SO) se mantiene como fallback.

## 6. Orquestación (Dart)

`VideoActionsController` no cambia su lógica de efectos (limpieza/migración de llaves + refresh). El **ofrecimiento de permiso (4.1)** vive en la UI (`showVideoOptions`), no en el controlador, para no acoplar el controlador a diálogos:
- En `onDelete`/`onRename`, tras la confirmación/diálogo de texto y **antes** de llamar al controlador: si `!(await allFilesAccess.isGranted())` y `!settings.offeredAllFilesAccess` → mostrar el diálogo 4.1 (marcando el flag); si el usuario concede, seguir; si no, seguir igual (fallback). Luego llamar a `controller.delete/rename` como hoy.
- Guardas `context.mounted` tras cada await (coherente con el fix reciente).

## 7. Unidades y límites

1. **`all_files_access.dart` + `android_all_files_access.dart` + provider** — capacidad de permiso.
2. **`MainActivity.kt`** (delete/rename) — rama silenciosa vs fallback de consentimiento.
3. **`AndroidManifest.xml`** — el permiso.
4. **`KivoSettings`** — flag `offeredAllFilesAccess`.
5. **`advanced_playback_section.dart`** — fila de Ajustes.
6. **`video_options_sheet.dart`** — ofrecimiento en primer uso.

## 8. Testing

- **Unit:**
  - `KivoSettings`: `offeredAllFilesAccess` round-trip por `toMap`/`fromMap` y default `false`.
  - Lógica del ofrecimiento (una función pura o un pequeño helper): dado `(granted, offered)` decide si mostrar el diálogo → mostrar solo cuando `!granted && !offered`. Testeable como `bool shouldOfferAllFilesAccess(bool granted, bool offered)`.
- **Widget:**
  - `advanced_playback_section` muestra la fila con subtítulo "Concedido" vs no, según un `FakeAllFilesAccess`.
  - (Si es práctico) el diálogo de ofrecimiento aparece en el primer delete sin permiso y no en el segundo (flag) — con fakes; si montar el flujo completo es inviable, cubrir `shouldOfferAllFilesAccess` + verificación en dispositivo.
- **Fake:** `FakeAllFilesAccess` en `test/fakes/fakes.dart` (estado configurable `granted`, cuenta `requestCount`).
- **Checklist en dispositivo (release, Pixel 6, API 36):**
  - Sin el permiso: borrar/renombrar → aparece el diálogo de ofrecimiento (una sola vez) + el consentimiento del SO como hoy.
  - [Dar acceso] → pantalla de Ajustes → activar → volver → borrar/renombrar **sin ningún diálogo del SO** (solo el confirm propio de borrado).
  - La fila de Ajustes refleja "Concedido" y permite abrir la pantalla.
  - Revocar el permiso en Ajustes del sistema → las ops vuelven al fallback de consentimiento (no crashea).

## 9. Restricciones globales

- Un solo acento configurable; nada de colores nuevos hardcodeados.
- Patrón platform-boundary (interfaz + provider throws-until-overridden + override en main.dart).
- Sin deps nuevas (`permission_handler` ya está).
- `KivoSettings`: 6 puntos de inserción para el flag nuevo.
- No `flutter run`; build release + `adb install` al Pixel 6 (`24231FDF6006ST`) al cerrar el módulo.
- Suite completa verde.
- Las operaciones **nunca** deben romperse por falta del permiso: el flujo de consentimiento del SO permanece como fallback funcional.
