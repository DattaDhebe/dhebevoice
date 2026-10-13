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

class ProgressImporter extends NovelImportController {
  ProgressImporter({required super.storageService, required super.ttsService})
    : super(
        fileImportService: FileImportService(),
        novelLibraryService: NovelLibraryService(),
        webNovelImportService: WebNovelImportService(),
      );
  bool running = false;
  bool stopped = false;
  @override
  bool get isImporting => running;
  @override
  String? get importStatus =>
      running ? 'Downloading Chapter 102 - ${'A long title ' * 70}' : null;
  @override
  double? get importProgress => running ? 0.5 : null;
  @override
  Future<void> cancelImport() async {
    stopped = true;
    running = false;
    notifyListeners();
  }
}

void main() {
  testWidgets('long import progress scrolls and Close does not stop import', (
    tester,
  ) async {
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
    final importer = ProgressImporter(storageService: storage, ttsService: tts);
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
    importer.running = true;
    importer.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Stop import'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);
    expect(importer.running, isTrue);
    expect(importer.stopped, isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
    navigator.push(
      DialogRoute<void>(
        context: tester.element(find.byType(AlertDialog)),
        builder: (_) => const AlertDialog(title: Text('Another dialog')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await importer.cancelImport();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Another dialog'), findsOneWidget);
    expect(find.text('Importing content'), findsNothing);
    expect(tester.takeException(), isNull);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    importer.dispose();
    tts.dispose();
    audio.dispose();
    theme.dispose();
    await tester.pump();
  });

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
