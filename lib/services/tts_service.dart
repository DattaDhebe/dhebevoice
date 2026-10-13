import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/voice_model.dart';
import '../models/reader_text.dart';
import '../models/offline_voice_pack.dart';
import 'file_import_service.dart';
import 'offline_model_store.dart';
import 'offline_speech_engine.dart';
import 'storage_service.dart';

enum ReaderPlaybackState { idle, playing, paused, stopped, completed, error }

enum _PauseOrigin { none, user, system }

class TtsService extends ChangeNotifier {
  static const _defaultLanguage = 'en-IN';
  static const _defaultVoicePattern = 'en-in-x-ene-local';
  static const _defaultSpeechRate = 0.48;
  static const _defaultPitch = 1.0;
  static const _defaultVolume = 1.0;
  static const _watchdogCheckInterval = Duration(seconds: 4);
  static const _watchdogTimeout = Duration(seconds: 12);

  TtsService({
    required StorageService storageService,
    required FileImportService fileImportService,
    FlutterTts? flutterTts,
    OfflineModelStore? modelStore,
    OfflineSpeechEngine? offlineEngine,
  }) : _storageService = storageService,
       _fileImportService = fileImportService,
       _flutterTts = flutterTts ?? FlutterTts(),
       modelStore = modelStore ?? OfflineModelStore(),
       _offlineEngine = offlineEngine;

  final StorageService _storageService;
  final FileImportService _fileImportService;
  final FlutterTts _flutterTts;
  final OfflineModelStore modelStore;
  OfflineSpeechEngine? _offlineEngine;
  bool _useOfflineVoice = false;
  bool _switchingVoice = false;
  bool get usesOfflineVoice => _useOfflineVoice;
  bool get switchingVoice => _switchingVoice;
  bool get supportsOfflineVoice =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;

  List<VoiceModel> _voices = const [];
  List<SpeechChunk> _queuedChunks = const [];
  ReaderText _readerText = ReaderText('');
  ReaderPlaybackState _playbackState = ReaderPlaybackState.idle;
  String _text = '';
  String _selectedLanguage = _defaultLanguage;
  VoiceModel? _selectedVoice;
  double _speechRate = _defaultSpeechRate;
  double _pitch = _defaultPitch;
  double _volume = _defaultVolume;
  String? _errorMessage;
  int _currentCharIndex = 0;
  int _currentParagraphIndex = 0;
  int _pausedCharIndex = 0;
  int _sessionId = 0;
  int _activeChunkOffset = 0;
  int _queuedChunkIndex = 0;
  int? _queuedEndOffset;
  bool _queuedResetPositionOnComplete = true;
  bool _queuedTriggerCompletionHandler = true;
  bool _engineReady = false;
  bool _resumeAfterInterruption = false;
  bool _isInitializing = false;
  bool _hasInitialized = false;
  bool _isRecoveringFromStall = false;
  bool _chunkStarted = false;
  bool _isDisposed = false;
  int? _completingSession;
  Future<void>? _initialization;
  DateTime? _lastPositionSaveAt;
  int _stallRecoveryAttempts = 0;
  DateTime? _lastPlaybackActivityAt;
  Future<void> Function()? _playbackCompletedHandler;
  Timer? _playbackWatchdog;
  Timer? _unexpectedPauseRecoveryTimer;
  _PauseOrigin _pauseOrigin = _PauseOrigin.none;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  List<VoiceModel> get voices => _voices;
  ReaderPlaybackState get playbackState => _playbackState;
  String get text => _text;
  String get selectedLanguage => _selectedLanguage;
  VoiceModel? get selectedVoice => _selectedVoice;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  double get volume => _volume;
  String? get errorMessage => _errorMessage;
  int get currentCharIndex => _currentCharIndex;
  int get currentParagraphIndex => _currentParagraphIndex;
  List<String> get paragraphs => _readerText.paragraphs;
  int get paragraphCount => paragraphs.length;

  bool get isPlaying => _playbackState == ReaderPlaybackState.playing;
  bool get isPaused => _playbackState == ReaderPlaybackState.paused;
  bool get isInitializing => _isInitializing;
  bool get hasInitialized => _hasInitialized;
  int get playbackSessionId => _sessionId;

  void setPlaybackCompletedHandler(Future<void> Function()? handler) {
    _playbackCompletedHandler = handler;
  }

