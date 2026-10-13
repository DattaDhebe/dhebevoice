import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/main.dart';
import 'package:text_reader_app/services/audio_handler_controller.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/novel_import_controller.dart';
import 'package:text_reader_app/services/novel_library_service.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/theme_controller.dart';
import 'package:text_reader_app/services/tts_service.dart';
import 'package:text_reader_app/services/web_novel_import_service.dart';

void main() {
  testWidgets(
    'reader renders before voice initialization and shows startup errors',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reader_home_guide_seen': true});
      ReceiveSharingIntent.setMockValues(
        initialMedia: [],
        mediaStream: const Stream.empty(),
      );
      final storage = StorageService();
      await storage.initialize();
      final theme = ThemeController(storageService: storage);
      await theme.initialize();
      final tts = TtsService(
        storageService: storage,
        fileImportService: FileImportService(),
      );
      final audio = AudioHandlerController();
      final importer = NovelImportController(
        storageService: storage,
        fileImportService: FileImportService(),
        novelLibraryService: NovelLibraryService(),
        webNovelImportService: WebNovelImportService(),
        ttsService: tts,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (_) async => 1,
      );
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TextReaderApp(
          storageService: storage,
          themeController: theme,
          ttsService: tts,
          novelImportController: importer,
          audioHandlerController: audio,
        ),
      );
      await tester.pump();
      expect(find.text('DhebeVoice'), findsOneWidget);
      expect(find.text('Reading content'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      audio.reportError('Playback controls could not start.');
      await tester.pump();
      expect(find.text('Playback controls could not start.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      importer.dispose();
      tts.dispose();
      audio.dispose();
      theme.dispose();
      await tester.pump();
    },
  );
}
