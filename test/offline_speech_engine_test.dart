import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/services/offline_speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/offline_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late OfflineSpeechEngine engine;
  late List<MethodCall> calls;
  var completions = 0;
  var starts = 0;
  var errors = 0;
  Future<bool> speak() => engine.speak(
    directory: 'models',
    text: 'Hello world.',
    voice: 'F1',
    language: 'en',
    speed: 1,
    volume: 1,
  );
  Future<void> event(
    int id,
    String type, [
    Map<String, Object?> extra = const {},
  ]) async {
    final result = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'id': id, 'type': type, ...extra}),
      ),
      (_) => result.complete(),
    );
    await result.future;
  }

  setUp(() {
    calls = [];
    completions = 0;
    starts = 0;
    errors = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return ['speak', 'resume', 'prepareChapter'].contains(call.method)
          ? true
          : null;
    });
    engine = OfflineSpeechEngine(channel: channel);
    engine.onComplete = () => completions++;
    engine.onStart = () => starts++;
    engine.onError = (_) => errors++;
  });
  tearDown(() async {
    await engine.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Stop invalidates late start, completion and error', () async {
    await speak();
    final id = calls.last.arguments['id'] as int;
    await engine.stop();
    await event(id, 'started');
    await event(id, 'completed');
    await event(id, 'error');
    expect(starts + completions + errors, 0);
    expect(engine.active, isFalse);
    expect(engine.generating, isFalse);
  });

  Future<bool> prepare() => engine.beginChapter(
    directory: 'models',
    texts: ['First.', 'Second.'],
    voice: 'M2',
    language: 'en',
    speed: 1,
  );

  test(
    'chapter progress aggregates segments and readiness is not speech completion',
    () async {
      expect(await prepare(), isTrue);
      final id = calls.last.arguments['id'] as int;
      await event(id, 'preparing', {
        'segmentsDone': 1,
        'segmentsTotal': 2,
        'completed': 2,
        'total': 9,
        'message': 'Refining',
      });
      expect(engine.preparationProgress, closeTo((1 + 2 / 9) / 2, .001));
      await event(id, 'started');
      await event(id, 'completed');
      expect(completions + starts, 0);
      await event(id, 'chapterPrepared');
      expect(await engine.chapterReady, isTrue);
      expect(engine.active, isFalse);
      expect(completions, 0);
    },
  );

  test(
    'Stop or Pause finishes chapter wait immediately and ignores late readiness',
    () async {
      await prepare();
      final old = calls.last.arguments['id'] as int;
      final waiting = engine.chapterReady;
      await engine.pause();
      expect(await waiting, isFalse);
      await event(old, 'chapterPrepared');
      expect(await engine.chapterReady, isFalse);
      expect(engine.preparingChapter, isFalse);
      await prepare();
      await engine.stop();
      expect(await engine.chapterReady, isFalse);
    },
  );

  test(
    'chapter preparation errors release the waiter and keep the actionable message',
    () async {
      await prepare();
      final id = calls.last.arguments['id'] as int;
      await event(id, 'error', {
        'message': 'Not enough storage. Turn off chapter preparation.',
      });
      expect(await engine.chapterReady, isFalse);
      expect(engine.lastError, contains('Not enough storage'));
      expect(errors, 1);
    },
  );

  test(
    'preparation reports real stages and ignores stale or late updates',
    () async {
      await speak();
      final id = calls.last.arguments['id'] as int;
      await event(id, 'preparing', {
        'message': 'Refining voice',
        'completed': 2,
        'total': 7,
      });
      expect(engine.preparationMessage, 'Refining voice');
      expect(engine.preparationProgress, 2 / 7);
      await event(id, 'preparing', {
        'message': 'Loading model',
        'completed': 99,
        'total': 0,
      });
      expect(engine.preparationProgress, isNull);
      await event(id, 'started');
      await event(id, 'preparing', {
        'message': 'Late update',
        'completed': 3,
        'total': 7,
      });
      expect(engine.preparationProgress, isNull);
      expect(engine.preparationMessage, isNull);
      await engine.stop();
      await speak();
      await event(id, 'preparing', {
        'message': 'Stale request',
        'completed': 2,
        'total': 7,
      });
      expect(engine.preparationMessage, isNull);
      await engine.stop();
    },
  );

  test(
    'passes at most two optional lookahead segments to native playback',
    () async {
      await engine.speak(
        directory: 'models',
        text: 'Current paragraph.',
        nextText: 'Next paragraph.',
        followingText: 'Following paragraph.',
        voice: 'F1',
        language: 'en',
        speed: 1,
        volume: .5,
        steps: 3,
      );
      expect(calls.last.arguments['nextText'], 'Next paragraph.');
      expect(calls.last.arguments['followingText'], 'Following paragraph.');
      expect(calls.last.arguments['steps'], 3);
      await speak();
      expect(calls.last.arguments['steps'], 5);
      expect((calls.last.arguments as Map).containsKey('nextText'), isFalse);
      expect(
        (calls.last.arguments as Map).containsKey('followingText'),
        isFalse,
      );
    },
  );

  test('pause and resume retain the generated audio request', () async {
    expect(await speak(), isTrue);
    final id = calls.last.arguments['id'] as int;
    await event(id, 'started');
    expect(engine.generating, isFalse);
    await engine.pause();
    expect(await engine.resume(), isTrue);
    await event(id, 'completed');
    await event(id, 'completed');
    expect(completions, 1);
    expect(calls.where((c) => c.method == 'speak').length, 1);
    expect(engine.active, isFalse);
  });

  test(
    'rolling lookahead crosses the bridge without stopping the active request',
    () async {
      final texts = List.generate(8, (i) => 'Next $i.');
      await engine.speak(
        directory: 'models',
        text: 'Current.',
        voice: 'M2',
        language: 'en',
        speed: 1,
        volume: 1,
        upcomingTexts: texts,
      );
      expect(calls.last.arguments['upcomingTexts'], texts);
      final id = calls.last.arguments['id'];
      await engine.prepareNext(
        directory: 'models',
        text: texts.first,
        voice: 'M3',
        language: 'hi',
        speed: 1,
        upcomingTexts: texts,
      );
      expect(calls.last.method, 'preload');
      expect(calls.last.arguments['id'], id);
      expect(calls.last.arguments['upcomingTexts'], texts);
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
    },
  );

  test(
    'live lookahead update keeps the active request and narrator callbacks',
    () async {
      await speak();
      final id = calls.last.arguments['id'] as int;
      await engine.prepareNext(
        directory: 'models',
        text: 'Next.',
        nextText: 'Following.',
        voice: 'M3',
        language: 'hi',
        speed: 1,
      );
      expect(calls.last.method, 'preload');
      expect(calls.last.arguments['id'], id);
      expect(calls.last.arguments['nextText'], 'Following.');
      expect(engine.active, isTrue);
      await event(id, 'started');
      await event(id, 'completed');
      expect(starts, 1);
      expect(completions, 1);
    },
  );

  test(
    'unsupported lookahead falls back without failing active narration',
    () async {
      await speak();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'preload') {
          throw PlatformException(code: 'preload_failed');
        }
        return null;
      });
      await engine.prepareNext(
        directory: 'models',
        text: 'Next.',
        voice: 'M3',
        language: 'en',
        speed: 1,
      );
      expect(engine.active, isTrue);
      expect(errors, 0);
    },
  );

  test('idle or stopped engine never queues new lookahead', () async {
    await engine.prepareNext(
      directory: 'models',
      text: 'Next.',
      voice: 'M3',
      language: 'en',
      speed: 1,
    );
    expect(calls, isEmpty);
    await speak();
    await engine.stop();
    final count = calls.length;
    await engine.prepareNext(
      directory: 'models',
      text: 'Next.',
      voice: 'M3',
      language: 'en',
      speed: 1,
    );
    expect(calls.length, count);
  });

  test('previous synthesis cannot complete a newer segment', () async {
    await speak();
    final previous = calls.last.arguments['id'] as int;
    await speak();
    final current = calls.last.arguments['id'] as int;
    await event(previous, 'completed');
    expect(completions, 0);
    expect(engine.active, isTrue);
    await event(current, 'completed');
    expect(completions, 1);
  });
}
