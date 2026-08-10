import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_log.dart';

final errorLogProvider = Provider<ErrorLog>((ref) {
  throw UnimplementedError('errorLogProvider must be overridden');
});