  String get currentParagraph {
    final items = paragraphs;
    if (items.isEmpty) {
      return 'Paste text, import a .txt or .epub file, or share text into the app.';
    }

    final index = min(_currentParagraphIndex, items.length - 1);
    return items[index].trim();
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _isInitializing = true;
    notifyListeners();

    if (_text.isEmpty) _text = _storageService.text;
    _readerText = ReaderText(_text);
    _speechRate = _storageService.rate;
    _pitch = _storageService.pitch;
    _volume = _storageService.volume;
    _currentCharIndex = _storageService.position.clamp(0, _text.length);
    try {
      await _configureTts();
      await _configureAudioSession();
      await _loadVoices();
      await _applyStoredSelections();
      await _syncTtsOptions();

      if (supportsOfflineVoice &&
          _storageService.speechProvider == OfflineVoicePack.id) {
        await modelStore.initialize();
        if (modelStore.ready) await setOfflineVoiceEnabled(true);
      }

      if (_text.isNotEmpty) {
        _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      }
    } catch (error) {
      _engineReady = false;
      _errorMessage =
          'Could not prepare playback. Check your installed TTS engine.';
      debugPrint('TTS initialization failed: $error');
    } finally {
      _isInitializing = false;
      _hasInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _configureTts() async {
    try {
      await _flutterTts.awaitSpeakCompletion(false);
      await _flutterTts.setQueueMode(0);

      _flutterTts.setStartHandler(() {
        if (_useOfflineVoice) return;
        if (!isPlaying || _queuedChunks.isEmpty || _isDisposed) return;
        _chunkStarted = true;
        _markPlaybackActivity();
        _errorMessage = null;
        notifyListeners();
      });

      _flutterTts.setCompletionHandler(() {
        if (_useOfflineVoice) return;
        if (!_chunkStarted || !isPlaying || _isDisposed) return;
        _chunkStarted = false;
        _markPlaybackActivity(resetRecoveryAttempts: true);
        unawaited(_handleChunkCompleted());
      });

      _flutterTts.setPauseHandler(() {
        if (_useOfflineVoice) return;
        if (_isDisposed || !isPlaying || _queuedChunks.isEmpty) return;
        final pauseOrigin = _pauseOrigin;
        _pauseOrigin = _PauseOrigin.none;
        _stopPlaybackWatchdog();
        _playbackState = ReaderPlaybackState.paused;
        notifyListeners();
        if (pauseOrigin == _PauseOrigin.none && _queuedChunks.isNotEmpty) {
          _scheduleUnexpectedPauseRecovery();
        }
      });

      _flutterTts.setContinueHandler(() {
        if (_useOfflineVoice) return;
        if (!isPlaying || _queuedChunks.isEmpty || _isDisposed) return;
        _chunkStarted = true;
        _cancelUnexpectedPauseRecovery();
        _markPlaybackActivity(resetRecoveryAttempts: true);
        _startPlaybackWatchdog();
        _playbackState = ReaderPlaybackState.playing;
        _errorMessage = null;
        notifyListeners();
      });

      _flutterTts.setErrorHandler((message) {
        if (_useOfflineVoice) return;
        unawaited(_handlePlaybackError(message));
      });

      _flutterTts.setProgressHandler((text, start, end, word) {
        if (_useOfflineVoice) return;
        if (!isPlaying || _queuedChunks.isEmpty || _isDisposed) return;
        final activeChunk = _queuedChunks[_queuedChunkIndex];
        if (text != activeChunk.text) return;
        _chunkStarted = true;
        _markPlaybackActivity(resetRecoveryAttempts: true);
        final previousParagraph = _currentParagraphIndex;
        final hadProgress = _currentCharIndex > 0;
        _activeChunkOffset = activeChunk.start;
        _currentCharIndex = (_activeChunkOffset + start).clamp(
          activeChunk.start,
          activeChunk.end,
        );
        _pausedCharIndex = _currentCharIndex;
        _currentParagraphIndex = activeChunk.paragraphIndex;
        final now = DateTime.now();
        if (_lastPositionSaveAt == null ||
            now.difference(_lastPositionSaveAt!) >=
                const Duration(seconds: 2)) {
          _lastPositionSaveAt = now;
          unawaited(_storageService.savePosition(_currentCharIndex));
        }
        // The reader highlights a paragraph, not each spoken word.
        if (previousParagraph != _currentParagraphIndex ||
            hadProgress != (_currentCharIndex > 0)) {
          notifyListeners();
        }
      });

      _engineReady = true;
    } catch (_) {
      _engineReady = false;
      _errorMessage =
          'No Android text-to-speech engine is available on this device yet.';
    }
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration.speech().copyWith(
        androidWillPauseWhenDucked: false,
      ),
    );
    _audioSession = session;

    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (!isPlaying) {
          return;
        }

        switch (event.type) {
          case AudioInterruptionType.pause:
            _resumeAfterInterruption = true;
            unawaited(pause(fromSystemInterruption: true));
          case AudioInterruptionType.duck:
          case AudioInterruptionType.unknown:
            break;
        }
        return;
      }

      switch (event.type) {
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption && isPaused) {
            _resumeAfterInterruption = false;
            unawaited(play());
          } else {
            _resumeAfterInterruption = false;
          }
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          break;
      }
    });

    _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
      if (isPlaying) {
        unawaited(pause());
      }
    });
  }

  Future<void> _loadVoices() async {
    if (!_engineReady) {
      _voices = const [];
      return;
    }

    final rawVoices = await _flutterTts.getVoices;
    final voiceMaps =
        (rawVoices as List<dynamic>)
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (entry) =>
                  entry.map((key, value) => MapEntry(key.toString(), value)),
            )
            .map(VoiceModel.fromMap)
            .where((voice) => voice.locale.isNotEmpty && voice.isInstalled)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));

    _voices = voiceMaps;
  }

  Future<void> refreshVoices() async {
    if (_useOfflineVoice || _switchingVoice || _isInitializing) return;
    try {
      final previous = _selectedVoice;
      await _loadVoices();
      _selectedVoice =
          _voices
              .where((v) => v.matchesIdentity(previous?.name, previous?.locale))
              .firstOrNull ??
          _defaultVoiceForLanguage(_selectedLanguage);
      if (_selectedVoice != null) _selectedLanguage = _selectedVoice!.locale;
      _errorMessage = null;
    } catch (_) {
      _errorMessage =
          'Could not refresh Android voices. Check your system TTS settings.';
    }
    notifyListeners();
  }

  Future<void> selectBestInstalledVoice() async {
    if (_useOfflineVoice) return;
    final candidates = _voices
        .where(
          (v) =>
              v.requiresNetwork != true &&
              _normalizeLocale(v.locale) == _normalizeLocale(_selectedLanguage),
        )
        .toList();
    candidates.sort((a, b) {
      final availability = (a.requiresNetwork == false ? 0 : 1).compareTo(
        b.requiresNetwork == false ? 0 : 1,
      );
      return availability != 0
          ? availability
          : (b.qualityScore ?? 0).compareTo(a.qualityScore ?? 0);
    });
    if (candidates.isNotEmpty) {
      await setVoice(candidates.first);
    } else {
      _errorMessage =
          'No offline voice was found for this language. You can choose an online voice explicitly from the voice list.';
      notifyListeners();
    }
  }

  Future<void> _stopSpeech() async {
    if (_useOfflineVoice) {
      await _offlineEngine?.stop();
    } else {
      await _flutterTts.stop();
    }
  }

  void _prepareOfflineCallbacks() {
    _offlineEngine ??= OfflineSpeechEngine();
    _offlineEngine!.onStart = () {
      if (!_useOfflineVoice ||
          !isPlaying ||
          _queuedChunks.isEmpty ||
          _isDisposed) {
        return;
      }
      _chunkStarted = true;
      _markPlaybackActivity();
      notifyListeners();
    };
    _offlineEngine!.onActivity = () {
      if (_useOfflineVoice && isPlaying) {
        _markPlaybackActivity(resetRecoveryAttempts: true);
      }
    };
    _offlineEngine!.onComplete = () {
      if (!_useOfflineVoice ||
          !isPlaying ||
          _queuedChunks.isEmpty ||
          _isDisposed) {
        return;
      }
      _chunkStarted = false;
      unawaited(_handleChunkCompleted());
    };
    _offlineEngine!.onError = (error) {
      if (_useOfflineVoice) unawaited(_handlePlaybackError(error));
    };
  }

  Future<void> setOfflineVoiceEnabled(bool enabled) async {
    if (_switchingVoice || enabled == _useOfflineVoice) return;
    if (enabled && (!supportsOfflineVoice || !modelStore.ready)) return;
    _switchingVoice = true;
    notifyListeners();
    final previousProvider = _useOfflineVoice ? OfflineVoicePack.id : 'android';
    try {
      if (isPlaying) await pause();
      await _storageService.saveProviderVoice(
        previousProvider,
        _selectedVoice?.name,
        _selectedVoice?.locale,
      );
      await _stopSpeech();
      ++_sessionId;
      _queuedChunks = const [];
      _queuedEndOffset = null;
      _useOfflineVoice = enabled;
      if (enabled) {
        _prepareOfflineCallbacks();
        _voices = [
          for (final locale in OfflineVoicePack.languages)
            for (final gender in ['F', 'M'])
              for (var i = 1; i <= 5; i++)
                VoiceModel(
                  name: '$gender$i',
                  locale: locale,
                  label: 'Supertonic ${gender == 'F' ? 'Female' : 'Male'} $i',
                  personaLabel: gender == 'F' ? 'Female' : 'Male',
                  metadataLabels: const ['Offline', 'Neural'],
                  requiresNetwork: false,
                ),
        ];
      } else {
        await _offlineEngine?.unload();
        await _loadVoices();
      }
      final provider = enabled ? OfflineVoicePack.id : 'android';
      final name = _storageService.providerVoiceName(provider);
      final locale = _storageService.providerVoiceLocale(provider);
      _selectedVoice =
          _voices.where((v) => v.matchesIdentity(name, locale)).firstOrNull ??
          (enabled
              ? _voices.first
              : _defaultVoiceForLanguage(_defaultLanguage));
      _selectedLanguage = _selectedVoice?.locale ?? _defaultLanguage;
      await _storageService.saveSpeechProvider(provider);
      await _storageService.saveVoice(
        _selectedVoice?.name,
        _selectedVoice?.locale,
      );
      await _storageService.saveLanguage(_selectedLanguage);
      await _syncTtsOptions();
      _errorMessage = null;
    } catch (_) {
      _errorMessage =
          'Could not change speech engine. Try Android voices or restart the app.';
    } finally {
      _switchingVoice = false;
      notifyListeners();
    }
  }

  Future<void> removeOfflineVoicePack() async {
    if (modelStore.downloading) return;
    if (_useOfflineVoice) await setOfflineVoiceEnabled(false);
    await _offlineEngine?.unload();
    await modelStore.remove();
  }

  Future<void> _applyStoredSelections() async {
    final restoringOffline =
        _storageService.speechProvider == OfflineVoicePack.id;
    final storedLanguage = restoringOffline
        ? _storageService.providerVoiceLocale('android')
        : _storageService.language;
    final storedVoiceName = restoringOffline
        ? _storageService.providerVoiceName('android')
        : _storageService.voiceName;
    final storedVoiceLocale = restoringOffline
        ? _storageService.providerVoiceLocale('android')
        : _storageService.voiceLocale;
    final defaultLanguage = _preferredLanguageFromVoices();

    _selectedLanguage = storedLanguage ?? defaultLanguage ?? _defaultLanguage;

    _selectedVoice = _voices.cast<VoiceModel?>().firstWhere(
      (voice) => voice!.matchesIdentity(storedVoiceName, storedVoiceLocale),
      orElse: () => _defaultVoiceForLanguage(_selectedLanguage),
    );

    if (_selectedVoice != null) {
      _selectedLanguage = _selectedVoice!.locale;
    }
  }

  String? _preferredLanguageFromVoices() {
    final exactEnglishIndia = _voices.firstWhere(
      (voice) =>
          _normalizeLocale(voice.locale) == _normalizeLocale(_defaultLanguage),
      orElse: () => const VoiceModel(name: '', locale: '', label: ''),
    );
    if (exactEnglishIndia.locale.isNotEmpty) {
      return exactEnglishIndia.locale;
    }

    final preferred = _voices
        .where((voice) => _isEnglishIndia(voice.locale))
        .map((voice) => voice.locale)
        .toList();
    if (preferred.isNotEmpty) {
      return preferred.first;
    }
    return _voices.isNotEmpty ? _voices.first.locale : null;
  }

  VoiceModel? _defaultVoiceForLanguage(String language) {
    if (_voices.isEmpty) {
      return null;
    }

    final normalizedLanguage = _normalizeLocale(language);
    final candidates = _voices.where((voice) {
      final voiceLocale = _normalizeLocale(voice.locale);
      return voiceLocale == normalizedLanguage ||
          voiceLocale.startsWith('$normalizedLanguage-');
    }).toList();

    if (candidates.isEmpty) {
      if (_isEnglishIndia(language)) {
        return _voices.firstWhere(
          (voice) => _isEnglishIndia(voice.locale),
          orElse: () => _voices.first,
        );
      }
      return _voices.first;
    }

    candidates.sort((a, b) {
      return _voicePreferenceScore(
        b,
        normalizedLanguage,
      ).compareTo(_voicePreferenceScore(a, normalizedLanguage));
    });
    return candidates.first;
  }

  bool _isEnglishIndia(String locale) {
    final normalized = _normalizeLocale(locale);
    return normalized == 'en-in' || normalized.startsWith('en-in-');
  }

  String _normalizeLocale(String locale) {
    return locale.toLowerCase().replaceAll('_', '-');
  }

  String _normalizeVoiceName(String name) {
    return name.toLowerCase().replaceAll('_', '-');
  }

  int _voicePreferenceScore(VoiceModel voice, String normalizedLanguage) {
    final normalizedLocale = _normalizeLocale(voice.locale);
    final normalizedName = _normalizeVoiceName(voice.name);
    var score = voice.requiresNetwork == false ? 10000 : 0;

    if (normalizedLocale == normalizedLanguage) {
      score += 1000;
    }
    if (normalizedLocale.startsWith('$normalizedLanguage-')) {
      score += 250;
    }

    if (normalizedLanguage == _normalizeLocale(_defaultLanguage)) {
      if (normalizedName.contains(_defaultVoicePattern)) {
        score += 5000;
      }
      if (normalizedName.contains('en-in-x-ene')) {
        score += 4000;
      }
      if (normalizedName.contains('en-in-x')) {
        score += 3000;
      }
      if (normalizedName.contains('local')) {
        score += 300;
      }
      if (normalizedName.contains('google')) {
        score += 200;
      }
    }

    for (final label in voice.metadataLabels) {
      final normalizedLabel = label.toLowerCase();
      if (normalizedLabel.contains('high')) {
        score += 80;
      }
      if (normalizedLabel.contains('low')) {
        score -= 10;
      }
    }

    return score;
  }

  Future<void> _syncTtsOptions() async {
    if (_useOfflineVoice) return;
    if (!_engineReady) {
      return;
    }

    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setVolume(_volume);

    if (_selectedVoice != null) {
      await _flutterTts.setVoice(_selectedVoice!.toTtsMap());
    }
  }

  Future<void> updateText(
    String value, {
    bool resetPosition = false,
    int? initialPosition,
  }) async {
    if (value == _text && !resetPosition && initialPosition == null) return;
    if (isPlaying || isPaused) await stop();
    _text = value;
    _readerText = ReaderText(value);
    _errorMessage = null;
    if (initialPosition != null) {
      _currentCharIndex = initialPosition.clamp(0, _text.length);
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      _activeChunkOffset = _currentCharIndex;
      _pausedCharIndex = _currentCharIndex;
    } else if (resetPosition || _currentCharIndex > _text.length) {
      _currentCharIndex = 0;
      _currentParagraphIndex = 0;
      _activeChunkOffset = 0;
      _pausedCharIndex = 0;
    } else {
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      _pausedCharIndex = min(_currentCharIndex, _text.length);
    }

    await _storageService.saveText(value);
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();
  }

  Future<void> importTextFile() async {
    final imported = await _fileImportService.importTextFile();
    if (imported == null || imported.trim().isEmpty) {
      return;
    }

    await stop();
    await updateText(imported.trim(), resetPosition: true);
  }

  Future<void> handleSharedText(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await stop();
    await updateText(trimmed, resetPosition: true);
  }

  Future<void> setLanguage(String value) async {
    if (_switchingVoice) return;
    if (isPlaying || isPaused) await pause();
    _selectedLanguage = value;
    _selectedVoice = _defaultVoiceForLanguage(value);
    if (_useOfflineVoice) await _offlineEngine?.stop();
    _errorMessage = null;
    await _storageService.saveLanguage(value);
    await _storageService.saveVoice(
      _selectedVoice?.name,
      _selectedVoice?.locale,
    );
    await _storageService.saveProviderVoice(
      _useOfflineVoice ? OfflineVoicePack.id : 'android',
      _selectedVoice?.name,
      _selectedVoice?.locale,
    );
    await _syncTtsOptions();
    notifyListeners();
  }

  Future<void> setVoice(VoiceModel? voice, {bool confirmOnline = false}) async {
    if (_switchingVoice) return;
    if (voice?.requiresNetwork == true) {
      if (confirmOnline) {
        await _storageService.approveOnlineVoice(voice!.name, voice.locale);
      } else if (!_storageService.isOnlineVoiceApproved(
        voice!.name,
        voice.locale,
      )) {
        _errorMessage =
            'Choose this online voice from Settings to confirm internet use first.';
        notifyListeners();
        return;
      }
    }
    if (isPlaying || isPaused) await pause();
    if (_useOfflineVoice) await _offlineEngine?.stop();
    _selectedVoice = voice;
    _errorMessage = null;
    if (voice != null) {
      _selectedLanguage = voice.locale;
      await _storageService.saveLanguage(voice.locale);
    }
    await _storageService.saveVoice(voice?.name, voice?.locale);
    await _storageService.saveProviderVoice(
      _useOfflineVoice ? OfflineVoicePack.id : 'android',
      voice?.name,
      voice?.locale,
    );
    await _syncTtsOptions();
    notifyListeners();
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value;
    await _storageService.saveRate(value);
    if (!_useOfflineVoice) await _flutterTts.setSpeechRate(value);
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    _pitch = value;
    await _storageService.savePitch(value);
    if (!_useOfflineVoice) await _flutterTts.setPitch(value);
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value;
    await _storageService.saveVolume(value);
    if (_useOfflineVoice) {
      await _offlineEngine?.setVolume(value);
    } else {
      await _flutterTts.setVolume(value);
    }
    notifyListeners();
  }

  Future<void> resetSettings() async {
    if (_useOfflineVoice) await setOfflineVoiceEnabled(false);
    _selectedLanguage = _preferredLanguageFromVoices() ?? _defaultLanguage;
    _selectedVoice = _defaultVoiceForLanguage(_selectedLanguage);
    _speechRate = _defaultSpeechRate;
    _pitch = _defaultPitch;
    _volume = _defaultVolume;
    _errorMessage = null;

    await _storageService.resetTtsSettings();
    await _storageService.saveLanguage(_selectedLanguage);
    await _storageService.saveVoice(
      _selectedVoice?.name,
      _selectedVoice?.locale,
    );
    await _storageService.saveRate(_speechRate);
    await _storageService.savePitch(_pitch);
    await _storageService.saveVolume(_volume);
    await _syncTtsOptions();
    notifyListeners();
  }

  Future<void> play() async {
    if (isPlaying || _isDisposed || _switchingVoice) return;
    if (isPaused) {
      await _resumePlayback();
      return;
    }

    await _playInternal(
      startOffset: _currentCharIndex,
      endOffset: null,
      triggerCompletionHandler: true,
      resetPositionOnComplete: true,
    );
  }

  Future<void> playSelection(TextSelection selection) async {
    final normalizedSelection = _normalizedSelection(selection);
    if (normalizedSelection == null) {
      _errorMessage = 'Select some text before using Play selection.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    _currentCharIndex = normalizedSelection.start;
    _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();

    await _playInternal(
      startOffset: normalizedSelection.start,
      endOffset: normalizedSelection.end,
      triggerCompletionHandler: false,
      resetPositionOnComplete: false,
    );
  }

  Future<void> playFromParagraph(int paragraphIndex) async {
    if (paragraphIndex < 0 || paragraphIndex >= paragraphCount) {
      return;
    }

    final paragraphOffset = _offsetForParagraph(paragraphIndex);
    _currentCharIndex = paragraphOffset;
    _currentParagraphIndex = paragraphIndex;
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();

    await _playInternal(
      startOffset: paragraphOffset,
      endOffset: null,
      triggerCompletionHandler: true,
      resetPositionOnComplete: true,
    );
  }

  Future<void> playPreviousParagraph() async {
    if (paragraphCount == 0 || _currentParagraphIndex <= 0) {
      return;
    }
    await playFromParagraph(_currentParagraphIndex - 1);
  }

  Future<void> playNextParagraph() async {
    if (paragraphCount == 0 || _currentParagraphIndex >= paragraphCount - 1) {
      return;
    }
    await playFromParagraph(_currentParagraphIndex + 1);
  }

  Future<void> _resumePlayback() async {
    if (_useOfflineVoice && _offlineEngine?.active == true) {
      final session = ++_sessionId;
      if (!await _activateAudioSession() || session != _sessionId) return;
      _playbackState = ReaderPlaybackState.playing;
      _chunkStarted = true;
      _markPlaybackActivity(resetRecoveryAttempts: true);
      _startPlaybackWatchdog();
      notifyListeners();
      try {
        if (await _offlineEngine!.resume()) return;
      } catch (_) {
        // Regenerate the saved segment if the native audio cache was released.
      }
      if (!_isPlaybackSessionActive(session)) return;
    }
    final resumeOffset = min(
      max(_pausedCharIndex, _activeChunkOffset),
      _text.length,
    );
    await _playInternal(
      startOffset: resumeOffset,
      endOffset: _queuedEndOffset,
      triggerCompletionHandler: _queuedTriggerCompletionHandler,
      resetPositionOnComplete: _queuedResetPositionOnComplete,
      shouldStopBeforeQueueing: false,
    );
  }

  Future<void> _playInternal({
    required int startOffset,
    required int? endOffset,
    required bool triggerCompletionHandler,
    required bool resetPositionOnComplete,
    bool shouldStopBeforeQueueing = true,
    bool isRecovery = false,
  }) async {
    if (_switchingVoice) return;
    final voice = _selectedVoice;
    if (!_useOfflineVoice &&
        voice?.requiresNetwork == true &&
        !_storageService.isOnlineVoiceApproved(voice!.name, voice.locale)) {
      _errorMessage =
          'This voice requires internet. Choose it from Settings to confirm online speech, or select an offline voice.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }
    if (!_engineReady && !_useOfflineVoice) {
      _errorMessage =
          'Android text-to-speech is not available. Install or enable a TTS engine first.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    if (_voices.isEmpty) {
      _errorMessage =
          'No installed TTS voices were found. Add a voice in Android system settings and try again.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    final trimmed = _text.trim();
    if (trimmed.isEmpty) {
      _errorMessage = 'Add or import some text before starting playback.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    final chunks = _buildChunks(
      _text,
      startOffset: startOffset,
      endOffset: endOffset,
    );
    if (chunks.isEmpty) {
      _playbackState = ReaderPlaybackState.completed;
      _currentCharIndex = resetPositionOnComplete ? 0 : startOffset;
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      await _storageService.savePosition(_currentCharIndex);
      notifyListeners();
      return;
    }

    final localSession = ++_sessionId;
    final activated = await _activateAudioSession();
    if (localSession != _sessionId || _isDisposed) return;
    if (!activated) {
      _errorMessage =
          'DhebeVoice could not take audio focus right now. Try again after other audio stops.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _chunkStarted = false;
    _cancelUnexpectedPauseRecovery();
    _pauseOrigin = _PauseOrigin.none;
    _playbackState = ReaderPlaybackState.playing;
    _queuedChunks = chunks;
    _queuedChunkIndex = 0;
    _queuedEndOffset = endOffset;
    _queuedResetPositionOnComplete = resetPositionOnComplete;
    _queuedTriggerCompletionHandler = triggerCompletionHandler;
    _activeChunkOffset = chunks.first.start;
    _pausedCharIndex = startOffset;
    _currentParagraphIndex = chunks.first.paragraphIndex;
    _markPlaybackActivity(resetRecoveryAttempts: !isRecovery);
    _startPlaybackWatchdog();
    notifyListeners();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(AudioService.androidForceEnableMediaButtons());
    }

    await _syncTtsOptions();
    if (!_isPlaybackSessionActive(localSession)) return;
    if (shouldStopBeforeQueueing) {
      await _stopSpeech();
    }
    if (!_isPlaybackSessionActive(localSession)) return;

    final started = await _startCurrentChunk(localSession);
    if (!started && _isPlaybackSessionActive(localSession)) {
      await _handlePlaybackError(
        (_useOfflineVoice ? _offlineEngine?.lastError : null) ??
            'DhebeVoice could not start the selected voice. Try another installed voice.',
      );
    }
  }

  Future<bool> _startCurrentChunk(int sessionId) async {
    if (_queuedChunks.isEmpty || _queuedChunkIndex >= _queuedChunks.length) {
      return false;
    }
    if (!_isPlaybackSessionActive(sessionId)) {
      return false;
    }

    final chunk = _queuedChunks[_queuedChunkIndex];
    _activeChunkOffset = chunk.start;
    _currentParagraphIndex = chunk.paragraphIndex;
    if (_useOfflineVoice) {
      _currentCharIndex = chunk.start;
      _pausedCharIndex = chunk.start;
      _chunkStarted = false;
      final started = await _offlineEngine!.speak(
        directory: modelStore.directoryPath!,
        text: chunk.text,
        voice: _selectedVoice?.name ?? 'F1',
        language: _selectedLanguage,
        speed: (_speechRate / 0.48).clamp(0.5, 2.0),
        volume: _volume,
      );
      return _isPlaybackSessionActive(sessionId) && started;
    }

    await _flutterTts.setQueueMode(0);
    if (!_isPlaybackSessionActive(sessionId)) return false;
    _chunkStarted = false;
    final result = await _flutterTts.speak(chunk.text, focus: false);
    return _isPlaybackSessionActive(sessionId) && result == 1;
  }

  Future<void> _handleChunkCompleted() async {
    if (_queuedChunks.isEmpty ||
        _playbackState != ReaderPlaybackState.playing) {
      return;
    }

    final session = _sessionId;
    if (_completingSession == session) return;
    _completingSession = session;
    try {
      final completedIndex = min(_queuedChunkIndex, _queuedChunks.length - 1);
      final completedChunk = _queuedChunks[completedIndex];
      _currentCharIndex = completedChunk.end;
      _pausedCharIndex = min(_currentCharIndex, _text.length);
      _currentParagraphIndex = completedChunk.paragraphIndex;
      await _storageService.savePosition(_currentCharIndex);
      if (!_isPlaybackSessionActive(session)) return;

      if (completedIndex < _queuedChunks.length - 1) {
        _queuedChunkIndex = completedIndex + 1;
        final nextChunk = _queuedChunks[_queuedChunkIndex];
        _activeChunkOffset = nextChunk.start;
        _currentParagraphIndex = nextChunk.paragraphIndex;
        notifyListeners();
        final localSession = _sessionId;
        final started = await _startCurrentChunk(localSession);
        if (!started && _isPlaybackSessionActive(localSession)) {
          await _recoverFromPlaybackStall();
        }
        return;
      }

      final triggerCompletionHandler = _queuedTriggerCompletionHandler;
      final resetPositionOnComplete = _queuedResetPositionOnComplete;
      final finalOffset = _queuedEndOffset ?? _queuedChunks.last.end;

      _queuedChunks = const [];
      _queuedChunkIndex = 0;
      _queuedEndOffset = null;
      _resumeAfterInterruption = false;
      _cancelUnexpectedPauseRecovery();
      _stopPlaybackWatchdog();
      await _audioSession?.setActive(false);
      if (!_isPlaybackSessionActive(session)) return;

      _playbackState = ReaderPlaybackState.completed;
      _currentCharIndex = resetPositionOnComplete
          ? 0
          : min(finalOffset, _text.length);
      _pausedCharIndex = _currentCharIndex;
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      await _storageService.savePosition(_currentCharIndex);
      if (session != _sessionId || _isDisposed) return;
      notifyListeners();

      final handler = _playbackCompletedHandler;
      if (triggerCompletionHandler && handler != null) {
        await handler();
      }
    } catch (error) {
      if (session == _sessionId && !_isDisposed) {
        await _handlePlaybackError(error);
      }
    } finally {
      if (_completingSession == session) _completingSession = null;
    }
  }

  Future<void> _handlePlaybackError(dynamic message) async {
    if (_isDisposed ||
        _playbackState == ReaderPlaybackState.paused ||
        _playbackState == ReaderPlaybackState.stopped) {
      return;
    }

    final session = ++_sessionId;
    _chunkStarted = false;
    _queuedChunks = const [];
    _queuedChunkIndex = 0;
    _queuedEndOffset = null;
    _resumeAfterInterruption = false;
    _cancelUnexpectedPauseRecovery();
    _stopPlaybackWatchdog();
    await _audioSession?.setActive(false);
    if (session != _sessionId || _isDisposed) return;

    _playbackState = ReaderPlaybackState.error;
    _errorMessage = _friendlyPlaybackError(message);
    if (_useOfflineVoice) await _offlineEngine?.stop();
    _pausedCharIndex = min(
      max(_currentCharIndex, _activeChunkOffset),
      _text.length,
    );
    notifyListeners();
  }

  String _friendlyPlaybackError(dynamic message) {
    final raw = message?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return 'DhebeVoice could not continue playback. Try another installed voice.';
    }
    if (raw.toLowerCase().contains('selected voice')) {
      return raw;
    }
    if (raw.toLowerCase().contains('error from texttospeech')) {
      return 'DhebeVoice could not continue with the selected voice. Try another installed voice.';
    }
    return raw;
  }

  Future<bool> _activateAudioSession() async {
    final session = _audioSession;
    if (session == null) {
      return true;
    }
    return session.setActive(true);
  }

  bool _isPlaybackSessionActive(int sessionId) {
    return sessionId == _sessionId &&
        !_isDisposed &&
        _playbackState == ReaderPlaybackState.playing;
  }

  Future<void> pause({bool fromSystemInterruption = false}) async {
    if (!isPlaying) {
      return;
    }

    if (!fromSystemInterruption) {
      _resumeAfterInterruption = false;
    }
    _pauseOrigin = fromSystemInterruption
        ? _PauseOrigin.system
        : _PauseOrigin.user;
    _cancelUnexpectedPauseRecovery();
    _sessionId++;
    _chunkStarted = false;
    _pausedCharIndex = min(
      max(_currentCharIndex, _activeChunkOffset),
      _text.length,
    );
    _currentCharIndex = _pausedCharIndex;
    _stopPlaybackWatchdog();
    _playbackState = ReaderPlaybackState.paused;
    _errorMessage = null;
    if (_useOfflineVoice) {
      await _offlineEngine?.pause();
    } else {
      await _flutterTts.pause();
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(AudioService.androidForceEnableMediaButtons());
    }
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();
  }

  Future<void> stop() async {
    _sessionId++;
    _chunkStarted = false;
    _queuedChunks = const [];
    _queuedChunkIndex = 0;
    _queuedEndOffset = null;
    _resumeAfterInterruption = false;
    _cancelUnexpectedPauseRecovery();
    _pauseOrigin = _PauseOrigin.none;
    _stopPlaybackWatchdog();
    _playbackState = ReaderPlaybackState.stopped;
    _errorMessage = null;
    _currentCharIndex = 0;
    _currentParagraphIndex = 0;
    _activeChunkOffset = 0;
    _pausedCharIndex = 0;
    await _stopSpeech();
    await _audioSession?.setActive(false);
    await _storageService.savePosition(0);
    notifyListeners();
  }

  List<String> availableLanguages() {
    final locales = _voices.map((voice) => voice.locale).toSet().toList()
      ..sort();
    return locales;
  }

  int _paragraphIndexForOffset(int offset) {
    return _readerText.paragraphIndexForOffset(offset);
  }

  List<SpeechChunk> _buildChunks(
    String source, {
    required int startOffset,
    int? endOffset,
  }) {
    return _readerText.chunks(
      startOffset: startOffset,
      endOffset: endOffset,
      maxChunkLength: _useOfflineVoice ? 240 : 2800,
    );
  }

  TextSelection? _normalizedSelection(TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed || _text.isEmpty) {
      return null;
    }

    final start = min(selection.start, selection.end);
    final end = max(selection.start, selection.end);
    if (start < 0 || end > _text.length || start >= end) {
      return null;
    }

    return TextSelection(baseOffset: start, extentOffset: end);
  }

  int _offsetForParagraph(int targetIndex) {
    return _readerText.offsetForParagraph(targetIndex);
  }

  void _markPlaybackActivity({bool resetRecoveryAttempts = false}) {
    _lastPlaybackActivityAt = DateTime.now();
    if (resetRecoveryAttempts) {
      _stallRecoveryAttempts = 0;
    }
  }

  void _startPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = Timer.periodic(_watchdogCheckInterval, (_) {
      unawaited(_handlePlaybackWatchdogTick());
    });
  }

  void _cancelUnexpectedPauseRecovery() {
    _unexpectedPauseRecoveryTimer?.cancel();
    _unexpectedPauseRecoveryTimer = null;
  }

  void _scheduleUnexpectedPauseRecovery() {
    _cancelUnexpectedPauseRecovery();
    _unexpectedPauseRecoveryTimer = Timer(const Duration(seconds: 2), () {
      if (_playbackState != ReaderPlaybackState.paused ||
          _queuedChunks.isEmpty ||
          _resumeAfterInterruption) {
        return;
      }

      unawaited(_resumePlayback());
    });
  }

  void _stopPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
    _cancelUnexpectedPauseRecovery();
    _lastPlaybackActivityAt = null;
    _stallRecoveryAttempts = 0;
    _isRecoveringFromStall = false;
  }

  Future<void> _handlePlaybackWatchdogTick() async {
    if (!isPlaying || _queuedChunks.isEmpty || _isRecoveringFromStall) {
      return;
    }

    if (_appLifecycleState == AppLifecycleState.paused ||
        _appLifecycleState == AppLifecycleState.inactive ||
        _appLifecycleState == AppLifecycleState.hidden) {
      return;
    }

    final lastPlaybackActivityAt = _lastPlaybackActivityAt;
    if (lastPlaybackActivityAt == null) {
      return;
    }

    final timeout = _useOfflineVoice && _offlineEngine?.generating == true
        ? const Duration(minutes: 3)
        : _watchdogTimeout;
    if (DateTime.now().difference(lastPlaybackActivityAt) < timeout) {
      return;
    }

    if (_stallRecoveryAttempts >= 2) {
      await _handlePlaybackError(
        'DhebeVoice lost playback unexpectedly. Tap Resume to continue from the last paragraph.',
      );
      return;
    }

    await _recoverFromPlaybackStall();
  }

  Future<void> _recoverFromPlaybackStall() async {
    if (_isRecoveringFromStall) {
      return;
    }

    _isRecoveringFromStall = true;
    _stallRecoveryAttempts++;

    try {
      final resumeOffset = min(
        max(_currentCharIndex, _activeChunkOffset),
        _text.length,
      );

      await _playInternal(
        startOffset: resumeOffset,
        endOffset: _queuedEndOffset,
        triggerCompletionHandler: _queuedTriggerCompletionHandler,
        resetPositionOnComplete: _queuedResetPositionOnComplete,
        isRecovery: true,
      );
    } finally {
      _isRecoveringFromStall = false;
    }
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    _appLifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      await _storageService.savePosition(_currentCharIndex);
    }

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        state == AppLifecycleState.resumed &&
        (_playbackState == ReaderPlaybackState.playing ||
            _playbackState == ReaderPlaybackState.paused)) {
      unawaited(AudioService.androidForceEnableMediaButtons());
    }

    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sessionId++;
    _interruptionSubscription?.cancel();
    _becomingNoisySubscription?.cancel();
    _playbackWatchdog?.cancel();
    _unexpectedPauseRecoveryTimer?.cancel();
    unawaited(_flutterTts.stop());
    unawaited(_offlineEngine?.dispose());
    modelStore.dispose();
    super.dispose();
  }
}
