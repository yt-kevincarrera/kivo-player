# Kivo Hito 1 · Plan 1 — Fundación y reproducción

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tener una app Flutter que abre un video (vía "abrir con" o selector), lo reproduce con media_kit, recuerda la posición por archivo (resume) y conoce los videos hermanos de su carpeta (cola), sobre una base de settings persistente y una frontera de plataforma lista para iOS.

**Architecture:** Capas pragmáticas. El núcleo (settings, motor, resume, cola) es lógica pura testeable detrás de interfaces; lo específico de SO vive tras interfaces en `platform/` con implementación Android. media_kit se envuelve tras una interfaz `PlaybackEngine` para poder testear el estado con un fake. Estado y composición con Riverpod; persistencia con Hive.

**Tech Stack:** Flutter (Dart), media_kit + media_kit_video, flutter_riverpod, hive + path_provider, receive_sharing_intent, file_picker, screen_brightness, volume_controller, wakelock_plus; mocktail para tests.

## Global Constraints

- Plataforma objetivo: **Android primero**; el núcleo no debe depender de APIs Android directas — todo SO va tras interfaces en `platform/`.
- Motor de reproducción: **media_kit (libmpv)**, envuelto tras la interfaz `PlaybackEngine`. Ningún widget ni servicio importa `package:media_kit` salvo la implementación `MediaKitEngine`.
- Estado: **Riverpod**. El provider de `position` es independiente y de alta frecuencia.
- Persistencia: **Hive**. Acceso siempre tras una interfaz de store (no se usa `Box` directamente fuera de las impls de store).
- Principio transversal: **todo valor con sentido es configurable** y se lee desde `SettingsService`/providers, nunca hardcodeado en la UI o la lógica.
- Paleta: azul `#2D6CFF`, negro/oscuro base, dorado `#E8B84B`.
- Rango de velocidad máximo: **4.0x**.
- Mantener el APK lo más liviano posible (preferir dependencias ligeras), sin recortar features importantes.
- Extensiones de video soportadas (mínimo): `mkv, mp4, avi, mov, webm, flv, wmv, m4v, mpg, mpeg, ts, m2ts, 3gp, ogv`.
- Defaults de settings: los de la tabla del spec (`docs/superpowers/specs/2026-06-28-kivo-hito1-reproductor-design.md` §4).

---

## Estructura de archivos (este plan)

```
pubspec.yaml
analysis_options.yaml
lib/
  main.dart
  app.dart
  core/
    theme/kivo_theme.dart
    settings/kivo_settings.dart
    settings/settings_store.dart          # interfaz + HiveSettingsStore
    settings/settings_service.dart
    settings/settings_provider.dart
  player/
    engine/playback_engine.dart           # interfaz + estado
    engine/media_kit_engine.dart
    engine/playback_provider.dart
    resume/resume_store.dart              # interfaz + HiveResumeStore
    resume/resume_service.dart
    queue/file_system_lister.dart         # interfaz + IoFileSystemLister
    queue/natural_sort.dart
    queue/folder_queue_scanner.dart
    open/video_source.dart                # apertura: intent + picker
  platform/
    interfaces/device_controls.dart       # brillo, volumen, orientación, wakelock
    android/android_device_controls.dart
  ui/
    player/player_screen.dart             # reproductor mínimo (sin controles ricos)
    home/open_screen.dart                 # pantalla inicial: botón "abrir archivo"
test/
  core/settings/settings_service_test.dart
  player/resume/resume_service_test.dart
  player/queue/natural_sort_test.dart
  player/queue/folder_queue_scanner_test.dart
  player/engine/playback_provider_test.dart
  fakes/fakes.dart
```

---

### Task 1: Scaffold del proyecto Flutter + dependencias + git

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/app.dart`
- Create: estructura Android estándar (la genera `flutter create`)
- Test: `test/smoke_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: app Flutter ejecutable; `KivoApp` widget raíz envuelto en `ProviderScope`.

- [ ] **Step 1: Generar el proyecto Flutter en el directorio actual**

Run (PowerShell, desde la raíz del repo vacío):
```
flutter create --org dev.selector --project-name kivo_player --platforms=android .
```
Expected: crea `android/`, `lib/main.dart`, `pubspec.yaml`, `test/widget_test.dart`.

- [ ] **Step 2: Inicializar git**

```bash
git init
git add -A
git commit -m "chore: scaffold flutter project"
```

- [ ] **Step 3: Declarar dependencias en `pubspec.yaml`**

Reemplaza la sección `dependencies`/`dev_dependencies` por:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_video: ^1.0.5
  hive: ^2.2.3
  path_provider: ^2.1.4
  receive_sharing_intent: ^1.8.0
  file_picker: ^8.1.2
  screen_brightness: ^1.0.1
  volume_controller: ^2.0.7
  wakelock_plus: ^1.2.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.4
  flutter_lints: ^4.0.0
