import 'package:flutter/material.dart';
import 'settings_screen.dart';

Route<T> settingsRoute<T>() =>
    MaterialPageRoute<T>(builder: (_) => const SettingsScreen());
