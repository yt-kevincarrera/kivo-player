import 'dart:convert';
import 'package:crypto/crypto.dart';

/// A location identity, not a title. Including the name and relative path
/// distinguishes filenames across locations and guards the URI fallback
/// against row IDs reused with different metadata. Kivo migrates renames.
String videoIdentity(String source, String name, {String path = ''}) =>
    'video:v2:${sha256.convert(utf8.encode(jsonEncode([source, name, path])))}';

bool isVideoIdentity(String key) => key.startsWith('video:v2:');

/// Ambiguous legacy records remain in the stores and backups, but are never
/// guessed onto one of several same-named videos, even after one disappears.
String legacyVideoIdentity(String name) =>
    'legacy:v1:${sha256.convert(utf8.encode(name))}';