```

Run: `flutter pub get`
Expected: resuelve sin errores.

- [ ] **Step 4: Configurar `minSdkVersion` para media_kit**

En `android/app/build.gradle`, dentro de `defaultConfig`, fija:
```gradle
minSdkVersion 21
```
(media_kit requiere 21+.)

- [ ] **Step 5: Escribir `lib/app.dart` (widget raíz)**

```dart
import 'package:flutter/material.dart';
import 'core/theme/kivo_theme.dart';
import 'ui/home/open_screen.dart';

class KivoApp extends StatelessWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.dark(),
      home: const OpenScreen(),
    );
  }
}
```

- [ ] **Step 6: Escribir `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: KivoApp()));
}
```

> `KivoTheme`, `OpenScreen` se crean en tareas siguientes. Hasta entonces el proyecto no compila completo; el smoke test se habilita al final de Task 2/Task 9. Crea stubs mínimos si necesitas compilar antes: un `OpenScreen` que muestre `Scaffold(body: Center(child: Text('Kivo')))` y `KivoTheme.dark()` devolviendo `ThemeData.dark()`. Se reemplazan en sus tareas.

- [ ] **Step 7: Smoke test**

`test/smoke_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/home/open_screen.dart';

void main() {
  testWidgets('OpenScreen renders without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OpenScreen())),
    );
    expect(find.byType(OpenScreen), findsOneWidget);
  });
}
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: dependencies, app root, smoke test"
```

---

### Task 2: Tema azul/negro/dorado

**Files:**
- Create: `lib/core/theme/kivo_theme.dart`
- Test: `test/core/theme/kivo_theme_test.dart`

**Interfaces:**
- Produces: `KivoColors` (constantes `blue`, `gold`, `ink`, `panel`), `KivoTheme.dark() -> ThemeData`.

- [ ] **Step 1: Test de colores**

`test/core/theme/kivo_theme_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';

void main() {
  test('palette matches spec', () {
    expect(KivoColors.blue, const Color(0xFF2D6CFF));
    expect(KivoColors.gold, const Color(0xFFE8B84B));
  });

  test('dark theme uses gold as secondary accent', () {
    final theme = KivoTheme.dark();
    expect(theme.colorScheme.secondary, KivoColors.gold);
    expect(theme.brightness, Brightness.dark);
  });
}
```

- [ ] **Step 2: Run test → FAIL** (`KivoColors` no existe)

Run: `flutter test test/core/theme/kivo_theme_test.dart`

- [ ] **Step 3: Implementar `kivo_theme.dart`**

```dart
import 'package:flutter/material.dart';

class KivoColors {
  static const blue = Color(0xFF2D6CFF);
  static const gold = Color(0xFFE8B84B);
  static const ink = Color(0xFF0A0E1A);
  static const panel = Color(0xFF111726);
}

class KivoTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: KivoColors.blue,
      secondary: KivoColors.gold,
      surface: KivoColors.panel,
    );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: KivoColors.ink,
      useMaterial3: true,
    );
  }
}
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: kivo theme (blue/black/gold)"
```

---

### Task 3: Modelo de settings + persistencia + provider

**Files:**
- Create: `lib/core/settings/kivo_settings.dart`, `lib/core/settings/settings_store.dart`, `lib/core/settings/settings_service.dart`, `lib/core/settings/settings_provider.dart`
- Create: `test/fakes/fakes.dart`
- Test: `test/core/settings/settings_service_test.dart`

**Interfaces:**
- Produces:
  - `KivoSettings` (immutable) con campos: `doubleTapSkipLeft:int`, `doubleTapSkipRight:int`, `doubleTapCenterPause:bool`, `brightnessSensitivity:double`, `volumeSensitivity:double`, `seekSensitivity:double`, `horizontalSeek:bool`, `hapticsOnGestures:bool`, `volumeBoostMax:int`, `holdLeftSpeed:double`, `holdRightMin:double`, `holdRightMax:double`, `holdRightReleaseToNormal:bool`, `speedFineStep:double`, `speedPresets:List<double>`, `rememberSpeed:bool`, `centerSkipSeconds:int`, `controlsAutoHideMs:int`, `showInfoOverlay:bool`, `infoOverlayContent:String`, `infoOverlayCorner:String`, `defaultAspectMode:String`, `resumeBehavior:String`, `resumeMinSeconds:int`, `rememberOrientationLock:bool`. Métodos: `copyWith(...)`, `toMap()`, `KivoSettings.fromMap(Map)`, `KivoSettings.defaults()`.
  - `SettingsStore` interface: `Map<String, dynamic>? read()`, `Future<void> write(Map<String, dynamic>)`.
  - `HiveSettingsStore implements SettingsStore`.
  - `SettingsService`: `KivoSettings get current`, `Future<void> update(KivoSettings)`, `static Future<SettingsService> load(SettingsStore)`.
  - `settingsProvider`: `NotifierProvider<SettingsNotifier, KivoSettings>`; `SettingsNotifier.set(KivoSettings)`.

- [ ] **Step 1: Test del servicio con store en memoria**

`test/fakes/fakes.dart` (se ampliará en otras tareas):
```dart
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/player/resume/resume_store.dart';
import 'package:kivo_player/player/queue/file_system_lister.dart';

