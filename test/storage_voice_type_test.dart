import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialize();
  });

  test('voice labels persist by exact engine, ID, and language', () async {
    await storage.saveVoiceTypeLabel('engine.one', 'voice', 'en-IN', 'Male');
    final reopened = StorageService();
    await reopened.initialize();
    expect(reopened.voiceTypeLabel('engine.one', 'voice', 'en-IN'), 'Male');
    expect(reopened.voiceTypeLabel('engine.two', 'voice', 'en-IN'), isNull);
    expect(reopened.voiceTypeLabel('engine.one', 'other', 'en-IN'), isNull);
    expect(reopened.voiceTypeLabel('engine.one', 'voice', 'hi-IN'), isNull);
  });

  test('provider reset removes only the selected personal label', () async {
    await storage.saveVoiceTypeLabel('engine.one', 'voice', 'en', 'Female');
    await storage.saveVoiceTypeLabel('engine.one', 'other', 'en', 'Child');
    await storage.saveVoiceTypeLabel('engine.one', 'voice', 'en', null);
    expect(storage.voiceTypeLabel('engine.one', 'voice', 'en'), isNull);
    expect(storage.voiceTypeLabel('engine.one', 'other', 'en'), 'Child');
  });

  test('invalid labels and missing identities are rejected', () async {
    await expectLater(
      storage.saveVoiceTypeLabel('engine', 'voice', 'en', 'Guess'),
      throwsArgumentError,
    );
    await expectLater(
      storage.saveVoiceTypeLabel('', 'voice', 'en', 'Male'),
      throwsArgumentError,
    );
  });

  test('stored invalid data is ignored', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'reader_voice_type_${jsonEncode(['engine', 'voice', 'en'])}',
      'Guess',
    );
    expect(storage.voiceTypeLabel('engine', 'voice', 'en'), isNull);
    await prefs.setInt(
      'reader_voice_type_${jsonEncode(['engine', 'voice', 'en'])}',
      1,
    );
    expect(storage.voiceTypeLabel('engine', 'voice', 'en'), isNull);
  });
}
