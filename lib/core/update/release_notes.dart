/// Trims a GitHub release body down to the part a user in a dialog cares about.
///
/// The update dialog shows this text, and a link is useless there — nobody
/// taps a URL out of a modal to find out what changed. Releases published
/// before the workflow started writing real notes contain *nothing but* the
/// compare link, and those should read as "no notes" rather than as a stray
/// URL, so the dialog falls back to its own sentence.
String cleanReleaseNotes(String body) {
  final kept = <String>[];

  for (final raw in body.split('\n')) {
    final line = raw.trimRight();
    final trimmed = line.trim();

    // The compare footer, in any of the shapes GitHub emits for it.
    if (trimmed.startsWith('**Full Changelog**') ||
        trimmed.startsWith('Full Changelog:')) {
      continue;
    }
    // A markdown heading: the dialog already says which version this is.
    if (trimmed.startsWith('#')) continue;
    // A line that is only a URL. One inside a sentence stays — dropping the
    // line would take the sentence with it.
    if (trimmed.startsWith('http') && !trimmed.contains(' ')) continue;

    kept.add(line);
  }

  // Collapse the blank runs the removals leave behind.
  final out = <String>[];
  for (final line in kept) {
    if (line.trim().isEmpty && (out.isEmpty || out.last.trim().isEmpty)) {
      continue;
    }
    out.add(line);
  }

  return out.join('\n').trim();
}