class InMemorySettingsStore implements SettingsStore {
  Map<String, dynamic>? _data;
  @override
  Map<String, dynamic>? read() => _data;
  @override
  Future<void> write(Map<String, dynamic> data) async => _data = data;
}

class InMemoryResumeStore implements ResumeStore {
  final Map<String, int> data = {};
  @override
  int? secondsFor(String key) => data[key];
  @override
  Future<void> put(String key, int seconds) async => data[key] = seconds;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

class FakeFileSystemLister implements FileSystemLister {
  final Map<String, List<String>> dirs;
  FakeFileSystemLister(this.dirs);
  @override
  List<String> listFiles(String dir) => dirs[dir] ?? const [];
}
```

`test/core/settings/settings_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import '../../fakes/fakes.dart';

void main() {
  test('loads defaults when store is empty', () async {
    final service = await SettingsService.load(InMemorySettingsStore());
    expect(service.current.centerSkipSeconds, 10);
    expect(service.current.holdRightMax, 4.0);
    expect(service.current.resumeBehavior, 'auto');
  });

  test('persists and reloads updated settings', () async {
    final store = InMemorySettingsStore();
    final service = await SettingsService.load(store);
    await service.update(service.current.copyWith(centerSkipSeconds: 30));

    final reloaded = await SettingsService.load(store);
    expect(reloaded.current.centerSkipSeconds, 30);
  });

  test('round-trips through map', () {
    final s = KivoSettings.defaults().copyWith(volumeBoostMax: 200);
    expect(KivoSettings.fromMap(s.toMap()).volumeBoostMax, 200);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/core/settings/settings_service_test.dart`

- [ ] **Step 3: Implementar `kivo_settings.dart`**

```dart
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
    );
  }
}
```

- [ ] **Step 4: Implementar `settings_store.dart`**

```dart
import 'package:hive/hive.dart';

abstract class SettingsStore {
  Map<String, dynamic>? read();
  Future<void> write(Map<String, dynamic> data);
}

class HiveSettingsStore implements SettingsStore {
  final Box box;
  static const _key = 'settings';
  HiveSettingsStore(this.box);

  @override
  Map<String, dynamic>? read() {
    final raw = box.get(_key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  @override
  Future<void> write(Map<String, dynamic> data) => box.put(_key, data);
}
```

- [ ] **Step 5: Implementar `settings_service.dart`**

```dart
import 'kivo_settings.dart';
import 'settings_store.dart';

class SettingsService {
  final SettingsStore _store;
  KivoSettings _current;

  SettingsService._(this._store, this._current);

  KivoSettings get current => _current;

  static Future<SettingsService> load(SettingsStore store) async {
    final map = store.read();
    final settings = map == null ? KivoSettings.defaults() : KivoSettings.fromMap(map);
    return SettingsService._(store, settings);
  }

  Future<void> update(KivoSettings next) async {
    _current = next;
    await _store.write(next.toMap());
  }
}
```

- [ ] **Step 6: Run test → PASS**

- [ ] **Step 7: Implementar `settings_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'kivo_settings.dart';
import 'settings_service.dart';

/// Overridden in main() once SettingsService is loaded.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError('settingsServiceProvider must be overridden');
});

class SettingsNotifier extends Notifier<KivoSettings> {
  @override
  KivoSettings build() => ref.read(settingsServiceProvider).current;

