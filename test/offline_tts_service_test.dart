import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/models/voice_model.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/offline_model_store.dart';
import 'package:text_reader_app/services/offline_speech_engine.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/tts_service.dart';

class TestableNeuralTts extends TtsService {
  TestableNeuralTts({
    required super.storageService,
    required super.modelStore,
    required super.offlineEngine,
    required super.flutterTts,
  }) : super(fileImportService: FileImportService());
  @override
  bool get supportsOfflineVoice => true;
}

class DelayedPositionStorage extends StorageService {
  Completer<void>? positionWrite;

  @override
  Future<void> savePosition(int value) async {
    await super.savePosition(value);
    await positionWrite?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel('test/native_neural');
  const android = MethodChannel('flutter_tts');
  const audio = MethodChannel('com.ryanheise.audio_session');
  late DelayedPositionStorage storage;
  late TestableNeuralTts service;
  late FlutterTts androidTts;
  late List<MethodCall> calls;
  var chapterCompletions = 0;

  Future<void> event(
    String type, [
    int? id,
    Map<String, Object?> extra = const {},
  ]) async {
    final latestId = calls
        .lastWhere((c) => c.method == 'speak' || c.method == 'prepareChapter')
        .arguments['id'];
    final result = Completer<void>();
    messenger.handlePlatformMessage(
      native.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'id': id ?? latestId, 'type': type, ...extra}),
      ),
      (_) => result.complete(),
    );
    await result.future;
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    storage = DelayedPositionStorage();
    await storage.initialize();
    calls = [];
    chapterCompletions = 0;
    messenger.setMockMethodCallHandler(audio, (_) async => null);
    messenger.setMockMethodCallHandler(
      android,
      (call) async => call.method == 'getVoices'
          ? [
              {
                'name': 'en-in-x-ene-local',
                'locale': 'en-IN',
                'quality': 'high',
                'network_required': '0',
              },
            ]
          : 1,
    );
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return ['speak', 'resume', 'prepareChapter'].contains(call.method)
          ? true
          : null;
    });
    androidTts = FlutterTts();
    service = TestableNeuralTts(
      storageService: storage,
      flutterTts: androidTts,
      modelStore: OfflineModelStore(directory: Directory('unused-test-models'))
        ..ready = true,
      offlineEngine: OfflineSpeechEngine(channel: native),
    );
    await service.initialize();
    service.setPlaybackCompletedHandler(() async {
      chapterCompletions++;
    });
    await service.setOfflineVoiceEnabled(true);
  });
  tearDown(() async {
    service.dispose();
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(android, null);
    messenger.setMockMethodCallHandler(audio, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'neural completion advances paragraphs and calls chapter autoplay once',
    () async {
      await service.updateText('First paragraph.\n\nSecond paragraph.');
      await service.play();
      expect(
        calls.lastWhere((c) => c.method == 'speak').arguments['nextText'],
        'Second paragraph.',
      );
      await event('started');
      await event('completed');
      expect(calls.where((c) => c.method == 'speak').length, 2);
      expect(service.currentParagraphIndex, 1);
      expect(
        (calls.lastWhere((c) => c.method == 'speak').arguments as Map)
            .containsKey('nextText'),
        isFalse,
      );
      await event('started');
      await event('completed');
      await event('completed');
      expect(chapterCompletions, 1);
      expect(service.playbackState, ReaderPlaybackState.completed);
    },
  );

  test(
    'default starts with the first segment and prepares a rolling window without a chapter wait',
    () async {
      expect(service.prepareNeuralChapter, isFalse);
      expect(storage.prepareNeuralChapter, isFalse);
      await service.updateText(
        List.generate(14, (i) => 'Paragraph ${i + 1}.').join('\n\n'),
      );
      await service.play();
      expect(calls.where((call) => call.method == 'prepareChapter'), isEmpty);
      final first =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(first['text'], 'Paragraph 1.');
      expect(
        first['upcomingTexts'],
        List.generate(8, (i) => 'Paragraph ${i + 2}.'),
      );
      expect(first['steps'], 5);
      expect(first['speed'], 1);
      await event('started');
      await event('completed');
      final next =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(next['text'], 'Paragraph 2.');
      expect(
        next['upcomingTexts'],
        List.generate(8, (i) => 'Paragraph ${i + 3}.'),
      );
      expect(calls.where((call) => call.method == 'prepareChapter'), isEmpty);
    },
  );

  test(
    'rolling window is bounded by text size and a voice change updates the whole window only',
    () async {
      await service.updateText(
        List.generate(10, (i) => '${'A word ' * 34}$i.').join('\n\n'),
      );
      await service.play();
      final first =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      final window = (first['upcomingTexts'] as List).cast<String>();
      expect(window.length, lessThanOrEqualTo(8));
      expect(
        window.fold<int>(0, (sum, text) => sum + text.length),
        inInclusiveRange(900, 1200),
      );
      await event('started');
      final before = calls.length;
      await service.setLanguage('hi');
      final updates = calls.skip(before).toList();
      expect(updates.map((call) => call.method), ['preload']);
      expect(updates.single.arguments['upcomingTexts'], window);
      expect(updates.single.arguments['language'], 'hi');
      expect(service.isPlaying, isTrue);
      expect(service.speechRate, .48);
    },
  );

  test(
    'streaming prefetch never includes paragraphs outside a selected range',
    () async {
      await service.updateText('First.\n\nSecond.\n\nPrivate remainder.');
      await service.playSelection(
        const TextSelection(baseOffset: 0, extentOffset: 15),
      );
      final first =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(first['upcomingTexts'], ['Second.']);
      await service.setLanguage('hi');
      expect(
        calls
            .lastWhere((call) => call.method == 'preload')
            .arguments['upcomingTexts'],
        ['Second.'],
      );
    },
  );

  test('native pause/resume does not synthesize the segment again', () async {
    await service.updateText('A story in one paragraph.');
    await service.play();
    await event('started');
    await service.pause();
    expect(service.isPaused, isTrue);
    await service.play();
    await event('started');
    expect(service.isPlaying, isTrue);
    expect(calls.where((c) => c.method == 'speak').length, 1);
    expect(calls.where((c) => c.method == 'resume').length, 1);
  });

  test(
    'short-paragraph lookahead stays bounded and refreshes both future voices',
    () async {
      await service.updateText('First.\n\nShort.\n\nThird.\n\nFourth.');
      await service.play();
      final first =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(first['nextText'], 'Short.');
      expect(first['followingText'], 'Third.');
      await event('started');
      await service.setLanguage('hi');
      final preload =
          calls.lastWhere((call) => call.method == 'preload').arguments as Map;
      expect(preload['text'], 'Short.');
      expect(preload['nextText'], 'Third.');
      expect(preload['language'], 'hi');
      await event('completed');
      final next =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(next['text'], 'Short.');
      expect(next['nextText'], 'Third.');
      expect(next['followingText'], 'Fourth.');
      await event('started');
      await event('completed');
      final third =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(third['nextText'], 'Fourth.');
      expect(third.containsKey('followingText'), isFalse);
    },
  );

  test(
    'preparation remains buffering, changes voice at the boundary, and Stop wins',
    () async {
      await service.updateText('First paragraph.\n\nSecond paragraph.');
      await service.play();
      final firstSequence = service.preparationSequence;
      await event('preparing', null, {
        'message': 'Refining voice',
        'completed': 2,
        'total': 7,
      });
      expect(service.isPlaying, isTrue);
      expect(service.isBuffering, isTrue);
      expect(service.isPaused, isFalse);
      expect(service.preparationProgress, 2 / 7);
      await event('started');
      expect(service.preparationProgress, isNull);
      expect(service.isBuffering, isFalse);
      await service.setVoice(
        service.voices.firstWhere(
          (voice) => voice.name == 'M3' && voice.locale == 'en',
        ),
      );
      expect(service.isBuffering, isFalse);
      await event('completed');
      expect(service.preparationSequence, greaterThan(firstSequence));
      expect(service.preparationTitle, 'Preparing selected voice');
      expect(service.isBuffering, isTrue);
      final id =
          calls.lastWhere((call) => call.method == 'speak').arguments['id']
              as int;
      await service.stop();
      await event('preparing', id, {
        'message': 'Late result',
        'completed': 7,
        'total': 7,
      });
      expect(service.playbackStatusLabel, 'Stopped');
      expect(service.isBuffering, isFalse);
      expect(service.preparationProgress, isNull);
    },
  );

  test('slow position saves never hold up the next neural paragraph', () async {
    await service.updateText('First.\n\nSecond.\n\nThird.');
    await service.play();
    await event('started');
    final write = Completer<void>();
    storage.positionWrite = write;
    addTearDown(() {
      storage.positionWrite = null;
      if (!write.isCompleted) write.complete();
    });
    await event('completed');
    expect(calls.where((call) => call.method == 'speak').length, 2);
    expect(service.currentParagraphIndex, 1);
    await event('started');
    await event('completed');
    expect(calls.where((call) => call.method == 'speak').length, 3);
    expect(service.currentParagraphIndex, 2);
    expect(write.isCompleted, isFalse);
    write.complete();
    storage.positionWrite = null;
    await service.pause();
  });

  test(
    'experimental three-step mode is rejected without changing rate or playback',
    () async {
      expect(service.neuralSteps, 5);
      await service.updateText('First.\n\nSecond.');
      await service.play();
      await event('started');
      final start = calls.length;
      await expectLater(service.setNeuralSteps(3), throwsArgumentError);
      expect(service.isPlaying, isTrue);
      expect(storage.neuralSteps, 5);
      expect(service.speechRate, .48);
      expect(calls.skip(start), isEmpty);
      await event('completed');
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['steps'],
        5,
      );
      await service.pause();
      await service.setNeuralSteps(5);
      await service.play();
      expect(calls.where((call) => call.method == 'resume').length, 1);
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['steps'],
        5,
      );
      await expectLater(service.setNeuralSteps(0), throwsArgumentError);
      expect(service.neuralSteps, 5);
    },
  );

  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'continuous Quality waits for all remaining audio then never prepares between segments',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.\n\nThird.');
      final playing = service.play();
      await flush();
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
      final preparation =
          calls.lastWhere((call) => call.method == 'prepareChapter').arguments
              as Map;
      expect(preparation['texts'], ['First.', 'Second.', 'Third.']);
      expect(preparation['steps'], 5);
      expect(preparation['speed'], 1);
      expect(service.isBuffering, isTrue);
      await event('preparing', null, {
        'segmentsDone': 1,
        'segmentsTotal': 3,
        'completed': 2,
        'total': 9,
        'message': 'Refining voice',
      });
      expect(service.preparationProgress, closeTo((1 + 2 / 9) / 3, .001));
      expect(service.preparationStages, '1 of 3 speech segments ready');
      await event('chapterPrepared');
      await playing;
      await event('started');
      await event('completed');
      await event('started');
      await event('completed');
      expect(calls.where((call) => call.method == 'prepareChapter').length, 1);
      expect(calls.where((call) => call.method == 'speak').length, 3);
    },
  );

  test(
    'Stop during chapter preparation is immediate and late readiness cannot start audio',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.');
      final playing = service.play();
      await flush();
      final id =
          calls
                  .lastWhere((call) => call.method == 'prepareChapter')
                  .arguments['id']
              as int;
      await service.stop().timeout(const Duration(seconds: 1));
      await playing;
      await event('chapterPrepared', id);
      expect(service.isPlaying, isFalse);
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
      expect(chapterCompletions, 0);
    },
  );

  test(
    'voice changed during chapter preparation cancels obsolete work and restarts with latest voice',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.');
      final playing = service.play();
      await flush();
      final oldId =
          calls
                  .lastWhere((call) => call.method == 'prepareChapter')
                  .arguments['id']
              as int;
      await service.setVoice(
        service.voices.firstWhere((v) => v.name == 'M2' && v.locale == 'en'),
      );
      await flush();
      final latest =
          calls.lastWhere((call) => call.method == 'prepareChapter').arguments
              as Map;
      expect(latest['voice'], 'M2');
      expect(latest['id'], isNot(oldId));
      await event('chapterPrepared', oldId);
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
      await event('chapterPrepared');
      await playing;
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['voice'],
        'M2',
      );
    },
  );

  test(
    'voice changed while playing prepares only the remainder at the next boundary',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.\n\nThird.');
      final playing = service.play();
      await flush();
      await event('chapterPrepared');
      await playing;
      await event('started');
      final before = calls.length;
      await service.setLanguage('hi');
      expect(calls.skip(before), isEmpty);
      await event('completed');
      final remaining =
          calls.lastWhere((call) => call.method == 'prepareChapter').arguments
              as Map;
      expect(remaining['texts'], ['Second.', 'Third.']);
      expect(remaining['language'], 'hi');
      await event('chapterPrepared');
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['text'],
        'Second.',
      );
    },
  );

  test(
    'turning preparation off during generation resumes with streaming, not a playback error',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.');
      final playing = service.play();
      await flush();
      await service.setPrepareNeuralChapter(false);
      await playing;
      expect(service.errorMessage, isNull);
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['text'],
        'First.',
      );
    },
  );

  test(
    'Pause cancels chapter preparation and cannot autoplay after the user pauses',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.');
      final playing = service.play();
      await flush();
      final id =
          calls
                  .lastWhere((call) => call.method == 'prepareChapter')
                  .arguments['id']
              as int;
      await service.pause();
      await playing;
      await event('chapterPrepared', id);
      expect(service.isPaused, isTrue);
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
    },
  );

  test(
    'live language change retains the narrator and replaces lookahead only',
    () async {
      await service.setVoice(
        service.voices.firstWhere(
          (voice) => voice.name == 'M3' && voice.locale == 'en',
        ),
      );
      await service.updateText('First paragraph.\n\nSecond paragraph.');
      await service.play();
      await event('started');
      final start = calls.length;
      final session = service.playbackSessionId;
      await service.setLanguage('hi');
      expect(service.selectedVoice?.name, 'M3');
      expect(service.isPlaying, isTrue);
      expect(service.playbackSessionId, session);
      expect(
        calls
            .skip(start)
            .any(
              (call) =>
                  call.method == 'pause' ||
                  call.method == 'stop' ||
                  call.method == 'speak',
            ),
        isFalse,
      );
      final preload =
          calls.lastWhere((call) => call.method == 'preload').arguments as Map;
      expect(preload['text'], 'Second paragraph.');
      expect(preload['voice'], 'M3');
      expect(preload['language'], 'hi');
      await event('completed');
      final next =
          calls.lastWhere((call) => call.method == 'speak').arguments as Map;
      expect(next['text'], 'Second paragraph.');
      expect(next['voice'], 'M3');
      expect(next['language'], 'hi');
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'changing a paused neural voice regenerates instead of resuming the old narrator',
    () async {
      await service.updateText('Story.');
      await service.play();
      await event('started');
      await service.pause();
      await service.setVoice(
        service.voices.firstWhere(
          (voice) => voice.name == 'F2' && voice.locale == 'en',
        ),
      );
      expect(service.isPaused, isTrue);
      await service.play();
      expect(calls.where((call) => call.method == 'resume'), isEmpty);
      expect(calls.where((call) => call.method == 'speak').length, 2);
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['voice'],
        'F2',
      );
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'voice changes during generation do not cancel the current segment',
    () async {
      await service.updateText('First.\n\nSecond.');
      await service.play();
      final firstId =
          calls.lastWhere((call) => call.method == 'speak').arguments['id']
              as int;
      final start = calls.length;
      await service.setVoice(
        service.voices.firstWhere(
          (voice) => voice.name == 'M2' && voice.locale == 'en',
        ),
      );
      expect(
        calls
            .skip(start)
            .any((call) => call.method == 'stop' || call.method == 'pause'),
        isFalse,
      );
      await event('started', firstId);
      await event('completed', firstId);
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['voice'],
        'M2',
      );
      expect(service.isPlaying, isTrue);
    },
  );

  test('voice changes never prefetch outside selected text', () async {
    await service.updateText('Read this only.\n\nDo not read this.');
    await service.playSelection(
      const TextSelection(baseOffset: 0, extentOffset: 15),
    );
    await service.setLanguage('hi');
    expect(calls.where((call) => call.method == 'preload'), isEmpty);
    await event('started');
    await event('completed');
    expect(chapterCompletions, 0);
    expect(service.playbackState, ReaderPlaybackState.completed);
  });

  test(
    'rate changes refresh the next segment without stopping the current voice',
    () async {
      await service.updateText('First.\n\nSecond.');
      await service.play();
      await event('started');
      final start = calls.length;
      await service.setSpeechRate(.6);
      final preload =
          calls.lastWhere((call) => call.method == 'preload').arguments as Map;
      expect(preload['speed'], 1.25);
      expect(
        calls
            .skip(start)
            .any((call) => call.method == 'stop' || call.method == 'pause'),
        isFalse,
      );
      await event('completed');
      expect(
        calls.lastWhere((call) => call.method == 'speak').arguments['speed'],
        1.25,
      );
    },
  );

  test('Stop during generation prevents late playback and autoplay', () async {
    await service.updateText('First.\n\nSecond.');
    await service.play();
    await service.stop();
    await event('started');
    await event('completed');
    expect(service.playbackState, ReaderPlaybackState.stopped);
    expect(calls.where((c) => c.method == 'speak').length, 1);
    expect(chapterCompletions, 0);
  });

  test(
    'interrupted neural audio resumes the cache without regenerating',
    () async {
      await service.updateText('A story in one paragraph.');
      await service.play();
      await event('started');
      await service.handleAudioInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await service.handleAudioInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(calls.where((c) => c.method == 'speak').length, 1);
      expect(calls.where((c) => c.method == 'resume').length, 1);
      expect(service.isPlaying, isTrue);
      await event('started');
      expect(service.isBuffering, isFalse);
    },
  );

  test(
    'Bluetooth disconnect during neural preparation waits for manual Play',
    () async {
      await service.updateText('Story.');
      await service.play();
      expect(service.isBuffering, isTrue);
      await service.handleAudioBecomingNoisy();
      await event('started');
      expect(service.isPaused, isTrue);
      await service.handleAudioInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(calls.where((c) => c.method == 'resume'), isEmpty);
      await service.play();
      await event('started');
      expect(service.isPlaying, isTrue);
      expect(calls.where((c) => c.method == 'speak').length, 1);
    },
  );

  test(
    'rapid neural Pause, Play and Stop cannot revive cached audio',
    () async {
      await service.updateText('Story.');
      await service.play();
      await event('started');
      final pausing = service.pause();
      final playing = service.play();
      final stopping = service.stop();
      await pausing;
      await playing;
      await stopping;
      await event('started');
      await event('completed');
      expect(service.playbackState, ReaderPlaybackState.stopped);
      expect(chapterCompletions, 0);
    },
  );

  test('selected text does not pre-generate outside the selection', () async {
    await service.updateText('Read this only.\n\nDo not read this paragraph.');
    await service.playSelection(
      const TextSelection(baseOffset: 0, extentOffset: 15),
    );
    final arguments =
        calls.lastWhere((c) => c.method == 'speak').arguments as Map;
    expect(arguments['text'], 'Read this only.');
    expect(arguments.containsKey('nextText'), isFalse);
    expect(arguments.containsKey('followingText'), isFalse);
  });

  test('old Android callbacks cannot affect neural playback', () async {
    await service.updateText('First.\n\nSecond.');
    await service.play();
    androidTts.startHandler!();
    androidTts.completionHandler!();
    androidTts.errorHandler!('old engine');
    expect(service.isPlaying, isTrue);
    expect(service.currentParagraphIndex, 0);
    expect(service.errorMessage, isNull);
  });

  test(
    'prepared selection never generates text outside the selected range',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText(
        'Read this only.\n\nDo not generate this paragraph.',
      );
      final playing = service.playSelection(
        const TextSelection(baseOffset: 0, extentOffset: 15),
      );
      await flush();
      expect(
        calls
            .lastWhere((call) => call.method == 'prepareChapter')
            .arguments['texts'],
        ['Read this only.'],
      );
      await event('chapterPrepared');
      await playing;
      await event('started');
      await event('completed');
      expect(chapterCompletions, 0);
    },
  );

  test(
    'oversized chapter is rejected before crossing the native bridge',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText(List.filled(401, 'A.').join('\n\n'));
      await service.play();
      expect(service.errorMessage, contains('too large'));
      expect(
        calls.where(
          (call) => call.method == 'prepareChapter' || call.method == 'speak',
        ),
        isEmpty,
      );
    },
  );

  test(
    'native chapter preparation failure keeps its actionable error and never starts speech',
    () async {
      await service.setPrepareNeuralChapter(true);
      await service.updateText('First.\n\nSecond.');
      final playing = service.play();
      await flush();
      await event('error', null, {
        'message': 'Not enough storage. Turn off chapter preparation.',
      });
      await playing;
      expect(service.errorMessage, contains('Not enough storage'));
      expect(service.isPlaying, isFalse);
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
    },
  );

  test('switching engines preserves provider voice choice', () async {
    await service.setVoice(
      service.voices.firstWhere((v) => v.name == 'M3' && v.locale == 'en'),
    );
    await service.setOfflineVoiceEnabled(false);
    expect(service.selectedVoice?.name, 'en-in-x-ene-local');
    await service.setOfflineVoiceEnabled(true);
    expect(service.selectedVoice?.name, 'M3');
    expect(service.selectedLanguage, 'en');
  });

  test(
    'online speech requires explicit approval rather than automatic fallback',
    () async {
      await service.setOfflineVoiceEnabled(false);
      const online = VoiceModel(
        name: 'online',
        locale: 'en-IN',
        label: 'Online',
        requiresNetwork: true,
      );
      await service.setVoice(online);
      expect(service.selectedVoice?.name, 'en-in-x-ene-local');
      expect(service.errorMessage, contains('confirm'));
      await service.setVoice(online, confirmOnline: true);
      expect(service.selectedVoice, online);
      expect(storage.isOnlineVoiceApproved(online.name, online.locale), isTrue);
    },
  );
}
