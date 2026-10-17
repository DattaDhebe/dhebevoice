import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/novel_book.dart';
import 'novel_import_controller.dart';
import 'tts_service.dart';

class ReaderAudioHandler extends BaseAudioHandler {
  ReaderAudioHandler({
    required TtsService ttsService,
    required NovelImportController novelImportController,
  }) : _ttsService = ttsService,
       _novelImportController = novelImportController {
    _ttsService.addListener(_broadcastReaderState);
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
  (ReaderPlaybackState, int, bool, bool, bool, bool, String?)?
  _lastPlaybackSnapshot;
  Future<void> _navigation = Future<void>.value();
  int _commandRevision = 0;

  @override
  Future<void> play() {
    _commandRevision++;
    return _ttsService.play();
  }

  @override
  Future<void> pause() {
    _commandRevision++;
    return _ttsService.pause();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final isPlaying = _ttsService.isPlaying || _ttsService.isAdvancingChapter;
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
    _commandRevision++;
    await _ttsService.stop();
  }

  @override
  Future<void> skipToNext() =>
      _navigate(() => _novelImportController.goToNextChapter());

  @override
  Future<void> skipToPrevious() =>
      _navigate(() => _novelImportController.goToPreviousChapter());

  @override
  Future<void> skipToQueueItem(int index) => _navigate(() async {
    final book = _novelImportController.activeNovel;
    if (book == null || index < 0 || index >= book.chapters.length) return;
    await _novelImportController.selectChapter(
      index,
      resumePlayback: _ttsService.isPlaying || _ttsService.isAdvancingChapter,
    );
  });

  Future<void> _navigate(Future<void> Function() action) {
    final revision = _commandRevision;
    final operation = _navigation.then((_) async {
      if (revision == _commandRevision) await action();
    });
    _navigation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _broadcastReaderState() {
    _broadcastLibraryState();
    _broadcastPlaybackState();
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
      _ttsService.isBuffering,
      _ttsService.isAdvancingChapter,
      _ttsService.errorMessage,
    );
    if (_lastPlaybackSnapshot == snapshot) return;
    _lastPlaybackSnapshot = snapshot;

    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      (_ttsService.isPlaying || _ttsService.isAdvancingChapter)
          ? MediaControl.pause
          : MediaControl.play,
      MediaControl.stop,
      if (hasNext) MediaControl.skipToNext,
    ];

    final processingState = _ttsService.isBuffering
        ? AudioProcessingState.buffering
        : switch (_ttsService.playbackState) {
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
        systemActions: {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          if (hasNext) MediaAction.skipToNext,
          if (hasPrevious) MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: compactActionIndices,
        processingState: processingState,
        playing: _ttsService.isPlaying || _ttsService.isAdvancingChapter,
        errorCode: processingState == AudioProcessingState.error ? 1 : null,
        errorMessage: _ttsService.errorMessage,
        queueIndex: activeNovel == null
            ? 0
            : _novelImportController.activeChapterIndex,
      ),
    );

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (_ttsService.isPlaying || _ttsService.isPaused)) {
      unawaited(_ttsService.refreshMediaButtons());
    }
  }
}