  Future<void> set(KivoSettings next) async {
    state = next;
    await ref.read(settingsServiceProvider).update(next);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, KivoSettings>(SettingsNotifier.new);
```

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: configurable settings model + hive persistence + provider"
```

---

### Task 4: Frontera de plataforma (controles de dispositivo)

**Files:**
- Create: `lib/platform/interfaces/device_controls.dart`, `lib/platform/android/android_device_controls.dart`
- Test: `test/platform/device_controls_test.dart`

**Interfaces:**
- Produces: `DeviceControls` interface con `Future<void> setBrightness(double v01)`, `Future<double> currentBrightness()`, `Future<void> setSystemVolume(double v01)`, `Future<double> currentVolume()`, `Future<void> setOrientation(List<DeviceOrientationLock> o)`, `Future<void> keepAwake(bool on)`. Enum `DeviceOrientationLock { auto, portrait, landscape }`. Impl `AndroidDeviceControls`.

- [ ] **Step 1: Test del contrato (clamp de brillo)**

`test/platform/device_controls_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/device_controls.dart';

class RecordingControls implements DeviceControls {
  double brightness = 0.5;
  @override
  Future<double> currentBrightness() async => brightness;
  @override
  Future<void> setBrightness(double v01) async => brightness = v01.clamp(0.0, 1.0);
  @override
  Future<double> currentVolume() async => 0.5;
  @override
  Future<void> setSystemVolume(double v01) async {}
  @override
  Future<void> setOrientation(List<DeviceOrientationLock> o) async {}
  @override
  Future<void> keepAwake(bool on) async {}
}

void main() {
  test('brightness clamps to 0..1', () async {
    final c = RecordingControls();
    await c.setBrightness(1.5);
    expect(await c.currentBrightness(), 1.0);
    await c.setBrightness(-0.2);
    expect(await c.currentBrightness(), 0.0);
  });
}
```

- [ ] **Step 2: Run test → FAIL** (interfaz no existe)

- [ ] **Step 3: Implementar la interfaz `device_controls.dart`**

```dart
enum DeviceOrientationLock { auto, portrait, landscape }

abstract class DeviceControls {
  Future<void> setBrightness(double v01);
  Future<double> currentBrightness();
  Future<void> setSystemVolume(double v01);
  Future<double> currentVolume();
  Future<void> setOrientation(List<DeviceOrientationLock> orientations);
  Future<void> keepAwake(bool on);
}
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Implementar `android_device_controls.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../interfaces/device_controls.dart';

class AndroidDeviceControls implements DeviceControls {
  @override
  Future<void> setBrightness(double v01) =>
      ScreenBrightness().setScreenBrightness(v01.clamp(0.0, 1.0));

  @override
  Future<double> currentBrightness() => ScreenBrightness().current;

  @override
  Future<void> setSystemVolume(double v01) async {
    VolumeController().setVolume(v01.clamp(0.0, 1.0));
  }

  @override
  Future<double> currentVolume() => VolumeController().getVolume();

  @override
  Future<void> setOrientation(List<DeviceOrientationLock> orientations) {
    final mapped = <DeviceOrientation>[];
    for (final o in orientations) {
      switch (o) {
        case DeviceOrientationLock.auto:
          return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        case DeviceOrientationLock.portrait:
          mapped.addAll([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
        case DeviceOrientationLock.landscape:
          mapped.addAll([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      }
    }
    return SystemChrome.setPreferredOrientations(mapped);
  }

  @override
  Future<void> keepAwake(bool on) => WakelockPlus.toggle(enable: on);
}

final deviceControls = AndroidDeviceControls();
```

> Provider de inyección (lo consumirá Plan 2). Añadir a `device_controls.dart`:
```dart
// (en device_controls.dart, al final)
// Provider declarado en platform/android para no acoplar la interfaz a una impl.
```
Crear `lib/platform/device_controls_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/device_controls.dart';
import 'android/android_device_controls.dart';

final deviceControlsProvider = Provider<DeviceControls>((ref) => deviceControls);
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: platform boundary for device controls (android impl)"
```

---

### Task 5: Motor de reproducción (interfaz + media_kit + providers)

**Files:**
- Create: `lib/player/engine/playback_engine.dart`, `lib/player/engine/media_kit_engine.dart`, `lib/player/engine/playback_provider.dart`
- Test: `test/player/engine/playback_provider_test.dart`

**Interfaces:**
- Produces:
  - `PlaybackEngine` interface: `Future<void> open(String path, {Duration startAt = Duration.zero})`, `Future<void> play()`, `Future<void> pause()`, `Future<void> seek(Duration p)`, `Future<void> setRate(double r)`, `Future<void> setVolume(double percent)`, `Future<void> dispose()`, streams: `Stream<Duration> positionStream`, `Stream<Duration> durationStream`, `Stream<bool> playingStream`, `Stream<bool> bufferingStream`, y `dynamic get nativePlayer` (para `media_kit_video`).
  - `MediaKitEngine implements PlaybackEngine`.
  - Providers: `playbackEngineProvider` (Provider, override en main/test), `positionProvider` (StreamProvider<Duration>), `durationProvider`, `playingProvider`, `bufferingProvider`.

- [ ] **Step 1: Ampliar fakes con `FakePlaybackEngine`**

Añadir a `test/fakes/fakes.dart`:
```dart
import 'dart:async';
import 'package:kivo_player/player/engine/playback_engine.dart';

class FakePlaybackEngine implements PlaybackEngine {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();

  String? openedPath;
  Duration? openedAt;
  double rate = 1.0;
  double volume = 100;

  @override
  dynamic get nativePlayer => null;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get durationStream => _dur.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  void emitPosition(Duration d) => _pos.add(d);
  void emitDuration(Duration d) => _dur.add(d);
  void emitPlaying(bool v) => _playing.add(v);

  @override
  Future<void> open(String path, {Duration startAt = Duration.zero}) async {
    openedPath = path;
    openedAt = startAt;
  }
  @override
  Future<void> play() async => _playing.add(true);
  @override
  Future<void> pause() async => _playing.add(false);
  @override
  Future<void> seek(Duration p) async => _pos.add(p);
  @override
  Future<void> setRate(double r) async => rate = r;
  @override
  Future<void> setVolume(double percent) async => volume = percent;
  @override
  Future<void> dispose() async {
    _pos.close(); _dur.close(); _playing.close(); _buffering.close();
  }
}
```

- [ ] **Step 2: Test del provider de posición**

`test/player/engine/playback_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import '../../fakes/fakes.dart';

void main() {
  test('positionProvider reflects engine stream', () async {
    final engine = FakePlaybackEngine();
    final container = ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);

    final sub = container.listen(positionProvider, (_, __) {});
    engine.emitPosition(const Duration(seconds: 7));
    await Future<void>.delayed(Duration.zero);

    expect(sub.read().value, const Duration(seconds: 7));
  });
}
```

- [ ] **Step 3: Run test → FAIL**

- [ ] **Step 4: Implementar `playback_engine.dart`**

```dart
abstract class PlaybackEngine {
  dynamic get nativePlayer;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;

  Future<void> open(String path, {Duration startAt});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double percent);
  Future<void> dispose();
}
```

- [ ] **Step 5: Implementar `media_kit_engine.dart`**

```dart
import 'package:media_kit/media_kit.dart';
import 'playback_engine.dart';

class MediaKitEngine implements PlaybackEngine {
  final Player _player = Player();

  @override
  dynamic get nativePlayer => _player;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Future<void> open(String path, {Duration startAt = Duration.zero}) async {
    await _player.open(Media(path, start: startAt), play: true);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);
  @override
  Future<void> dispose() => _player.dispose();
}
```

- [ ] **Step 6: Implementar `playback_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'playback_engine.dart';

final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  throw UnimplementedError('playbackEngineProvider must be overridden');
});

final positionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackEngineProvider).positionStream;
});

final durationProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackEngineProvider).durationStream;
});

final playingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playbackEngineProvider).playingStream;
});

final bufferingProvider = StreamProvider<bool>((ref) {
  return ref.watch(playbackEngineProvider).bufferingStream;
});
```

- [ ] **Step 7: Run test → PASS**

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: playback engine interface + media_kit impl + state providers"
```

---

### Task 6: Servicio de reanudación (resume)

**Files:**
- Create: `lib/player/resume/resume_store.dart`, `lib/player/resume/resume_service.dart`
- Test: `test/player/resume/resume_service_test.dart`

**Interfaces:**
- Produces:
  - `ResumeStore` interface: `int? secondsFor(String key)`, `Future<void> put(String key, int seconds)`, `Future<void> remove(String key)`. Impl `HiveResumeStore`.
  - `ResumeService(ResumeStore store, {int minSeconds = 5, double finishedTailFraction = 0.97})`: `Duration? positionFor(String key)`, `Future<void> record(String key, Duration position, Duration total)`, `Future<void> clear(String key)`.

- [ ] **Step 1: Tests de la lógica de resume**

`test/player/resume/resume_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

void main() {
  late InMemoryResumeStore store;
  late ResumeService service;
  setUp(() {
    store = InMemoryResumeStore();
    service = ResumeService(store, minSeconds: 5);
  });

  test('does not record below min threshold', () async {
    await service.record('a', const Duration(seconds: 3), const Duration(minutes: 10));
    expect(service.positionFor('a'), isNull);
  });

  test('records position above threshold', () async {
    await service.record('a', const Duration(seconds: 30), const Duration(minutes: 10));
    expect(service.positionFor('a'), const Duration(seconds: 30));
  });

  test('clears when near the end (finished)', () async {
    await service.record('a', const Duration(seconds: 60), const Duration(minutes: 10));
    expect(service.positionFor('a'), isNotNull);
    // 99% of 600s = 594s -> finished
    await service.record('a', const Duration(seconds: 595), const Duration(seconds: 600));
    expect(service.positionFor('a'), isNull);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implementar `resume_store.dart`**

```dart
import 'package:hive/hive.dart';

abstract class ResumeStore {
  int? secondsFor(String key);
  Future<void> put(String key, int seconds);
  Future<void> remove(String key);
}

class HiveResumeStore implements ResumeStore {
  final Box box;
  HiveResumeStore(this.box);

  @override
  int? secondsFor(String key) => box.get(key) as int?;
  @override
  Future<void> put(String key, int seconds) => box.put(key, seconds);
  @override
  Future<void> remove(String key) => box.delete(key);
}
```

- [ ] **Step 4: Implementar `resume_service.dart`**

```dart
import 'resume_store.dart';

class ResumeService {
  final ResumeStore _store;
  final int minSeconds;
  final double finishedTailFraction;

  ResumeService(this._store, {this.minSeconds = 5, this.finishedTailFraction = 0.97});

  Duration? positionFor(String key) {
    final s = _store.secondsFor(key);
    return s == null ? null : Duration(seconds: s);
  }

