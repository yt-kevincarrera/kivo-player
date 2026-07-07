import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/all_files_access.dart';

final allFilesAccessProvider = Provider<AllFilesAccess>((ref) {
  throw UnimplementedError('allFilesAccessProvider must be overridden');
});

/// Current grant status for the Settings row; autoDispose so re-entering the
/// screen re-queries, and `ref.invalidate` refreshes it after returning from
/// the system settings screen.
final allFilesAccessGrantedProvider = FutureProvider.autoDispose<bool>(
    (ref) => ref.read(allFilesAccessProvider).isGranted());
