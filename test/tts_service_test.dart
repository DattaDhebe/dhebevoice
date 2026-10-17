import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/models/novel_book.dart';
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
  late MemoryLibrary library;
  late NovelImportController importer;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    storage = RecordingStorage();
    await storage.initialize();
    spoken = [];
    queueBarrier = null;
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      if (call.method == 'getVoices') {
        return [
          {'name': 'en-in-x-ene-local', 'locale': 'en-IN'},
        ];
      }
      if (call.method == 'setQueueMode') await queueBarrier?.future;
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