  Future<void> record(String key, Duration position, Duration total) async {
    final finishedThreshold = total.inMilliseconds * finishedTailFraction;
    if (total.inMilliseconds > 0 && position.inMilliseconds >= finishedThreshold) {
      await _store.remove(key);
      return;
    }
    if (position.inSeconds < minSeconds) return;
    await _store.put(key, position.inSeconds);
  }

  Future<void> clear(String key) => _store.remove(key);
}
```

- [ ] **Step 5: Run test → PASS**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: per-file resume service with finished/threshold logic"
```

---

### Task 7: Orden natural de nombres

**Files:**
- Create: `lib/player/queue/natural_sort.dart`
- Test: `test/player/queue/natural_sort_test.dart`

**Interfaces:**
- Produces: `int naturalCompare(String a, String b)`.

- [ ] **Step 1: Test**

`test/player/queue/natural_sort_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/queue/natural_sort.dart';

void main() {
  test('orders episode numbers numerically, not lexically', () {
    final names = ['ep2.mkv', 'ep10.mkv', 'ep1.mkv'];
    names.sort(naturalCompare);
    expect(names, ['ep1.mkv', 'ep2.mkv', 'ep10.mkv']);
  });

  test('case-insensitive', () {
    expect(naturalCompare('Apple', 'apple') == 0, isFalse); // stable but defined
    final l = ['B.mkv', 'a.mkv'];
    l.sort(naturalCompare);
    expect(l.first, 'a.mkv');
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implementar `natural_sort.dart`**

```dart
int naturalCompare(String a, String b) {
  final ra = _tokenize(a.toLowerCase());
  final rb = _tokenize(b.toLowerCase());
  final n = ra.length < rb.length ? ra.length : rb.length;
  for (var i = 0; i < n; i++) {
    final ta = ra[i], tb = rb[i];
    final na = int.tryParse(ta), nb = int.tryParse(tb);
    int c;
    if (na != null && nb != null) {
      c = na.compareTo(nb);
    } else {
      c = ta.compareTo(tb);
    }
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

List<String> _tokenize(String s) {
  final out = <String>[];
  final buf = StringBuffer();
  bool? digit;
  for (final ch in s.codeUnits) {
    final isDigit = ch >= 0x30 && ch <= 0x39;
    if (digit != null && isDigit != digit && buf.isNotEmpty) {
      out.add(buf.toString());
      buf.clear();
    }
    buf.writeCharCode(ch);
    digit = isDigit;
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}
```

- [ ] **Step 4: Run test → PASS**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: natural-order filename comparator"
```

---

### Task 8: Escáner de cola por carpeta

**Files:**
- Create: `lib/player/queue/file_system_lister.dart`, `lib/player/queue/folder_queue_scanner.dart`
- Test: `test/player/queue/folder_queue_scanner_test.dart`

**Interfaces:**
- Consumes: `naturalCompare` (Task 7).
- Produces:
  - `FileSystemLister` interface: `List<String> listFiles(String dir)`. Impl `IoFileSystemLister`.
  - `const kVideoExtensions` (Set<String>).
  - `FolderQueueScanner(FileSystemLister lister)`: `List<String> siblingsOf(String filePath)` — devuelve los paths de video de la misma carpeta (incluido el actual), filtrados por extensión y ordenados con `naturalCompare`.

- [ ] **Step 1: Test con lister fake** (`FakeFileSystemLister` ya existe en fakes.dart)

`test/player/queue/folder_queue_scanner_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/queue/folder_queue_scanner.dart';
import '../../fakes/fakes.dart';

void main() {
  test('returns only video siblings, naturally sorted', () {
    final lister = FakeFileSystemLister({
      '/movies': [
        '/movies/ep10.mkv',
        '/movies/ep2.mkv',
        '/movies/notes.txt',
        '/movies/ep1.mp4',
        '/movies/cover.jpg',
      ],
    });
    final scanner = FolderQueueScanner(lister);
    final result = scanner.siblingsOf('/movies/ep2.mkv');
    expect(result, [
      '/movies/ep1.mp4',
      '/movies/ep2.mkv',
      '/movies/ep10.mkv',
    ]);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implementar `file_system_lister.dart`**

```dart
import 'dart:io';

abstract class FileSystemLister {
  List<String> listFiles(String dir);
}

class IoFileSystemLister implements FileSystemLister {
  @override
  List<String> listFiles(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }
}
```

- [ ] **Step 4: Implementar `folder_queue_scanner.dart`**

```dart
import 'natural_sort.dart';
import 'file_system_lister.dart';

const kVideoExtensions = {
  'mkv', 'mp4', 'avi', 'mov', 'webm', 'flv', 'wmv',
  'm4v', 'mpg', 'mpeg', 'ts', 'm2ts', '3gp', 'ogv',
};

class FolderQueueScanner {
  final FileSystemLister _lister;
  FolderQueueScanner(this._lister);

  List<String> siblingsOf(String filePath) {
    final dir = _dirOf(filePath);
    final files = _lister.listFiles(dir).where(_isVideo).toList();
    files.sort((a, b) => naturalCompare(_baseName(a), _baseName(b)));
    return files;
  }

  bool _isVideo(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return false;
    return kVideoExtensions.contains(path.substring(i + 1).toLowerCase());
  }

  String _dirOf(String path) {
    final i = path.replaceAll('\\', '/').lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  String _baseName(String path) {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }
}
```

- [ ] **Step 5: Run test → PASS**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: folder queue scanner (video siblings, natural order)"
```

---

### Task 9: Cableado de apertura + pantalla del reproductor mínima

**Files:**
- Modify: `lib/main.dart` (inicializar Hive y overrides de providers)
- Create: `lib/player/open/video_source.dart`, `lib/ui/home/open_screen.dart`, `lib/ui/player/player_screen.dart`
- Modify: `lib/app.dart` (ya creado)
- Test: `test/ui/open_flow_test.dart`

**Interfaces:**
- Consumes: `settingsServiceProvider`, `settingsProvider`, `playbackEngineProvider`, `positionProvider`, `durationProvider`, `playingProvider`, `ResumeService`, `FolderQueueScanner`, `KivoTheme`.
- Produces:
  - `resumeServiceProvider` (Provider, override en main).
  - `queueScannerProvider` (Provider<FolderQueueScanner>).
  - `currentVideoProvider` (NotifierProvider exposing `VideoSession?` with `path`, `queue`, `index`).
  - `OpenScreen` (botón "Abrir archivo" + escucha share intent).
  - `PlayerScreen` (reproduce el video, aplica resume al abrir, guarda al pausar/salir).

- [ ] **Step 1: Test del flujo de apertura (con fakes)**

`test/ui/open_flow_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/player/player_screen.dart';
import '../fakes/fakes.dart';

void main() {
  testWidgets('opening a video with saved resume seeks engine to that position',
      (tester) async {
    final engine = FakePlaybackEngine();
    final resumeStore = InMemoryResumeStore();
    await resumeStore.put('/movies/ep1.mkv', 120); // 2 min saved
    final settingsService = await SettingsService.load(InMemorySettingsStore());

    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      playbackEngineProvider.overrideWithValue(engine),
      resumeServiceProvider.overrideWithValue(ResumeService(resumeStore)),
    ]);
    addTearDown(container.dispose);

    container.read(currentVideoProvider.notifier).open(
          const VideoSession(path: '/movies/ep1.mkv', queue: ['/movies/ep1.mkv'], index: 0),
        );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await tester.pump();

    expect(engine.openedPath, '/movies/ep1.mkv');
    expect(engine.openedAt, const Duration(seconds: 120));
  });
}
```

- [ ] **Step 2: Run test → FAIL**

- [ ] **Step 3: Implementar `video_source.dart`** (sesión actual + providers de resume/cola)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../resume/resume_service.dart';
import '../queue/folder_queue_scanner.dart';
import '../queue/file_system_lister.dart';

class VideoSession {
  final String path;
  final List<String> queue;
  final int index;
  const VideoSession({required this.path, required this.queue, required this.index});
}

final resumeServiceProvider = Provider<ResumeService>((ref) {
  throw UnimplementedError('resumeServiceProvider must be overridden');
});

final queueScannerProvider = Provider<FolderQueueScanner>(
  (ref) => FolderQueueScanner(IoFileSystemLister()),
);

class CurrentVideoNotifier extends Notifier<VideoSession?> {
  @override
  VideoSession? build() => null;

  void open(VideoSession session) => state = session;

  void openPath(String path) {
    final queue = ref.read(queueScannerProvider).siblingsOf(path);
    final index = queue.indexOf(path);
    state = VideoSession(
      path: path,
      queue: queue.isEmpty ? [path] : queue,
      index: index < 0 ? 0 : index,
    );
  }
}

final currentVideoProvider =
    NotifierProvider<CurrentVideoNotifier, VideoSession?>(CurrentVideoNotifier.new);
```

- [ ] **Step 4: Implementar `player_screen.dart`** (reproductor mínimo: aplica resume, guarda posición)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart';
import '../../player/engine/playback_provider.dart';
import '../../player/open/video_source.dart';
import '../../player/resume/resume_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoController? _controller;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  String? _path;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final session = ref.read(currentVideoProvider);
    if (session == null) return;
    _path = session.path;
    final engine = ref.read(playbackEngineProvider);
    final resume = ref.read(resumeServiceProvider);
    final startAt = resume.positionFor(session.path) ?? Duration.zero;

    final native = engine.nativePlayer;
    if (native is Player) {
      _controller = VideoController(native);
      setState(() {});
    }
    await engine.open(session.path, startAt: startAt);
  }

  Future<void> _saveProgress() async {
    final path = _path;
    if (path == null || _lastDuration == Duration.zero) return;
    await ref.read(resumeServiceProvider).record(path, _lastPosition, _lastDuration);
  }

  @override
  void dispose() {
    _saveProgress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(positionProvider, (_, next) {
      next.whenData((d) => _lastPosition = d);
    });
    ref.listen(durationProvider, (_, next) {
      next.whenData((d) => _lastDuration = d);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _controller == null
            ? const CircularProgressIndicator()
            : Video(controller: _controller!),
      ),
    );
  }
}
```

- [ ] **Step 5: Implementar `open_screen.dart`** (botón abrir + share intent)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../player/open/video_source.dart';
import '../player/player_screen.dart';

class OpenScreen extends ConsumerStatefulWidget {
  const OpenScreen({super.key});
  @override
  ConsumerState<OpenScreen> createState() => _OpenScreenState();
}

class _OpenScreenState extends ConsumerState<OpenScreen> {
  @override
  void initState() {
    super.initState();
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) _openPath(files.first.path);
    });
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) _openPath(files.first.path);
    });
  }

  void _openPath(String path) {
    ref.read(currentVideoProvider.notifier).openPath(path);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) _openPath(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open),
          label: const Text('Abrir video'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implementar el cableado en `main.dart`** (Hive + overrides)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'core/settings/settings_store.dart';
import 'core/settings/settings_service.dart';
import 'core/settings/settings_provider.dart';
import 'player/engine/media_kit_engine.dart';
import 'player/engine/playback_provider.dart';
import 'player/resume/resume_store.dart';
import 'player/resume/resume_service.dart';
import 'player/open/video_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  final settingsBox = await Hive.openBox('settings');
  final resumeBox = await Hive.openBox('resume');

  final settingsService = await SettingsService.load(HiveSettingsStore(settingsBox));
  final resumeService = ResumeService(
    HiveResumeStore(resumeBox),
    minSeconds: settingsService.current.resumeMinSeconds,
  );
  final engine = MediaKitEngine();

  runApp(ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      playbackEngineProvider.overrideWithValue(engine),
      resumeServiceProvider.overrideWithValue(resumeService),
    ],
    child: const KivoApp(),
  ));
}
```

- [ ] **Step 7: Configurar permisos Android (share intent + lectura)**

En `android/app/src/main/AndroidManifest.xml`, dentro de `<activity>` añade el intent-filter para "abrir con":
```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <data android:mimeType="video/*" />
</intent-filter>
```
Y antes de `<application>`:
```xml
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
```

- [ ] **Step 8: Run test → PASS**

Run: `flutter test test/ui/open_flow_test.dart`

- [ ] **Step 9: Verificación manual en dispositivo/emulador**

Run: `flutter run`
Expected: arranca en `OpenScreen`; "Abrir video" abre el selector; al elegir un mkv/mp4 reproduce. Si había progreso guardado (≥ umbral), reanuda en esa posición.

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "feat: open via picker/intent, minimal player with resume + folder queue"
```

