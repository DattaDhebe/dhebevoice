import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/models/novel_book.dart';
import 'package:text_reader_app/models/voice_model.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/novel_import_controller.dart';
import 'package:text_reader_app/services/novel_library_service.dart';
import 'package:text_reader_app/services/reader_audio_handler.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/tts_service.dart';
import 'package:text_reader_app/services/web_novel_import_service.dart';

class RecordingStorage extends StorageService {
  final positions = <int>[];
  Completer<void>? positionBarrier;
  Completer<void>? chapterBarrier;
  Completer<void>? languageBarrier;

  @override
  Future<void> saveLanguage(String value) async {
    await super.saveLanguage(value);
    if (value == 'hi-IN') await languageBarrier?.future;
  }

  @override
  Future<void> saveActiveChapterIndex(int value) async {
    await chapterBarrier?.future;
    await super.saveActiveChapterIndex(value);
  }

  @override
  Future<void> savePosition(int value) async {
    positions.add(value);
    if (value > 0) await positionBarrier?.future;
    await super.savePosition(value);
  }
}

class MemoryLibrary extends NovelLibraryService {
  int saves = 0;

  @override
  Future<List<NovelBook>> loadLibrary() async => [
    NovelBook(
      id: 'test-book',
      title: 'Test book',
      sourceUrl: 'sample://test',
      importedAt: DateTime(2026),
      chapters: const [
        NovelChapter(
          title: 'First',
          url: '',
          content: 'First chapter.',
          order: 0,
        ),
        NovelChapter(
          title: 'Second',
          url: '',
          content: 'Second chapter.',
          order: 1,
        ),
      ],
    ),
  ];

  @override
  Future<void> saveLibrary(List<NovelBook> books) async {
    saves++;
  }
}

