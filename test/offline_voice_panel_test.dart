import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/offline_model_store.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/tts_service.dart';
import 'package:text_reader_app/widgets/offline_voice_panel.dart';

class _InstalledModels extends OfflineModelStore {
  _InstalledModels() : super(directory: Directory('unused-test-models')) {
    ready = true;
  }

  @override
  Future<void> initialize() async {}
}

class _NeuralSettings extends TtsService {
  _NeuralSettings(StorageService storage)
    : super(
        storageService: storage,
        fileImportService: FileImportService(),
        modelStore: _InstalledModels(),
      );

  @override
  bool get usesOfflineVoice => true;
}

void main() {
  testWidgets(
    'background preparation is default and whole-chapter waiting stays optional',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reader_neural_steps': 3});
      final storage = StorageService();
      await storage.initialize();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (_) async => 1,
      );
      final service = _NeuralSettings(storage);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<TtsService>.value(
          value: service,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: OfflineVoicePanel(service: service),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(service.neuralSteps, 5);
      expect(storage.neuralSteps, 5);
      expect(find.text('Faster (3 steps)'), findsNothing);
      expect(service.prepareNeuralChapter, isFalse);
      expect(storage.prepareNeuralChapter, isFalse);
      await tester.ensureVisible(find.byType(Switch).last);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(service.prepareNeuralChapter, isTrue);
      expect(storage.prepareNeuralChapter, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      await tester.pump();
    },
  );
}
