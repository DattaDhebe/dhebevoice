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
  void Function()? onStart;
  void Function()? onComplete;
  void Function()? onActivity;
  void Function(String)? onError;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'event') return;
    final event = Map<String, dynamic>.from(call.arguments as Map);
    if (event['id'] != _requestId || !active) return;
    switch (event['type']) {
      case 'started':
        generating = false;
        onStart?.call();
      case 'activity':
        onActivity?.call();
      case 'completed':
        generating = false;
        active = false;
        onComplete?.call();
      case 'error':
        generating = false;
        active = false;
        onError?.call(event['message'] as String? ?? 'Offline voice failed.');
    }
  }

  Future<bool> speak({
    required String directory,
    required String text,
    required String voice,
    required String language,
    required double speed,
    required double volume,
    String? nextText,
  }) async {
    final request = ++_requestId;
    active = true;
    generating = true;
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
        'nextText': ?nextText,
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

  Future<void> pause() => _channel.invokeMethod<void>('pause');
  Future<bool> resume() async =>
      await _channel.invokeMethod<bool>('resume') ?? false;
  Future<void> setVolume(double value) =>
      _channel.invokeMethod<void>('volume', {'value': value});
  Future<void> stop() async {
    ++_requestId;
    active = false;
    generating = false;
    await _channel.invokeMethod<void>('stop');
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
