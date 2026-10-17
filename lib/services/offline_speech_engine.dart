import 'dart:async';

import 'package:flutter/services.dart';

/// Small request-id bridge prevents a cancelled synthesis from restarting audio.
class OfflineSpeechEngine {
  OfflineSpeechEngine({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.dhebe.dhebevoice/offline_tts') {
    _channel.setMethodCallHandler(_handleCall);
  }
  final MethodChannel _channel;
  int _requestId = 0;
  bool generating = false;
  bool active = false;
  String? lastError;
  String? preparationMessage;
  int? completedStages;
  int? totalStages;
  int? segmentsDone;
  int? segmentsTotal;
  bool preparingChapter = false;
  Completer<bool>? _chapterReady;
  Future<bool> get chapterReady => _chapterReady?.future ?? Future.value(false);
  double? get preparationProgress {
    final stage = completedStages == null || totalStages == null
        ? null
        : completedStages! / totalStages!;
    if (segmentsTotal != null) {
      return (segmentsDone! +
              (segmentsDone! < segmentsTotal! ? stage ?? 0 : 0)) /
          segmentsTotal!;
    }
    return stage;
  }

  void Function()? onStart;
  void Function()? onComplete;
  void Function()? onActivity;
  void Function()? onPreparation;
  void Function(String)? onError;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'event') return;
    final event = Map<String, dynamic>.from(call.arguments as Map);
    if (event['id'] != _requestId || !active) return;
    switch (event['type']) {
      case 'preparing':
        if (!generating) return;
        preparationMessage = event['message'] as String?;
        final completed = event['completed'];
        final total = event['total'];
        final valid =
            completed is int &&
            total is int &&
            total > 0 &&
            completed >= 0 &&
            completed <= total;
        completedStages = valid ? completed : null;
        totalStages = valid ? total : null;
        final done = event['segmentsDone'];
        final count = event['segmentsTotal'];
        if (done is int &&
            count is int &&
            count > 0 &&
            done >= 0 &&
            done <= count) {
          segmentsDone = done;
          segmentsTotal = count;
          preparationMessage = done == count
              ? 'Chapter audio is ready'
              : 'Segment ${done + 1} of $count: ${preparationMessage ?? 'Preparing speech'}';
        }
        onPreparation?.call();
      case 'chapterPrepared':
        if (!preparingChapter) return;
        preparingChapter = false;
        generating = false;
        active = false;
        _completeChapter(true);
      case 'started':
        if (preparingChapter) return;
        generating = false;
        _clearPreparation();
        onStart?.call();
      case 'activity':
        onActivity?.call();
      case 'completed':
        if (preparingChapter) return;
        generating = false;
        active = false;
        _clearPreparation();
        onComplete?.call();
      case 'error':
        generating = false;
        active = false;
        _clearPreparation();
        preparingChapter = false;
        lastError = event['message'] as String? ?? 'Offline voice failed.';
        _completeChapter(false);
        onError?.call(event['message'] as String? ?? 'Offline voice failed.');
    }
  }

  Future<bool> beginChapter({
    required String directory,
    required List<String> texts,
    required String voice,
    required String language,
    required double speed,
    int steps = 5,
  }) async {
    if (texts.isEmpty) {
      throw ArgumentError.value(texts, 'texts', 'Chapter must contain speech');
    }
    _completeChapter(false);
    _chapterReady = Completer<bool>();
    final request = ++_requestId;
    active = true;
    generating = true;
    preparingChapter = true;
    lastError = null;
    _clearPreparation();
    preparationMessage = 'Preparing chapter for continuous playback';
    segmentsDone = 0;
    segmentsTotal = texts.length;
    onPreparation?.call();
    try {
      final accepted = await _channel.invokeMethod<bool>('prepareChapter', {
        'id': request,
        'directory': directory,
        'text': texts.first,
        'texts': texts,
        'voice': voice,
        'language': language,
        'speed': speed,
        'steps': steps,
      });
      if (request != _requestId) return false;
      if (accepted == true) return true;
    } catch (error) {
      if (request != _requestId) return false;
      lastError = error is PlatformException
          ? error.message
          : 'Chapter preparation failed.';
    }
    active = false;
    generating = false;
    preparingChapter = false;
    _completeChapter(false);
    return false;
  }

  void _completeChapter(bool ready) {
    if (_chapterReady?.isCompleted == false) _chapterReady!.complete(ready);
  }

  Future<bool> speak({
    required String directory,
    required String text,
    required String voice,
    required String language,
    required double speed,
    required double volume,
    int steps = 5,
    String? nextText,
    String? followingText,
    List<String>? upcomingTexts,
  }) async {
    _completeChapter(false);
    preparingChapter = false;
    final request = ++_requestId;
    active = true;
    generating = true;
    _clearPreparation();
    onPreparation?.call();
    lastError = null;
    try {
      final started = await _channel.invokeMethod<bool>('speak', {
        'id': request,
        'directory': directory,
        'text': text,
        'voice': voice,
        'language': language,
        'speed': speed,
        'volume': volume,
        'steps': steps,
        'nextText': ?nextText,
        'followingText': ?followingText,
        'upcomingTexts': ?upcomingTexts,
      });
      if (request == _requestId && started != true) {
        active = false;
        generating = false;
      }
      return request == _requestId && started == true;
    } catch (error) {
      if (request == _requestId) {
        active = false;
        generating = false;
        lastError = error is PlatformException ? error.message : null;
      }
      return false;
    }
  }

  Future<void> pause() =>
      preparingChapter ? stop() : _channel.invokeMethod<void>('pause');
  Future<void> prepareNext({
    required String directory,
    required String text,
    required String voice,
    required String language,
    required double speed,
    int steps = 5,
    String? nextText,
    List<String>? upcomingTexts,
  }) async {
    if (!active) return;
    try {
      await _channel.invokeMethod<void>('preload', {
        'id': _requestId,
        'directory': directory,
        'text': text,
        'voice': voice,
        'language': language,
        'speed': speed,
        'steps': steps,
        'nextText': ?nextText,
        'upcomingTexts': ?upcomingTexts,
      });
    } on PlatformException {
      // Lookahead is optional; normal speech can still render the next segment.
    } on MissingPluginException {
      // Older native builds can still apply a voice at the next speak request.
    }
  }

  Future<bool> resume() async =>
      await _channel.invokeMethod<bool>('resume') ?? false;
  Future<void> setVolume(double value) =>
      _channel.invokeMethod<void>('volume', {'value': value});
  Future<void> stop() async {
    ++_requestId;
    active = false;
    generating = false;
    preparingChapter = false;
    _completeChapter(false);
    _clearPreparation();
    await _channel.invokeMethod<void>('stop');
  }

  void _clearPreparation() {
    preparationMessage = null;
    completedStages = null;
    totalStages = null;
    segmentsDone = null;
    segmentsTotal = null;
  }

  Future<void> unload() async {
    await stop();
    await _channel.invokeMethod<void>('unload');
  }

  Future<void> dispose() async {
    try {
      await unload();
    } on PlatformException {
      // The engine may already have detached during application shutdown.
    } on MissingPluginException {
      // No native handler remains after engine teardown.
    } finally {
      _channel.setMethodCallHandler(null);
    }
  }
}
