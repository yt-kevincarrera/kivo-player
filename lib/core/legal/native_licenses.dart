import 'package:flutter/foundation.dart';

/// The native code inside the APK that Flutter's own license list does not
/// know about: the libmpv build media_kit ships (media-kit/libmpv-android-
/// video-build, "default" flavour — mpv built with -Dgpl=false, FFmpeg with
/// --disable-gpl, so the whole stack is LGPL-compatible) and the charset
/// detector used for subtitles. Versions are that build's
/// `buildscripts/include/depinfo.sh`.
///
/// LGPL components are dynamically linked (libmpv.so); their source, and the
/// scripts that build this exact binary, are at [_buildSource].
const _buildSource =
    'https://github.com/media-kit/libmpv-android-video-build';

class NativeLicense {
  const NativeLicense(this.name, this.license, this.url, {this.note});
  final String name;
  final String license;
  final String url;
  final String? note;

  String get text => [
        '$name — $license',
        'Source: $url',
        if (note != null) note!,
        'Full license text: https://spdx.org/licenses/$license.html',
      ].join('\n\n');
}

const nativeLicenses = <NativeLicense>[
  NativeLicense('mpv (libmpv)', 'LGPL-2.1-or-later',
      'https://github.com/mpv-player/mpv',
      note: 'Built from commit 78d43740 by $_buildSource with -Dgpl=false.'),
  NativeLicense('FFmpeg 6.0', 'LGPL-2.1-or-later', 'https://ffmpeg.org',
      note: 'Built by $_buildSource with --disable-gpl --disable-nonfree.'),
  NativeLicense('libass 0.17.1', 'ISC', 'https://github.com/libass/libass'),
  NativeLicense('FreeType 2.13.0', 'FTL', 'https://freetype.org',
      note: 'Portions of this software are copyright © The FreeType Project '
          '(www.freetype.org). All rights reserved.'),
  NativeLicense('HarfBuzz 7.2.0', 'MIT-Modern-Variant',
      'https://github.com/harfbuzz/harfbuzz'),
  NativeLicense('GNU FriBidi 1.0.12', 'LGPL-2.1-or-later',
      'https://github.com/fribidi/fribidi'),
  NativeLicense('dav1d 1.2.0', 'BSD-2-Clause', 'https://code.videolan.org/videolan/dav1d'),
  NativeLicense('Mbed TLS 3.4.0', 'Apache-2.0', 'https://github.com/Mbed-TLS/mbedtls'),
  NativeLicense('libxml2 2.10.3', 'MIT', 'https://gitlab.gnome.org/GNOME/libxml2'),
  NativeLicense('juniversalchardet 2.5.0', 'MPL-1.1',
      'https://github.com/albfernandez/juniversalchardet',
      note: 'Used to detect the encoding of external subtitle files.'),
];

/// Adds [nativeLicenses] to the app's license page (showLicensePage).
void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final l in nativeLicenses) {
      yield LicenseEntryWithLineBreaks([l.name], l.text);
    }
  });
}
