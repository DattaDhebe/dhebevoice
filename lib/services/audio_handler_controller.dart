import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

class AudioHandlerController extends ChangeNotifier {
  AudioHandler? _audioHandler;
  String? _errorMessage;

  AudioHandler? get audioHandler => _audioHandler;
  bool get isReady => _audioHandler != null;
  String? get errorMessage => _errorMessage;

  void reportError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void attach(AudioHandler handler) {
    if (identical(_audioHandler, handler)) {
      return;
    }
    _audioHandler = handler;
    _errorMessage = null;
    notifyListeners();
  }
}
