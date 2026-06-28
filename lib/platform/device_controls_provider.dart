import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/device_controls.dart';
import 'android/android_device_controls.dart';

final deviceControlsProvider = Provider<DeviceControls>((ref) => deviceControls);
