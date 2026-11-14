import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'android/android_storage_browser.dart';
import 'interfaces/storage_browser.dart';

final storageBrowserProvider = Provider<StorageBrowser>(
  (ref) => AndroidStorageBrowser(),
);

final storageChangesProvider = StreamProvider<Object?>(
  (ref) => const EventChannel('kivo/storage_events').receiveBroadcastStream(),
);
