import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/novel_book.dart';
import 'novel_import_controller.dart';
import 'tts_service.dart';

class ReaderAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  ReaderAudioHandler({
    required TtsService ttsService,
    required NovelImportController novelImportController,
  }) : _ttsService = ttsService,
       _novelImportController = novelImportController {
    _ttsService.addListener(_broadcastPlaybackState);
    _novelImportController.addListener(_broadcastLibraryState);
    _broadcastLibraryState();
    _broadcastPlaybackState();
  }

  final TtsService _ttsService;
  final NovelImportController _novelImportController;
  List<NovelChapter>? _lastChapters;
  String? _lastBookId;
  String? _lastBookTitle;
  int? _lastChapterIndex;
  String? _lastLanguage;
  (ReaderPlaybackState, int, bool, bool)? _lastPlaybackSnapshot;

  @override
  Future<void> play() => _ttsService.play();

  @override
  Future<void> pause() => _ttsService.pause();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final isPlaying = playbackState.value.playing;
    switch (button) {
      case MediaButton.media:
        if (isPlaying) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  @override
  Future<void> stop() async {
    await _ttsService.stop();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    final canAdvance =
        _novelImportController.activeNovel != null &&
        _novelImportController.activeChapterIndex <
            _novelImportController.activeNovel!.chapters.length - 1;
    if (!canAdvance) {
      return;
    }

    final shouldResume = _ttsService.isPlaying;
    final change = _novelImportController.goToNextChapter();
    final session = _ttsService.playbackSessionId;
    await change;
    if (shouldResume && session == _ttsService.playbackSessionId) {
      await _ttsService.play();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_novelImportController.activeNovel == null ||
        _novelImportController.activeChapterIndex <= 0) {
      return;
    }

    final shouldResume = _ttsService.isPlaying;
    final change = _novelImportController.goToPreviousChapter();
    final session = _ttsService.playbackSessionId;
    await change;
    if (shouldResume && session == _ttsService.playbackSessionId) {
      await _ttsService.play();
    }
  }

  void _broadcastLibraryState() {
    final activeNovel = _novelImportController.activeNovel;
    final chapterIndex = _novelImportController.activeChapterIndex;
    final libraryChanged =
        !identical(_lastChapters, activeNovel?.chapters) ||
        _lastBookId != activeNovel?.id ||
        _lastBookTitle != activeNovel?.title;
    if (!libraryChanged &&
        _lastChapterIndex == chapterIndex &&
        _lastLanguage == _ttsService.selectedLanguage) {
      return;
    }
    _lastChapters = activeNovel?.chapters;
    _lastBookId = activeNovel?.id;
    _lastBookTitle = activeNovel?.title;
    _lastChapterIndex = chapterIndex;
    _lastLanguage = _ttsService.selectedLanguage;

    if (activeNovel == null || activeNovel.chapters.isEmpty) {
      queue.add(const <MediaItem>[]);
      mediaItem.add(
        MediaItem(
          id: 'manual-text',
          album: 'DhebeVoice',
          title: 'Manual text',
          artist: _ttsService.selectedLanguage,
        ),
      );
      _broadcastPlaybackState();
      return;
    }

    final items = libraryChanged
        ? activeNovel.chapters
              .map(
                (chapter) =>
                    _chapterToMediaItem(novel: activeNovel, chapter: chapter),
              )
              .toList(growable: false)
        : queue.value;
    if (libraryChanged) queue.add(items);

    final selectedIndex = _novelImportController.activeChapterIndex.clamp(
      0,
      items.length - 1,
    );
    mediaItem.add(items[selectedIndex]);
    _broadcastPlaybackState();
  }

  MediaItem _chapterToMediaItem({
    required NovelBook novel,
    required NovelChapter chapter,
  }) {
    return MediaItem(
      id: chapter.url.isEmpty ? '${novel.id}:${chapter.order}' : chapter.url,
      album: novel.title,
      title: chapter.title,
      artist: 'DhebeVoice',
      displayTitle: chapter.title,
    );
  }

  void _broadcastPlaybackState() {
    final activeNovel = _novelImportController.activeNovel;
    final hasPrevious =
        activeNovel != null && _novelImportController.activeChapterIndex > 0;
    final hasNext =
        activeNovel != null &&
        _novelImportController.activeChapterIndex <
            activeNovel.chapters.length - 1;

    final snapshot = (
      _ttsService.playbackState,
      _novelImportController.activeChapterIndex,
      hasPrevious,
      hasNext,
    );
    if (_lastPlaybackSnapshot == snapshot) return;
    _lastPlaybackSnapshot = snapshot;

    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      _ttsService.isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      if (hasNext) MediaControl.skipToNext,
    ];

    final processingState = switch (_ttsService.playbackState) {
      ReaderPlaybackState.idle => AudioProcessingState.idle,
      ReaderPlaybackState.stopped => AudioProcessingState.idle,
      ReaderPlaybackState.playing ||
      ReaderPlaybackState.paused => AudioProcessingState.ready,
      ReaderPlaybackState.completed => AudioProcessingState.completed,
      ReaderPlaybackState.error => AudioProcessingState.error,
    };

    final playPauseIndex = controls.indexWhere(
      (control) =>
          control == MediaControl.play || control == MediaControl.pause,
    );
    final stopIndex = controls.indexOf(MediaControl.stop);
    final nextIndex = controls.indexOf(MediaControl.skipToNext);
    final previousIndex = controls.indexOf(MediaControl.skipToPrevious);

    final compactActionIndices = <int>[
      if (playPauseIndex >= 0) playPauseIndex,
      if (stopIndex >= 0) stopIndex,
      if (nextIndex >= 0) nextIndex else if (previousIndex >= 0) previousIndex,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: compactActionIndices,
        processingState: processingState,
        playing: _ttsService.isPlaying,
        queueIndex: activeNovel == null
            ? 0
            : _novelImportController.activeChapterIndex,
      ),
    );

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (_ttsService.isPlaying || _ttsService.isPaused)) {
      unawaited(AudioService.androidForceEnableMediaButtons());
    }
  }
}
