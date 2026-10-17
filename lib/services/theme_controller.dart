import 'package:flutter/material.dart';

import 'storage_service.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({required StorageService storageService})
    : _storageService = storageService;

  final StorageService _storageService;

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
  bool get isLightMode => _themeMode == ThemeMode.light;

  Future<void> initialize() async {
    final storedMode = _storageService.themeMode;
    _themeMode = switch (storedMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    await _storageService.saveThemeMode(mode.name);
    notifyListeners();
  }
}
