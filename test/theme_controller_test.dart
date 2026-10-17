import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installs follow the device theme', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    final controller = ThemeController(storageService: storage);
    await controller.initialize();
    expect(controller.themeMode, ThemeMode.system);
    controller.dispose();
  });

  test(
    'existing themes are retained and follow-device choice is persisted',
    () async {
      SharedPreferences.setMockInitialValues({'reader_theme_mode': 'dark'});
      final storage = StorageService();
      await storage.initialize();
      final controller = ThemeController(storageService: storage);
      await controller.initialize();
      expect(controller.themeMode, ThemeMode.dark);
      await controller.setThemeMode(ThemeMode.system);
      expect(storage.themeMode, 'system');
      final restored = ThemeController(storageService: storage);
      await restored.initialize();
      expect(restored.themeMode, ThemeMode.system);
      restored.dispose();
      controller.dispose();
    },
  );
}