---

## Self-Review (cobertura del spec, este plan)

- **§3 Stack/arquitectura:** Tasks 1,3,4,5 (Flutter, media_kit tras interfaz, Riverpod, Hive tras store, frontera de plataforma). ✓
- **§4 Settings base + tabla:** Task 3 implementa todos los valores con sus defaults. ✓
- **§5 Motor:** Task 5 (interfaz + impl + providers, `position` aislado). ✓
- **§9 Seek con miniatura, §6/§7/§8 UI rica, §11 toast de resume:** **fuera de este plan** (Plan 2/3). El *guardado/lectura* de resume sí está (Task 6 + Task 9). ✓ (alcance correcto)
- **§10 Cola por carpeta:** Tasks 7,8,9. ✓
- **§12 Apertura (intent + picker):** Task 9. ✓
- **§13 Tema:** Task 2. ✓

**Placeholder scan:** sin TBD/TODO; todo paso con código real. El único stub explícito (Task 1 Step 6) se reemplaza en Tasks 2 y 9 — señalado. ✓

**Type consistency:** `PlaybackEngine`, `ResumeService.record/positionFor`, `FolderQueueScanner.siblingsOf`, `VideoSession`, providers (`playbackEngineProvider`, `resumeServiceProvider`, `currentVideoProvider`) usados consistentemente entre Tasks 5/6/8/9 y sus tests. ✓

## Roadmap (próximos planes del Hito 1)

- **Plan 2 — Controles y gestos:** `ui/player/controls/*`, `ui/player/gestures/*`, velocidad (mantener-izq/der + panel granular), HUD de brillo/volumen/seek; consume `DeviceControls`, `settingsProvider`, `PlaybackEngine`.
- **Plan 3 — Pulido:** tira de miniaturas (cola), seek con miniatura on-demand (2ª instancia mpv), overlay de info permanente con toggle persistido, lock/aspecto/rotación.
