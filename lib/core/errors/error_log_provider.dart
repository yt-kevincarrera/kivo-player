import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_log.dart';

/// Overridden in `main()` with a Hive-backed store and the real device context.
///
/// Unlike the platform providers, this one has a working default rather than
/// throwing: recording a failure must never be the thing that breaks a code
/// path, and a session-only log is a perfectly valid log. Making it mandatory
/// turned "forgot the override" into "playback crashes", which is exactly the
/// class of problem this whole feature exists to remove.
final errorLogProvider = Provider<ErrorLog>((ref) => ErrorLog(
      InMemoryErrorLogStore(),
      appVersion: '',
      androidSdk: 0,
    ));
