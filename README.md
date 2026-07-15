<div align="center">

<img src="assets/kivo-logo.svg" width="110" alt="Kivo logo" />

# Kivo

**A modern, high-performance local video player for Android.**
No ads. No tracking. No cloud. Just your videos — played beautifully.

[![Latest release](https://img.shields.io/github/v/release/yt-kevincarrera/kivo-player?label=download&color=E8B84B)](https://github.com/yt-kevincarrera/kivo-player/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84)](https://github.com/yt-kevincarrera/kivo-player/releases/latest)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/github/license/yt-kevincarrera/kivo-player?color=blue)](LICENSE)

</div>

---

Kivo is a local-only video player built to replace the ad-ridden, bloated players on the Play Store. It plays what's on your device — that's it — with a fast, gesture-driven interface where **almost everything is configurable** and a single accent color (gold by default) themes the whole app.

Powered by **[media_kit](https://github.com/media-kit/media-kit) (libmpv)**, so it plays practically any format or codec you throw at it.

## ✨ Features

### Playback
- 🎬 **Plays almost anything** — libmpv under the hood (MKV, MP4, AVI, HEVC, and more).
- 👆 **Gesture controls** — double-tap to skip, hold to fast-forward with a speed ladder, vertical swipes for brightness & volume, horizontal swipe to seek with a **live frame preview**.
- ⚡ **Speed control** — fine-grained speed panel and quick presets.
- ▶️ **Resume where you left off**, autoplay-next through your list, and a PotPlayer-style info overlay.
- 🔊 **Volume boost** past 100% with a clear on-screen wall at the boundary.

### Tracks & subtitles
- 🎧 **Audio & subtitle track selection**, embedded and external.
- 🌐 **Preferred-language defaults** — auto-pick your language on open, and find matching external subtitle files next to the video.
- 🎨 **Subtitle styling** — font size, text color, and background, with a live preview.

### Beyond the basics
- 🖼️ **Picture-in-Picture** and **background playback** (with an audio-only mode + media-notification controls).
- ⏱️ **Sleep timer** (additive extend, or "stop after N episodes") and **A–B loop**.
- 🔒 **Vault** — hide private videos behind a PIN or fingerprint; the entrance itself can be hidden.

### Library
- 📁 **Auto-indexed library** with folders, search, sorting, thumbnails, and adjustable grid density.
- 🕘 **Continue watching** row and "new" badges.
- 🗂️ **File operations** — rename, delete, share, and details, with **multi-select** batch actions (silent, once you grant all-files access).

### Design
- 🎨 **One configurable accent color** themes the entire app (gold by default).
- 🌗 Light / dark / system themes.
- 🛠️ **Deeply configurable** — a full settings panel exposes gestures, sensitivities, playback behavior, and interface options.

## 📥 Download

Grab the latest APK from the **[Releases page](https://github.com/yt-kevincarrera/kivo-player/releases/latest)**:

| APK | For |
| --- | --- |
| `kivo-*-arm64-v8a.apk` | Most modern phones **(recommended)** |
| `kivo-*-armeabi-v7a.apk` | Older 32-bit devices |
| `kivo-*-x86_64.apk` | Emulators / Chromebooks |

Install the APK directly (you may need to allow *"install from unknown sources"*).

## 🛠️ Build from source

```bash
git clone https://github.com/yt-kevincarrera/kivo-player.git
cd kivo-player
flutter pub get
flutter run --release          # run on a connected device
# or build the APKs:
flutter build apk --release --split-per-abi
```

Requirements: **Flutter 3.41+** (Dart 3.11+), Android SDK, JDK 17.

> Tip: run in `--release` — debug builds are noticeably janky for video.

### Releasing a new version

1. Bump `version:` in `pubspec.yaml` (semver, e.g. `1.0.1+2`).
2. Commit, then tag and push: `git tag v1.0.1 && git push origin master --tags`.
3. CI (`.github/workflows/release.yml`) builds the split APKs and publishes the GitHub Release automatically.

In-app, users on an older version get an update prompt — automatically on launch (at most once a day, toggleable) or on demand via **Settings › Acerca de → "Buscar actualizaciones"**. The version shown there is the real build version, so it always matches the tag.

## 🧱 Tech & architecture

- **Flutter** (Android-first; a clean platform-boundary keeps iOS on the table).
- **[media_kit](https://github.com/media-kit/media-kit) / libmpv** as the playback engine, behind a `PlaybackEngine` interface.
- **Riverpod** for state (granular rebuilds, composable settings).
- **Hive** for local persistence (settings, resume points, vault).
- Native Android integration for MediaStore, a foreground-service media session, PiP, and file operations.

The codebase favors small, focused units and keeps platform-specific code behind interfaces, so the core logic stays testable and portable.

## 📄 License

Released under the [MIT License](LICENSE).

---

<div align="center">
Made with care for people who just want to watch their videos in peace.
</div>
