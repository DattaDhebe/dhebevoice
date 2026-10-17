import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/models/voice_model.dart';
import 'package:text_reader_app/services/audio_handler_controller.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/tts_service.dart';
import 'package:text_reader_app/widgets/player_controls.dart';
import 'package:text_reader_app/widgets/speech_preparation.dart';

class PreparingReader extends TtsService {
  PreparingReader(StorageService storage)
    : super(storageService: storage, fileImportService: FileImportService());
  bool buffering = false;
  bool stopped = false;
  int sequence = 0;
  double? progress;
  bool newVoice = false;
  @override
  bool get isBuffering => buffering;
  @override
  int get preparationSequence => sequence;
  @override
  String get preparationTitle =>
      newVoice ? 'Preparing selected voice' : 'Preparing speech';
  @override
  String get preparationMessage =>
      progress == null ? 'Loading neural voice model' : 'Refining voice';
  @override
  double? get preparationProgress => progress;
  @override
  String? get preparationStages =>
      progress == null ? null : '2 of 7 preparation steps';
  @override
  VoiceModel? get selectedVoice => const VoiceModel(
    name: 'M3',
    locale: 'en',
    label: 'Supertonic Male 3',
    personaLabel: 'Male',
  );
  @override
  Future<void> stop({
    bool preserveSleepTimer = false,
    bool keepAudioSession = false,
  }) async {
    stopped = true;
    finish();
  }

  void begin() {
    buffering = true;
    sequence++;
    notifyListeners();
  }

  void updateProgress() {
    progress = 2 / 7;
    notifyListeners();
  }

  void finish() {
    buffering = false;
    notifyListeners();
  }
}

void main() {
  late PreparingReader service;
  late AudioHandlerController audio;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    service = PreparingReader(storage);
    audio = AudioHandlerController();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  Future<void> open(WidgetTester tester) => tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TtsService>.value(value: service),
        ChangeNotifierProvider<AudioHandlerController>.value(value: audio),
      ],
      child: const MaterialApp(
        home: SpeechPreparationCoordinator(
          child: Scaffold(body: Text('Reader')),
        ),
      ),
    ),
  );

  Future<void> showProgress(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 701));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    audio.dispose();
    await tester.pump();
  }

  testWidgets('quick preparation never flashes a popup', (tester) async {
    await open(tester);
    service.begin();
    await tester.pump(const Duration(milliseconds: 200));
    service.finish();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SpeechPreparationDialog), findsNothing);
    await cleanup(tester);
  });

  testWidgets(
    'progress does not reset the popup delay and Hide never stops speech',
    (tester) async {
      await open(tester);
      service.begin();
      await tester.pump(const Duration(milliseconds: 400));
      service.updateProgress();
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SpeechPreparationDialog), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        2 / 7,
      );
      expect(find.text('2 of 7 preparation steps'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide preparation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.stopped, isFalse);
      service.updateProgress();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SpeechPreparationDialog), findsNothing);
      service.begin();
      await showProgress(tester);
      expect(find.byType(SpeechPreparationDialog), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(service.stopped, isTrue);
      expect(find.byType(SpeechPreparationDialog), findsNothing);
      await cleanup(tester);
    },
  );

  testWidgets(
    'audio start removes only its preparation route, not another popup',
    (tester) async {
      await open(tester);
      service.begin();
      await showProgress(tester);
      final context = tester.element(find.byType(SpeechPreparationDialog));
      Navigator.of(context).push(
        DialogRoute<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Another popup')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      service.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Another popup'), findsOneWidget);
      expect(find.byType(SpeechPreparationDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
    },
  );

  testWidgets('background preparation does not open a modal until resumed', (
    tester,
  ) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    service.begin();
    await showProgress(tester);
    expect(find.byType(SpeechPreparationDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await showProgress(tester);
    expect(find.byType(SpeechPreparationDialog), findsOneWidget);
    service.finish();
    await tester.pumpAndSettle();
    expect(find.byType(SpeechPreparationDialog), findsNothing);
    await cleanup(tester);
  });

  testWidgets(
    'preparation dialog fits large text with keyboard and Stop stays enabled',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      service.newVoice = true;
      service.begin();
      await showProgress(tester);
      expect(find.text('Stop').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester);
      var stopped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              isPlaying: true,
              canResume: false,
              enabled: false,
              stopEnabled: true,
              onPlay: () {},
              onPause: () {},
              onStop: () => stopped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Stop'));
      expect(stopped, isTrue);
    },
  );
}
