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
  Future<void> event(int id, String type) async {
    final result = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'id': id, 'type': type}),
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
      return call.method == 'speak' || call.method == 'resume' ? true : null;
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
