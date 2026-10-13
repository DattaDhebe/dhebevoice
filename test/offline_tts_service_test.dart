import 'dart:async';
import 'dart:io';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel('test/native_neural');
  const android = MethodChannel('flutter_tts');
  const audio = MethodChannel('com.ryanheise.audio_session');
  late StorageService storage;
  late TestableNeuralTts service;
  late FlutterTts androidTts;
  late List<MethodCall> calls;
  var chapterCompletions = 0;

  Future<void> event(String type, [int? id]) async {
    final latestId = calls
        .lastWhere((c) => c.method == 'speak')
        .arguments['id'];
    final result = Completer<void>();
    messenger.handlePlatformMessage(
      native.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'id': id ?? latestId, 'type': type}),
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
    storage = StorageService();
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
      return call.method == 'speak' || call.method == 'resume' ? true : null;
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
      await event('started');
      await event('completed');
      expect(calls.where((c) => c.method == 'speak').length, 2);
      expect(service.currentParagraphIndex, 1);
      await event('started');
      await event('completed');
      await event('completed');
      expect(chapterCompletions, 1);
      expect(service.playbackState, ReaderPlaybackState.completed);
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
