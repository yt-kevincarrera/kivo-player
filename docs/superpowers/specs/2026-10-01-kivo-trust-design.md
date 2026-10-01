# Kivo confianza (tanda 4) — Design

**Date:** 2026-10-01
**Status:** Implemented under the standing autonomy for every tanda. The one
user-owned call — the Vault — was asked: "Honesto + PIN reforzado".

## 1. Vault: honest, with a harder PIN

The Vault hides files (rename into `/sdcard/.KivoVault` + MediaStore row
removed); it does not encrypt them. Encrypting was offered and declined
(minutes per large video, battery, risk of a half-written file).

- **Said plainly** where it matters: under the keypad when the PIN is
  created, in the empty Vault, and in the Ajustes row ("ocultos de la galería
  · sin cifrar").
- **PIN derivation:** PBKDF2-HMAC-SHA256, 100 000 iterations, 16-byte random
  salt, computed with `Isolate.run` (inline under `flutter test`, where a real
  isolate never resolves inside the fake clock). Checked against the published
  PBKDF2-HMAC-SHA256 vectors (c = 1, 2, 4096). Constant-time compare.
- **Migration:** a record without `kdf` is the old salted SHA-256; it still
  opens, and the first correct entry re-derives it with PBKDF2. A wrong entry
  never touches it.
- **Lockout:** misses 1–4 free; the 5th locks 30 s, each further miss doubles
  it, capped at 1 h. Stored with the credentials, so killing the app does not
  reset it; a fingerprint unlock ends the streak. The gate shows a live
  countdown, also when reopened mid-lock.
- Threat model, unchanged and now written down in `VaultAuth`: someone with
  the phone in hand. A 4–6 digit PIN cannot resist an offline attack on a copy
  of the app's data whatever the hash.

## 2. Reportar un problema

Ajustes › Acerca de › Reportar un problema: a description field, then the
whole report as it will be sent (version, Android SDK, device, locale, every
error-log entry with code, operation, time and detail). Nothing is sent by
Kivo: the user picks **Enviar por correo** (`mailto:` the About address),
**Abrir en GitHub** (prefilled new issue; body cut at 6 000 chars) or
**Copiar**. The report text is English on purpose (read by the developer,
language-neutral codes).

## 3. Privacy and licenses

- **Privacidad** page: no ads/trackers/accounts; the only network use is the
  update check/download on GitHub (once a day if automatic, or on demand);
  the error log leaves only through the report; no cloud backup; what each
  permission is for.
- To make "no cloud backup" true: `android:allowBackup="false"`,
  `fullBackupContent="false"` and `data_extraction_rules.xml` excluding every
  domain from cloud backup and device transfer (Android otherwise copied
  settings, history and Vault metadata to the user's Google account). Kivo's
  own Ajustes › Copia de seguridad remains the way to move to another phone.
- **Licencias**: `showLicensePage` plus the native stack Flutter does not
  know about — mpv (LGPL-2.1+, built `-Dgpl=false`), FFmpeg 6.0 (LGPL-2.1+,
  `--disable-gpl`), libass, FreeType, HarfBuzz, FriBidi, dav1d, Mbed TLS,
  libxml2 (versions from the libmpv build's `depinfo.sh`) and juniversalchardet
  (MPL-1.1) — each with its source and a link to the full license text, plus
  the build repository for the LGPL source offer.

## Testing

PBKDF2 vectors; legacy open + upgrade; no upgrade on a miss; lockout timing,
persistence and biometric reset; gate notice + countdown; report contents,
live description, mailto/GitHub URLs; privacy page; native licenses registered.

## Also in this release (user requests, subtitles)

- Estilo tab regrouped (Texto · Contorno y sombra · Fondo · Posición ·
  Archivos .ass) with the preview pinned above the scrolling options, so it
  never scrolls away while something is being adjusted.
- Press and hold a subtitle line on the video to move it: pauses if playing,
  resumes on release, paused stays paused; framed with its percentage while
  held; saved on release. The subtitle layer takes no touches — the player's
  gestures start the move when a long press lands on a line
  (`SubtitleHitTargets`), so double-tap, swipes and pinch keep working over
  the text. A gesture torn down mid-move saves and resumes.

## Branch review (applied)

- Vault upgrade reuses the salt; the store writes hash/salt/scheme in one
  Hive batch; `verify` checks both schemes before counting a miss — a crash
  mid-upgrade can no longer lock the owner out.
- `lockFor` caps at 1 h from 12 misses (pow() overflowed to "no lock" at 64);
  the remaining lock is capped at what the streak earned (clock moved back).
  A clock moved forward still shortens it — the accepted limit of persisting
  wall-clock time.
- PIN setup guarded against a second entry; the pad shows it is busy.
- `openUrl` returns whether anything opened, so "no app to open it" shows.
- Privacy lists the fingerprint; GitHub issues are flagged as public; the
  issue URL is cut by encoded length.