Future<void> flushCallbacks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ttsChannel = MethodChannel('flutter_tts');
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordingStorage storage;
  late FlutterTts engine;
  late TtsService service;
  late List<String> spoken;
  Completer<void>? queueBarrier;
  Completer<void>? stopBarrier;
  late List<String> nativeCalls;
  late List<MethodCall> nativeArguments;
  late List<bool> focusChanges;
  Object? defaultEngine;
  Future<bool> Function(bool active)? focusOverride;
  var failPause = false;
  late DateTime now;
  late MemoryLibrary library;
  late NovelImportController importer;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    storage = RecordingStorage();
    await storage.initialize();
    spoken = [];
    queueBarrier = null;
    stopBarrier = null;
    nativeCalls = [];
    nativeArguments = [];
    focusChanges = [];
    defaultEngine = 'com.test.speech';
    focusOverride = null;
    failPause = false;
    now = DateTime(2026, 10, 17);
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      nativeCalls.add(call.method);
      nativeArguments.add(call);
      if (call.method == 'getDefaultEngine') return defaultEngine;
      if (call.method == 'getVoices') {
        return [
          {'name': 'en-in-x-ene-local', 'locale': 'en-IN'},
          {'name': 'alternate', 'locale': 'en-IN', 'network_required': '0'},
          {'name': 'hindi-local', 'locale': 'hi-IN', 'network_required': '0'},
          {'name': 'french-online', 'locale': 'fr-FR', 'network_required': '1'},
        ];
      }
      if (call.method == 'setQueueMode') await queueBarrier?.future;
      if (call.method == 'stop') await stopBarrier?.future;
      if (call.method == 'pause' && failPause) {
        throw PlatformException(code: 'pause_failed');
      }
      if (call.method == 'speak') {
        final arguments = call.arguments;
        spoken.add(
          arguments is Map ? arguments['text'] as String : arguments as String,
        );
      }
      return 1;
    });
    engine = FlutterTts();
    service = TtsService(
      storageService: storage,
      fileImportService: FileImportService(),
      flutterTts: engine,
      clock: () => now,
      setAudioSessionActive: (active) async {
        focusChanges.add(active);
        return focusOverride == null ? true : await focusOverride!(active);
      },
    );
    await service.initialize();
    library = MemoryLibrary();
    importer = NovelImportController(
      storageService: storage,
      fileImportService: FileImportService(),
      novelLibraryService: library,
      webNovelImportService: WebNovelImportService(),
      ttsService: service,
    );
    await importer.initialize();
  });

  tearDown(() async {
    service.dispose();
    importer.dispose();
    await flushCallbacks();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(ttsChannel, null);
    messenger.setMockMethodCallHandler(sessionChannel, null);
  });

  test('late native start and continue cannot undo Stop', () async {
    await service.updateText('One paragraph.');
    await service.play();
    await service.stop();
    engine.startHandler!();
    engine.continueHandler!();
    expect(service.playbackState, ReaderPlaybackState.stopped);
  });

  test(
    'labeling Android voices never interrupts or changes synthesis',
    () async {
      await service.updateText('First paragraph.\n\nSecond paragraph.');
      await service.play();
      engine.startHandler!();
      engine.progressHandler!('First paragraph.', 6, 15, 'paragraph');
      final voice = service.selectedVoice!;
      final session = service.playbackSessionId;
      nativeCalls.clear();
      focusChanges.clear();

      expect(service.canLabelAndroidVoices, isTrue);
      expect(voice.personaLabel, isNull);
      await service.setVoiceTypeLabel(voice, 'Female');
      expect(service.selectedVoice?.personaLabel, 'Female');
      expect(service.selectedVoice?.userPersonaLabel, 'Female');
      expect(service.selectedVoice?.toTtsMap(), voice.toTtsMap());
      expect(service.playbackSessionId, session);
      expect(service.currentCharIndex, 6);
      expect(service.isPlaying, isTrue);
      expect(nativeCalls, isEmpty);
      expect(focusChanges, isEmpty);

      await service.refreshVoices();
      expect(service.selectedVoice?.personaLabel, 'Female');
      nativeCalls.clear();
      await service.setVoiceTypeLabel(service.selectedVoice!, null);
      expect(service.selectedVoice?.personaDisplayLabel, 'Gender not provided');
      expect(nativeCalls, isEmpty);
      expect(service.isPlaying, isTrue);
      engine.completionHandler!();
      await flushCallbacks();
      expect(spoken, ['First paragraph.', 'Second paragraph.']);
    },
  );

  test('Android voice labels are isolated by engine identity', () async {
    final voice = service.selectedVoice!;
    await service.setVoiceTypeLabel(voice, 'Male');
    defaultEngine = 'com.other.speech';
    await service.refreshVoices();
    expect(service.selectedVoice?.personaLabel, isNull);
    await service.setVoiceTypeLabel(service.selectedVoice!, 'Child');
    defaultEngine = 'com.test.speech';
    await service.refreshVoices();
    expect(service.selectedVoice?.personaLabel, 'Male');
  });

  test(
    'missing engine identity keeps voices usable without saved labels',
    () async {
      await service.setVoiceTypeLabel(service.selectedVoice!, 'Male');
      defaultEngine = null;
      await service.refreshVoices();
      expect(service.voices, isNotEmpty);
      expect(service.selectedVoice?.personaLabel, isNull);
      expect(service.canLabelAndroidVoices, isFalse);
      await expectLater(
        service.setVoiceTypeLabel(service.selectedVoice!, 'Female'),
        throwsStateError,
      );
      await service.updateText('Still readable.');
      await service.play();
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'language changes keep playing and apply at the next speech boundary',
    () async {
      await service.updateText('First paragraph.\n\nSecond paragraph.');
      await service.play();
      engine.startHandler!();
      engine.progressHandler!('First paragraph.', 6, 15, 'paragraph');
      nativeCalls.clear();
      final session = service.playbackSessionId;
      await service.setLanguage('hi-IN');
      expect(service.isPlaying, isTrue);
      expect(service.currentCharIndex, 6);
      expect(service.playbackSessionId, session);
      expect(
        nativeCalls,
        isNot(contains(anyOf('pause', 'stop', 'setLanguage'))),
      );
      engine.completionHandler!();
      await flushCallbacks();
      expect(spoken, ['First paragraph.', 'Second paragraph.']);
      expect(
        nativeArguments
            .lastWhere((call) => call.method == 'setLanguage')
            .arguments,
        'hi-IN',
      );
      expect(service.selectedVoice?.name, 'hindi-local');
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'latest voice selection wins without stopping the current paragraph',
    () async {
      await service.updateText('First.\n\nSecond.');
      await service.play();
      engine.startHandler!();
      nativeCalls.clear();
      final alternate = service.voices.firstWhere(
        (voice) => voice.name == 'alternate',
      );
      final first = service.setVoice(alternate);
      final second = service.setVoice(
        service.voices.firstWhere((voice) => voice.name == 'en-in-x-ene-local'),
      );
      await first;
      await second;
      expect(service.isPlaying, isTrue);
      expect(nativeCalls, isNot(contains(anyOf('pause', 'stop', 'setVoice'))));
      engine.completionHandler!();
      await flushCallbacks();
      expect(
        (nativeArguments
                .lastWhere((call) => call.method == 'setVoice')
                .arguments
            as Map)['name'],
        'en-in-x-ene-local',
      );
      expect(spoken, ['First.', 'Second.']);
    },
  );

  test(
    'language changes while paused do not start playback by themselves',
    () async {
      await service.updateText('Story.');
      await service.play();
      await service.pause();
      await service.setLanguage('hi-IN');
      expect(service.isPaused, isTrue);
      expect(spoken, ['Story.']);
      await service.play();
      expect(service.isPlaying, isTrue);
      expect(service.selectedLanguage, 'hi-IN');
    },
  );

  test(
    'Stop after a voice change cancels speech and automatic continuation',
    () async {
      await service.updateText('First.\n\nSecond.');
      await service.play();
      engine.startHandler!();
      await service.setLanguage('hi-IN');
      await service.stop();
      engine.completionHandler!();
      await flushCallbacks();
      expect(spoken, ['First.']);
      expect(service.playbackState, ReaderPlaybackState.stopped);
    },
  );

  test(
    'unsupported or unapproved language leaves the current voice playing',
    () async {
      await service.updateText('Story.');
      await service.play();
      final original = service.selectedLanguage;
      await service.setLanguage('xx-YY');
      expect(service.selectedLanguage, original);
      expect(service.isPlaying, isTrue);
      await service.setLanguage('fr-FR');
      expect(service.selectedLanguage, original);
      expect(service.isPlaying, isTrue);
      expect(service.errorMessage, contains('confirm'));
      await service.setVoice(
        const VoiceModel(
          name: 'french-online',
          locale: 'fr-FR',
          label: 'French',
          requiresNetwork: true,
        ),
        confirmOnline: true,
      );
      expect(service.selectedLanguage, 'fr-FR');
      expect(service.isPlaying, isTrue);
    },
  );

  test(
    'a slower earlier selection cannot overwrite the latest saved voice',
    () async {
      await service.updateText('Story.');
      await service.play();
      storage.languageBarrier = Completer<void>();
      final first = service.setLanguage('hi-IN');
      await flushCallbacks();
      await service.setLanguage('en-IN');
      storage.languageBarrier!.complete();
      await first;
      expect(service.selectedLanguage, 'en-IN');
      expect(storage.language, 'en-IN');
      expect(storage.voiceName, 'en-in-x-ene-local');
      expect(service.isPlaying, isTrue);
    },
  );

  test('repeated Play is idempotent while audio focus is pending', () async {
    await service.updateText('Story.');
    final focus = Completer<bool>();
    focusOverride = (active) async => active ? focus.future : true;
    final playing = service.play();
    await flushCallbacks();
    expect(service.isPlaying, isTrue);
    expect(service.isBuffering, isTrue);
    await service.play();
    focus.complete(true);
    await playing;
    expect(spoken, ['Story.']);
    engine.startHandler!();
    expect(service.isBuffering, isFalse);
  });

  test('Pause cancels Play before focus has been granted', () async {
    await service.updateText('Story.');
    final focus = Completer<bool>();
    focusOverride = (active) async => active ? focus.future : true;
    final playing = service.play();
    await flushCallbacks();
    final pausing = service.pause();
    expect(service.isPaused, isTrue);
    focus.complete(true);
    await playing;
    await pausing;
    expect(spoken, isEmpty);
    expect(focusChanges.last, isFalse);
  });

  test('Stop finishes before a newer Play takes focus', () async {
    await service.updateText('Story.');
    await service.play();
    stopBarrier = Completer<void>();
    final stopping = service.stop();
    final playing = service.play();
    expect(service.isPlaying, isTrue);
    stopBarrier!.complete();
    await stopping;
    await playing;
    expect(service.isPlaying, isTrue);
    expect(spoken, ['Story.', 'Story.']);
    expect(focusChanges.last, isTrue);
  });

  test(
    'audio focus denial and platform failures do not strand Playing',
    () async {
      await service.updateText('Story.');
      focusOverride = (active) async => !active;
      await service.play();
      expect(service.playbackState, ReaderPlaybackState.error);
      expect(service.errorMessage, contains('audio focus'));
      expect(spoken, isEmpty);
      focusOverride = (active) async {
        if (active) throw PlatformException(code: 'focus_failed');
        return true;
      };
      await service.play();
      expect(service.playbackState, ReaderPlaybackState.error);
      expect(service.isBuffering, isFalse);
    },
  );

  test('a transient interruption resumes once from the saved word', () async {
    const text = 'First paragraph.';
    await service.updateText(text);
    await service.play();
    engine.startHandler!();
    engine.progressHandler!(text, 6, 15, 'paragraph');
    await service.handleAudioInterruption(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    expect(service.isPaused, isTrue);
    await service.handleAudioInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await service.handleAudioInterruption(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    expect(spoken, [text, 'paragraph.']);
    expect(service.isPlaying, isTrue);
  });

  test(
    'a notification interruption resumes rather than staying silent',
    () async {
      await service.updateText('Story.');
      await service.play();
      await service.handleAudioInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      expect(service.isPaused, isTrue);
      await service.handleAudioInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      expect(service.isPlaying, isTrue);
      expect(spoken.length, 2);
    },
  );

  for (final action in ['pause', 'stop', 'disconnect', 'permanent loss']) {
    test('$action cancels automatic resume after an interruption', () async {
      await service.updateText('Story.');
      await service.play();
      await service.handleAudioInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      switch (action) {
        case 'pause':
          await service.pause();
        case 'stop':
          await service.stop();
        case 'disconnect':
          await service.handleAudioBecomingNoisy();
        case 'permanent loss':
          await service.handleAudioInterruption(
            AudioInterruptionEvent(true, AudioInterruptionType.unknown),
          );
      }
      await service.handleAudioInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(service.isPlaying, isFalse);
      expect(spoken, ['Story.']);
    });
  }

  test(
    'permanent focus loss pauses active speech without auto-resume',
    () async {
      await service.updateText('Story.');
      await service.play();
      await service.handleAudioInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.unknown),
      );
      expect(service.isPaused, isTrue);
      await service.handleAudioInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(spoken.length, 1);
    },
  );

  test(
    'Bluetooth disconnect falls back to Stop if native pause fails',
    () async {
      await service.updateText('Story.');
      await service.play();
      nativeCalls.clear();
      failPause = true;
      await service.handleAudioBecomingNoisy();
      expect(nativeCalls, containsAllInOrder(['pause', 'stop']));
      expect(service.isPaused, isTrue);
      expect(focusChanges.last, isFalse);
      expect(service.errorMessage, isNull);
    },
  );

  testWidgets('an unsolicited native pause never restarts on its own', (
    tester,
  ) async {
    await service.updateText('Story.');
    await service.play();
    engine.startHandler!();
    engine.pauseHandler!();
    await tester.pump(const Duration(seconds: 5));
    expect(service.isPaused, isTrue);
    expect(spoken.length, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  test('rapid headset toggles use current transport intent', () async {
    await service.updateText('Story.');
    final handler = ReaderAudioHandler(
      ttsService: service,
      novelImportController: importer,
    );
    final play = handler.click();
    final pause = handler.click();
    await play;
    await pause;
    expect(service.isPaused, isTrue);
    expect(handler.playbackState.value.playing, isFalse);
    await handler.click();
    expect(service.isPlaying, isTrue);
    await handler.pause();
    await handler.pause();
    expect(service.isPaused, isTrue);
  });

  test(
    'background media Next plays the selected chapter and retains focus',
    () async {
      await importer.selectNovel('test-book');
      final handler = ReaderAudioHandler(
        ttsService: service,
        novelImportController: importer,
      );
      await handler.play();
      await service.handleAppLifecycleState(AppLifecycleState.paused);
      focusChanges.clear();
      final states = <PlaybackState>[];
      final subscription = handler.playbackState.listen(states.add);
      await handler.skipToNext();
      await flushCallbacks();
      expect(service.isPlaying, isTrue);
      expect(spoken, ['First chapter.', 'Second chapter.']);
      expect(focusChanges, isNot(contains(false)));
      expect(
        states,
        isNot(
          contains(
            predicate<PlaybackState>(
              (s) => s.processingState == AudioProcessingState.idle,
            ),
          ),
        ),
      );
      expect(handler.mediaItem.value?.title, 'Second');
      expect(
        handler.playbackState.value.systemActions,
        isNot(contains(MediaAction.skipToNext)),
      );
      await subscription.cancel();
    },
  );

  test(
    'media queue selection really changes chapters without starting paused audio',
    () async {
      await importer.selectNovel('test-book');
      final handler = ReaderAudioHandler(
        ttsService: service,
        novelImportController: importer,
      );
      await handler.play();
      await handler.pause();
      await handler.skipToQueueItem(1);
      expect(importer.activeChapterIndex, 1);
      expect(service.isPlaying, isFalse);
      expect(service.isPaused, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(spoken, ['First chapter.']);
      await handler.skipToQueueItem(-1);
      await handler.skipToQueueItem(100);
      expect(importer.activeChapterIndex, 1);
      await handler.play();
      await handler.skipToQueueItem(0);
      expect(service.isPlaying, isTrue);
      expect(spoken.last, 'First chapter.');
    },
  );

  test('Pause cancels an in-flight media Next', () async {
    await importer.selectNovel('test-book');
    final handler = ReaderAudioHandler(
      ttsService: service,
      novelImportController: importer,
    );
    await handler.play();
    storage.chapterBarrier = Completer<void>();
    final next = handler.skipToNext();
    await flushCallbacks();
    await handler.pause();
    storage.chapterBarrier!.complete();
    await next;
    expect(service.isPlaying, isFalse);
    expect(spoken, ['First chapter.']);
  });

  test('chapter autoplay does not release focus between chapters', () async {
    await importer.selectNovel('test-book');
    await service.play();
    focusChanges.clear();
    engine.startHandler!();
    engine.completionHandler!();
    await flushCallbacks();
    expect(spoken, ['First chapter.', 'Second chapter.']);
    expect(focusChanges, isNot(contains(false)));
  });

  test(
    'resuming at a completed paragraph advances instead of getting stuck',
    () async {
      await service.updateText('First.\n\nSecond.');
      await service.play();
      engine.startHandler!();
      storage.positionBarrier = Completer<void>();
      engine.completionHandler!();
      final pausing = service.pause();
      storage.positionBarrier!.complete();
      await pausing;
      await service.play();
      expect(spoken, ['First.', 'Second.']);
    },
  );

  testWidgets('in-app Stop cancels the sleep timer too', (tester) async {
    service.setSleepTimer(const Duration(minutes: 15));
    await service.stop();
    final session = service.playbackSessionId;
    await tester.pump(const Duration(minutes: 15));
    expect(service.sleepTimerEndsAt, isNull);
    expect(service.playbackSessionId, session);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'a valid long utterance is not restarted without word callbacks',
    (tester) async {
      final text = List.filled(50, 'A quiet story continues.').join(' ');
      await service.updateText(text);
      await service.play();
      engine.startHandler!();
      now = now.add(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 16));
      expect(spoken, [text]);
      expect(service.isPlaying, isTrue);
      await service.stop();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('a stalled Android engine is recovered while minimized', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await service.updateText('Story.');
    await service.play();
    await service.handleAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 16));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(spoken, ['Story.', 'Story.']);
    await service.stop();
    debugDefaultTargetPlatformOverride = null;
  });

  test('Pause at the chapter end can resume into the next chapter', () async {
    await importer.selectNovel('test-book');
    await service.play();
    engine.startHandler!();
    storage.positionBarrier = Completer<void>();
    engine.completionHandler!();
    final pausing = service.pause();
    storage.positionBarrier!.complete();
    await pausing;
    await service.play();
    await flushCallbacks();
    expect(importer.activeChapterIndex, 1);
    expect(spoken, ['First chapter.', 'Second chapter.']);
    expect(service.isPlaying, isTrue);
  });

  test(
    'media buffering remains active throughout delayed chapter autoplay',
    () async {
      await importer.selectNovel('test-book');
      final handler = ReaderAudioHandler(
        ttsService: service,
        novelImportController: importer,
      );
      await handler.play();
      engine.startHandler!();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      storage.chapterBarrier = Completer<void>();
      engine.completionHandler!();
      await flushCallbacks();
      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.buffering,
      );
      await handler.pause();
      storage.chapterBarrier!.complete();
      await flushCallbacks();
      expect(handler.playbackState.value.playing, isFalse);
      expect(spoken, ['First chapter.']);
    },
  );

  test('queued media navigation is cancelled by Stop', () async {
    await importer.selectNovel('test-book');
    final handler = ReaderAudioHandler(
      ttsService: service,
      novelImportController: importer,
    );
    await handler.play();
    storage.chapterBarrier = Completer<void>();
    final next = handler.skipToNext();
    await flushCallbacks();
    final previous = handler.skipToPrevious();
    await handler.stop();
    storage.chapterBarrier!.complete();
    await next;
    await previous;
    expect(importer.activeChapterIndex, 1);
    expect(service.isPlaying, isFalse);
    expect(spoken, ['First chapter.']);
  });

  testWidgets(
    'sleep expiry prevents a pending chapter transition from restarting audio',
    (tester) async {
      try {
        await importer.selectNovel('test-book');
        await service.play();
        engine.startHandler!();
        storage.chapterBarrier = Completer<void>();
        service.setSleepTimer(const Duration(seconds: 1));
        engine.completionHandler!();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        storage.chapterBarrier!.complete();
        await tester.pump();
        expect(service.sleepTimerEndsAt, isNull);
        expect(service.isPlaying, isFalse);
        expect(spoken, ['First chapter.']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'sleep expiry falls back to stopping speech if native pause fails',
    (tester) async {
      try {
        const text = 'First paragraph for bedtime listening.';
        await service.updateText(text);
        await service.play();
        engine.startHandler!();
        engine.progressHandler!(text, 6, 15, 'paragraph');
        var stops = 0;
        messenger.setMockMethodCallHandler(ttsChannel, (call) async {
          if (call.method == 'pause') {
            throw PlatformException(code: 'pause_failed');
          }
          if (call.method == 'stop') stops++;
          return 1;
        });
        service.setSleepTimer(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(stops, 1);
        expect(service.isPaused, isTrue);
        expect(service.currentCharIndex, 6);
        expect(storage.position, 6);
        expect(service.errorMessage, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('sleep timer pauses at the saved position and allows resume', (
    tester,
  ) async {
    const text = 'First paragraph for bedtime listening.';
    await service.updateText(text);
    await service.play();
    engine.startHandler!();
    engine.progressHandler!(text, 6, 15, 'paragraph');
    service.setSleepTimer(const Duration(minutes: 15));
    await tester.pump(const Duration(minutes: 15));
    await tester.pump();
    expect(service.sleepTimerEndsAt, isNull);
    expect(service.isPaused, isTrue);
    expect(service.currentCharIndex, 6);
    expect(storage.position, 6);
    await service.play();
    expect(service.isPlaying, isTrue);
    expect(spoken.last, text.substring(6));
    await service.stop();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'replacing and cancelling sleep timers invalidates old deadlines',
    (tester) async {
      service.setSleepTimer(const Duration(minutes: 15));
      service.setSleepTimer(const Duration(minutes: 30));
      await tester.pump(const Duration(minutes: 15));
      expect(service.sleepTimerEndsAt, isNotNull);
      service.setSleepTimer(null);
      final session = service.playbackSessionId;
      await tester.pump(const Duration(minutes: 30));
      expect(service.sleepTimerEndsAt, isNull);
      expect(service.playbackSessionId, session);
      expect(() => service.setSleepTimer(Duration.zero), throwsArgumentError);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('media Stop cancels a timer but chapter changes preserve it', (
    tester,
  ) async {
    service.setSleepTimer(const Duration(minutes: 30));
    await importer.selectNovel('test-book');
    await importer.selectChapter(1);
    expect(service.sleepTimerEndsAt, isNotNull);
    final handler = ReaderAudioHandler(
      ttsService: service,
      novelImportController: importer,
    );
    await handler.stop();
    expect(service.sleepTimerEndsAt, isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'chapter autoplay advances without rewriting the book library',
    () async {
      await importer.selectNovel('test-book');
      await service.play();
      engine.startHandler!();
      engine.completionHandler!();
      await flushCallbacks();
      expect(importer.activeChapterIndex, 1);
      expect(spoken, ['First chapter.', 'Second chapter.']);
      expect(service.isPlaying, isTrue);
      expect(library.saves, 0);
      expect(storage.chapterIndexForNovel('test-book'), 1);
    },
  );

  test('Stop during chapter autoplay prevents automatic restart', () async {
    await importer.selectNovel('test-book');
    await service.play();
    engine.startHandler!();
    storage.chapterBarrier = Completer<void>();
    engine.completionHandler!();
    await flushCallbacks();
    await service.stop();
    storage.chapterBarrier!.complete();
    await flushCallbacks();
    expect(spoken, ['First chapter.']);
    expect(service.playbackState, ReaderPlaybackState.stopped);
  });

  test('Stop wins over a pending media Next action', () async {
    final handler = ReaderAudioHandler(
      ttsService: service,
      novelImportController: importer,
    );
    await importer.selectNovel('test-book');
    await handler.play();
    storage.chapterBarrier = Completer<void>();
    final next = handler.skipToNext();
    await flushCallbacks();
    await handler.stop();
    storage.chapterBarrier!.complete();
    await next;
    expect(service.isPlaying, isFalse);
    expect(spoken, ['First chapter.']);
  });

  test('explicit chapter selection is clamped to a valid chapter', () async {
    await importer.selectNovel('test-book', chapterIndex: 1000);
    expect(importer.activeChapterIndex, 1);
    expect(service.text, 'Second chapter.');
  });

  test(
    'Stop during completion persistence cannot advance or restart',
    () async {
      await service.updateText('First.\n\nSecond.');
      await service.play();
      engine.startHandler!();
      storage.positionBarrier = Completer<void>();
      engine.completionHandler!();
      await service.stop();
      storage.positionBarrier!.complete();
      await flushCallbacks();
      expect(spoken, ['First.']);
      expect(service.playbackState, ReaderPlaybackState.stopped);
    },
  );

  test(
    'Stop during native queue setup does not issue speak afterward',
    () async {
      await service.updateText('First.');
      queueBarrier = Completer<void>();
      final play = service.play();
      await flushCallbacks();
      await service.stop();
      queueBarrier!.complete();
      await play;
      expect(spoken, isEmpty);
    },
  );

  test('duplicate completion only advances one paragraph', () async {
    await service.updateText('First.\n\nSecond.\n\nThird.');
    await service.play();
    engine.startHandler!();
    engine.completionHandler!();
    engine.completionHandler!();
    await flushCallbacks();
    expect(spoken, ['First.', 'Second.']);
    expect(service.currentParagraphIndex, 1);
  });

  test(
    'word callbacks update position without per-word writes and rebuilds',
    () async {
      const text = 'one two three four five six seven eight nine ten';
      await service.updateText(text);
      await service.play();
      engine.startHandler!();
      var notifications = 0;
      service.addListener(() => notifications++);
      storage.positions.clear();
      for (var i = 0; i < 20; i++) {
        engine.progressHandler!(text, i, i + 1, 'word');
      }
      expect(service.currentCharIndex, 19);
      expect(storage.positions.length, 1);
      expect(notifications, lessThanOrEqualTo(1));
      await service.pause();
      expect(storage.positions.last, 19);
    },
  );

  test('pause and resume starts at the saved source character', () async {
    const text = 'First.\n\n\n  Second paragraph.';
    await service.updateText(text);
    await service.playFromParagraph(1);
    engine.startHandler!();
    engine.progressHandler!('Second paragraph.', 7, 16, 'paragraph');
    await service.pause();
    await service.play();
    expect(spoken.last, 'paragraph.');
    expect(service.currentCharIndex, text.indexOf('paragraph'));
  });

  test('progress from a previous chapter is ignored', () async {
    await service.updateText('New chapter.');
    await service.play();
    engine.progressHandler!('Old chapter.', 9, 10, 'x');
    expect(service.currentCharIndex, 0);
  });

  test('editing playing text stops the old speech queue', () async {
    await service.updateText('Old text.');
    await service.play();
    await service.updateText('Edited text.');
    engine.completionHandler!();
    await flushCallbacks();
    expect(service.text, 'Edited text.');
    expect(service.isPlaying, isFalse);
    expect(spoken, ['Old text.']);
  });

  test('chapter completion handler is called once at the end', () async {
    await service.updateText('Only paragraph.');
    var completions = 0;
    service.setPlaybackCompletedHandler(() async {
      completions++;
    });
    await service.play();
    engine.startHandler!();
    engine.completionHandler!();
    await flushCallbacks();
    expect(completions, 1);
    expect(service.playbackState, ReaderPlaybackState.completed);
  });

  test(
    'Stop remains idle in the media session after later notifications',
    () async {
      final importer = NovelImportController(
        storageService: storage,
        fileImportService: FileImportService(),
        novelLibraryService: NovelLibraryService(),
        webNovelImportService: WebNovelImportService(),
        ttsService: service,
      );
      final handler = ReaderAudioHandler(
        ttsService: service,
        novelImportController: importer,
      );
      await service.updateText('Text.');
      await handler.play();
      await handler.stop();
      await service.setPitch(1.1);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(handler.playbackState.value.playing, isFalse);
      importer.dispose();
    },
  );
}
