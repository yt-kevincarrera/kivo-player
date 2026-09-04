# Kivo internacionalización — Design

**Date:** 2026-09-04
**Status:** Approved for implementation (user: "ingles como segunda")

## Goal

Que Kivo deje de ser español-solo con cadenas inline, y que añadir un idioma
sea un archivo. Español como fuente de verdad (el copy actual, tal cual),
inglés como primera traducción.

## Tamaño real (medido 2026-09-04)

- 388 cadenas distintas de interfaz en 51 archivos bajo `lib/ui`.
- 18 mensajes de error `KV-nnn` en `lib/core/errors/kivo_failure.dart`.
- 5 plurales hechos a mano (`== 1 ? 'video' : 'videos'`).
- 30 cadenas del lado Android (notificación, permisos, huella).
- **58 archivos de test afirman texto en español** (251 literales distintos).
  Ese número manda: la mitad del trabajo es desacoplar los tests del idioma.
- Sin `l10n.yaml`, sin `flutter_localizations`, sin `intl`.

## 1. Mecanismo

El estándar de Flutter: `gen-l10n` con ARB.
- `lib/l10n/app_es.arb` es la plantilla (`template-arb-file`). Contiene el
  español ACTUAL, sin reescribir copy. Cada clave lleva `@description`.
- `lib/l10n/app_en.arb`, la traducción.
- `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_es.arb`,
  `output-localization-file: app_localizations.dart`, `nullable-getter: false`,
  `synthetic-package: false` (salida bajo `lib/l10n/generated/`, versionada,
  para que los tests no dependan de un paso de generación).
- `pubspec.yaml`: `flutter_localizations` (sdk), `intl`, `generate: true`.
- Acceso: `context.l10n` (extensión en `lib/l10n/l10n.dart`) →
  `AppLocalizations.of(context)`.

## 2. Plurales, placeholders, formato

- Plurales en ICU: `{n, plural, =1{1 video} other{{n} videos}}`. Los cinco
  casos a mano desaparecen.
- Interpolaciones como placeholders tipados (`{name}`, `{count}`).
- El formato de duración/tamaño (`fmtDuration`, `fmtSize`) NO se localiza en
  esta tanda: es numérico y ya usa coma decimal española; el inglés tolera la
  coma peor pero no es un error de lectura. Se anota como deuda.
- La regla «video, nunca vídeo» sigue vigente en `app_es.arb`.

## 3. Selección de idioma

- Sigue al del sistema por defecto.
- `KivoSettings.locale`: `'system' | 'es' | 'en'`, persistido por nombre.
- Selector en Ajustes → General: «Idioma» con «Sistema · Español · English».
- `MaterialApp.locale` lo lee; `supportedLocales` = `[es, en]`;
  `localizationsDelegates` = los generados + los de Material/Cupertino/Widgets.

## 4. Lo que no es solo Dart

- Los 30 textos de Android van a `res/values/strings.xml` (inglés) y
  `res/values-es/strings.xml`. Lo que hoy se pasa desde Dart al plugin (los
  mensajes del diálogo de huella) cae en el ARB, no en XML.
- Los `KV-nnn` se traducen donde ya dice la regla del proyecto: en el
  adaptador que los muestra (`showFailureSnackBar` y equivalentes), no en el
  catálogo. El catálogo conserva el código y el detalle crudo.
- Notas de la release y el updater: el cuerpo viene de GitHub tal cual; solo
  se localizan los rótulos del diálogo.

## 5. Tests

- Nunca `find.text('Borrar')`. Dos vías: la clave a través de un
  `AppLocalizations` cargado en el test (`l10n.delete`), o una `Key` cuando la
  fila es una acción.
- Helper único `test/helpers/pump_app.dart`: `pumpLocalized(tester, child,
  {locale, container})` que monta `MaterialApp` con los delegados. Los ~90
  tests que montan `MaterialApp(` a mano migran a él en la tanda de su
  pantalla.
- Un test de contrato: cada clave de `app_es.arb` existe en `app_en.arb` con
  los mismos placeholders (falla la build si una traducción se queda atrás).
- Un test de barrido: `lib/ui` no contiene literales con mayúscula inicial
  fuera de la lista blanca (nombres propios: «Kivo», «Vault», «Android»).

## 6. Orden de trabajo

Tandas secuenciales (los ARB son un archivo compartido; en paralelo se pisan).
Cada tanda deja la app **bilingüe y en verde**; no hay estado medio traducido
en master.

0. Fundación: deps, `l10n.yaml`, ARB vacíos + `l10n.dart`, `KivoSettings.
   locale`, `MaterialApp` cableado, selector en General, `pumpLocalized`,
   test de contrato, test de barrido (aún con lista de excepciones larga).
1. Biblioteca: `lib/ui/home/**` (pantalla, chips, hojas, selección, listas).
2. Reproductor: `lib/ui/player/**` (menú, HUD, capítulos, marcadores, sync,
   temporizador, autoplay, tutorial).
3. Ajustes: `lib/ui/settings/**` y `lib/ui/update/**`.
4. Vault, mini-player, errores (`lib/ui/vault/**`, `lib/ui/mini_player/**`,
   adaptadores `KV-nnn`), y `lib/core`/`lib/player` restantes.
5. Android `strings.xml`, revisión de rama, barrido a cero excepciones.

## 7. Fuera de esta tanda

- Formato numérico/fecha por locale.
- Idiomas más allá de en/es.
- RTL.
- Traducir el cuerpo de las notas de release.

## 8. Archivos

Nuevos: `l10n.yaml`, `lib/l10n/app_es.arb`, `lib/l10n/app_en.arb`,
`lib/l10n/l10n.dart`, `lib/l10n/generated/*`, `test/helpers/pump_app.dart`,
`test/l10n/arb_contract_test.dart`, `test/l10n/no_hardcoded_strings_test.dart`,
`android/app/src/main/res/values-es/strings.xml`.
Modificados: `pubspec.yaml`, `lib/app.dart`, `lib/core/settings/kivo_settings.dart`,
`lib/ui/settings/sections/general_section.dart`, y progresivamente todo `lib/ui`.
