import 'package:flutter/foundation.dart';

import '../models/import_cancellation.dart';
import '../models/novel_book.dart';
import 'file_import_service.dart';
import 'novel_library_service.dart';
import 'storage_service.dart';
import 'tts_service.dart';
import 'web_novel_import_service.dart';

class NovelImportController extends ChangeNotifier {
  NovelImportController({
    required StorageService storageService,
    required FileImportService fileImportService,
    required NovelLibraryService novelLibraryService,
    required WebNovelImportService webNovelImportService,
    required TtsService ttsService,
  }) : _storageService = storageService,
       _fileImportService = fileImportService,
       _novelLibraryService = novelLibraryService,
       _webNovelImportService = webNovelImportService,
       _ttsService = ttsService {
    _ttsService.setPlaybackCompletedHandler(_handlePlaybackCompleted);
  }

  final StorageService _storageService;
  final FileImportService _fileImportService;
  final NovelLibraryService _novelLibraryService;
  final WebNovelImportService _webNovelImportService;
  final TtsService _ttsService;

  List<NovelBook> _library = const [];
  NovelBook? _activeNovel;
  int _activeChapterIndex = 0;
  bool _isImporting = false;
  bool _isCancellingImport = false;
  String? _importStatus;
  String? _errorMessage;
  double? _importProgress;
  String _selectedWebAccessModeId = WebNovelImportService.defaultAccessModeId;
  String? _pendingSharedUrl;
  int _chapterActivationId = 0;
  Future<void>? _initialization;
  bool _libraryReady = false;
  bool _disposed = false;
  ImportCancellation? _cancellation;
  Future<void> _libraryMutation = Future<void>.value();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }

  List<NovelBook> get library => _library;
  NovelBook? get activeNovel => _activeNovel;
  int get activeChapterIndex => _activeChapterIndex;
  bool get isImporting => _isImporting;
  bool get isCancellingImport => _isCancellingImport;
  String? get importStatus => _importStatus;
  String? get errorMessage => _errorMessage;
  double? get importProgress => _importProgress;
  String get selectedWebAccessModeId => _selectedWebAccessModeId;
  String? get pendingSharedUrl => _pendingSharedUrl;
  bool get hasPendingSharedUrl =>
      _pendingSharedUrl != null && _pendingSharedUrl!.trim().isNotEmpty;
  List<WebAccessMode> get availableWebAccessModes =>
      WebNovelImportService.accessModes;

  NovelChapter? get activeChapter =>
      _activeNovel == null || _activeNovel!.chapters.isEmpty
      ? null
      : _activeNovel!.chapters[_activeChapterIndex];

  Future<void> initialize() => _initialization ??= _initializeSafely();

  Future<void> _initializeSafely() async {
    try {
      await _initialize();
    } catch (error) {
      _errorMessage =
          'Could not prepare your Book List. Please try reopening the app.';
      debugPrint('Library initialization failed: $error');
      notifyListeners();
    }
  }

  Future<void> _initialize() async {
    try {
      _library = await _novelLibraryService.loadLibrary();
    } catch (error) {
      _errorMessage =
          'Could not load your Book List. Your saved file has not been changed.';
      debugPrint('Library load failed: $error');
      notifyListeners();
      return;
    }
    _library = _library
        .map(
          (book) => book.copyWith(
            lastReadChapterIndex:
                _storageService.chapterIndexForNovel(book.id) ??
                book.lastReadChapterIndex,
          ),
        )
        .toList();
    if (_library.isEmpty && !_storageService.hasSeededSampleBook) {
      final initial = [_buildSampleBook()];
      await _novelLibraryService.saveLibrary(initial);
      _library = initial;
      await _storageService.saveHasSeededSampleBook(true);
    }
    _libraryReady = true;
    _selectedWebAccessModeId = WebNovelImportService.normalizeAccessModeId(
      _storageService.webAccessModeId,
    );
    final savedNovelId = _storageService.activeNovelId;
    if (savedNovelId == null || savedNovelId.isEmpty) {
      notifyListeners();
      return;
    }

    final novelIndex = _library.indexWhere((entry) => entry.id == savedNovelId);
    if (novelIndex < 0 || _library[novelIndex].chapters.isEmpty) {
      notifyListeners();
      return;
    }

    _activeNovel = _library[novelIndex];
    _activeChapterIndex = _storageService.activeChapterIndex.clamp(
      0,
      _activeNovel!.chapters.length - 1,
    );
    notifyListeners();
  }

  Future<void> handleSharedPayload(String value) async {
    await initialize();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final sharedLink = _sharedLink(trimmed);
    if (sharedLink != null) {
      await queueSharedUrl(sharedLink);
      return;
    }

    await clearActiveNovel();
    await _ttsService.handleSharedText(trimmed);
  }

  Future<void> queueSharedUrl(String url) async {
    _pendingSharedUrl = url.trim();
    if (!_isImporting) {
      _errorMessage = null;
      _importProgress = null;
      _importStatus = 'Shared link ready. Review it, then start import.';
    }
    notifyListeners();
  }

  Future<void> clearPendingSharedUrl() async {
    if (!hasPendingSharedUrl) {
      return;
    }

    _pendingSharedUrl = null;
    if (!_isImporting) {
      _importStatus = null;
      _errorMessage = null;
      _importProgress = null;
    }
    notifyListeners();
  }

  Future<void> importPendingSharedUrl({String? accessModeId}) async {
    final url = _pendingSharedUrl;
    if (url == null || url.trim().isEmpty) {
      return;
    }
    await importNovelFromUrl(url, accessModeId: accessModeId);
  }

  Future<void> setWebAccessMode(String modeId) async {
    final resolvedModeId = WebNovelImportService.normalizeAccessModeId(modeId);
    if (_selectedWebAccessModeId == resolvedModeId) {
      return;
    }

    _selectedWebAccessModeId = resolvedModeId;
    await _storageService.saveWebAccessModeId(resolvedModeId);
    notifyListeners();
  }

  Future<void> importLocalFile() async {
    await initialize();
    if (_isImporting || !_libraryReady || _disposed) return;
    _isImporting = true;
    _isCancellingImport = false;
    final activation = _chapterActivationId;
    final originalText = _ttsService.text;
    _errorMessage = null;
    _importStatus = 'Choose a TXT, EPUB or PDF file...';
    notifyListeners();

    try {
      final imported = await _fileImportService.importReaderFile();
      if (_isCancellingImport || _disposed) {
        _importStatus = 'Import stopped.';
        return;
      }
      if (imported == null) {
        _importStatus = null;
        return;
      }

      switch (imported.kind) {
        case ImportedReaderFileKind.text:
          if (activation != _chapterActivationId ||
              originalText != _ttsService.text) {
            _importStatus =
                'Reader changed while choosing a file. Import the text file again when ready.';
            return;
          }
          await clearActiveNovel();
          await _ttsService.stop();
          await _ttsService.updateText(imported.text!, resetPosition: true);
          _importStatus = 'Imported text file ${imported.name}.';
          break;
        case ImportedReaderFileKind.epub:
        case ImportedReaderFileKind.pdf:
          final book = imported.book!;
          final saved = await _saveImportedBook(book);
          if (!_disposed &&
              !_isCancellingImport &&
              activation == _chapterActivationId &&
              originalText == _ttsService.text &&
              !_ttsService.isPlaying &&
              _activeNovel == null &&
              originalText.trim().isEmpty) {
            await selectNovel(saved.id);
          }
          final importType = switch (imported.kind) {
            ImportedReaderFileKind.epub => 'EPUB',
            ImportedReaderFileKind.pdf => 'PDF',
            ImportedReaderFileKind.text => 'text',
          };
          _importStatus = _isCancellingImport
              ? 'Import stopped. Completed content was saved to Book List.'
              : 'Imported $importType ${book.title} with ${book.chapters.length} sections.';
          break;
      }
    } catch (error) {
      _importStatus = _isCancellingImport
          ? 'Import stopped.'
          : 'Could not import that file.';
      if (!_isCancellingImport) _errorMessage = _friendlyImportError(error);
    } finally {
      _isImporting = false;
      _isCancellingImport = false;
      notifyListeners();
    }
  }

  String? _sharedLink(String value) {
    // Browsers often share a title followed by the URL on a separate line.
    final matches = RegExp(
      r'https?://[^\s<>]+',
      caseSensitive: false,
    ).allMatches(value).toList();
    if (matches.length != 1) return null;
    try {
      return WebNovelImportService.normalizeUri(
        matches.single.group(0)!,
      ).toString();
    } on FormatException {
      return null;
    }
  }

  Future<void> importNovelFromUrl(String url, {String? accessModeId}) async {
    await initialize();
    if (_isImporting || !_libraryReady || _disposed) return;
    _isImporting = true;
    final cancellation = ImportCancellation();
    _cancellation = cancellation;
    final activation = _chapterActivationId;
    final originalText = _ttsService.text;
    final resolvedAccessModeId = WebNovelImportService.normalizeAccessModeId(
      accessModeId ?? _selectedWebAccessModeId,
    );
    _selectedWebAccessModeId = resolvedAccessModeId;
    _isCancellingImport = false;
    _importStatus = 'Connecting to source...';
    _importProgress = null;
    _errorMessage = null;
    notifyListeners();
    var completedWithoutCancellation = false;

    try {
      await _storageService.saveWebAccessModeId(resolvedAccessModeId);
      final result = await _webNovelImportService.importNovelResultFromUrl(
        url,
        accessModeId: resolvedAccessModeId,
        onProgress: (current, total, status) {
          if (_isCancellingImport || _disposed) return;
          _importStatus = status;
          _importProgress = total == null || total == 0
              ? null
              : (current / total).clamp(0.0, 1.0);
          notifyListeners();
        },
        shouldCancel: () => _isCancellingImport,
        cancellation: cancellation,
      );

      final imported = result.book;
      final shouldAutoSelectImported =
          imported != null &&
          !result.wasCancelled &&
          result.warning == null &&
          !_disposed &&
          activation == _chapterActivationId &&
          originalText == _ttsService.text &&
          !_ttsService.isPlaying &&
          _activeNovel == null &&
          originalText.trim().isEmpty;

      if (imported != null) {
        final saved = await _saveImportedBook(imported);
        if (shouldAutoSelectImported &&
            !_disposed &&
            !cancellation.isCancelled &&
            activation == _chapterActivationId &&
            !_ttsService.isPlaying) {
          await selectNovel(saved.id);
        }
      }

      if (result.wasCancelled || cancellation.isCancelled) {
        _importStatus = imported == null
            ? 'Import stopped.'
            : 'Stopped after ${imported.chapters.length} chapters. Saved to Book List.';
      } else if (result.warning != null) {
        _importStatus =
            'Saved ${imported?.chapters.length ?? 0} chapters. Import incomplete.';
        _errorMessage = result.warning;
        _pendingSharedUrl ??= url;
      } else if (imported != null) {
        _importStatus = 'Imported ${imported.chapters.length} chapters.';
        completedWithoutCancellation = true;
      }
    } catch (error) {
      _importStatus = 'Could not import that web page.';
      _errorMessage = _friendlyImportError(error);
      _pendingSharedUrl ??= url;
    } finally {
      if (completedWithoutCancellation &&
          _pendingSharedUrl?.trim() == url.trim()) {
        _pendingSharedUrl = null;
      }
      _isImporting = false;
      _cancellation = null;
      _isCancellingImport = false;
      _importProgress = null;
      notifyListeners();
    }
  }

  Future<void> cancelImport() async {
    if (!_isImporting || _isCancellingImport) {
      return;
    }

    _isCancellingImport = true;
    _cancellation?.cancel();
    _importStatus = 'Stopping import. Completed chapters will be kept.';
    notifyListeners();
  }

  String _friendlyImportError(Object error) {
    final raw = error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|FormatException): '), '')
        .trim();
    if (raw.isEmpty) {
      return 'Something went wrong while importing that web page. Please try again.';
    }

    return raw;
  }

  Future<void> selectNovel(String novelId, {int? chapterIndex}) async {
    final novelIndex = _library.indexWhere((entry) => entry.id == novelId);
    if (novelIndex < 0 || _library[novelIndex].chapters.isEmpty) {
      return;
    }

    final novel = _library[novelIndex];
    final resolvedChapterIndex = (chapterIndex ?? novel.lastReadChapterIndex)
        .clamp(0, novel.chapters.length - 1);

    await _activateChapter(
      novel: novel,
      chapterIndex: resolvedChapterIndex,
      persistLastRead: true,
    );
  }

  Future<void> selectChapter(
    int chapterIndex, {
    bool resumePlayback = false,
  }) async {
    final novel = _activeNovel;
    if (novel == null ||
        chapterIndex < 0 ||
        chapterIndex >= novel.chapters.length) {
      return;
    }

    await _activateChapter(
      novel: novel,
      chapterIndex: chapterIndex,
      persistLastRead: true,
      resumePlayback: resumePlayback,
    );
  }

  Future<void> clearActiveNovel() async {
    _chapterActivationId++;
    await _saveReadingPosition();
    _activeNovel = null;
    _activeChapterIndex = 0;
    await _storageService.saveActiveNovelId(null);
    await _storageService.saveActiveChapterIndex(0);
    notifyListeners();
  }

  Future<void> deleteNovel(String novelId) async {
    await _mutateLibrary(() async {
      final updated = _library.where((book) => book.id != novelId).toList();
      await _novelLibraryService.saveLibrary(updated);
      _library = updated;
    });

    if (_activeNovel?.id == novelId) {
      await clearActiveNovel();
    } else {
      notifyListeners();
    }
  }

  Future<void> detachIfTextChanged(String value) async {
    final chapter = activeChapter;
    if (chapter == null) {
      return;
    }
    if (value == chapter.content) {
      return;
    }
    await clearActiveNovel();
  }

  Future<void> goToNextChapter() async {
    if (_activeNovel == null) {
      return;
    }
    if (_activeChapterIndex >= _activeNovel!.chapters.length - 1) {
      return;
    }
    await selectChapter(
      _activeChapterIndex + 1,
      resumePlayback: _ttsService.isPlaying || _ttsService.isAdvancingChapter,
    );
  }

  Future<void> goToPreviousChapter() async {
    if (_activeNovel == null || _activeChapterIndex <= 0) {
      return;
    }
    await selectChapter(
      _activeChapterIndex - 1,
      resumePlayback: _ttsService.isPlaying || _ttsService.isAdvancingChapter,
    );
  }

  Future<void> _updateLastReadChapter(String novelId, int chapterIndex) async {
    _library = _library.map((book) {
      if (book.id != novelId) {
        return book;
      }
      return book.copyWith(lastReadChapterIndex: chapterIndex);
    }).toList();

    final novelIndex = _library.indexWhere((entry) => entry.id == novelId);
    if (novelIndex >= 0) {
      _activeNovel = _library[novelIndex];
    }

    await _storageService.saveNovelChapterIndex(novelId, chapterIndex);
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_disposed) return;
    final session = _ttsService.playbackSessionId;
    final novel = _activeNovel;
    if (novel == null) {
      return;
    }
    if (_activeChapterIndex >= novel.chapters.length - 1) {
      return;
    }

    final nextIndex = _activeChapterIndex + 1;
    await _activateChapter(
      novel: novel,
      chapterIndex: nextIndex,
      persistLastRead: true,
      stopPlayback: false,
      expectedPlaybackSession: session,
    );
    if (_ttsService.playbackSessionId != session ||
        _ttsService.playbackState != ReaderPlaybackState.completed ||
        _activeNovel?.id != novel.id ||
        _activeChapterIndex != nextIndex) {
      return;
    }
    await _ttsService.play();
  }

  Future<void> _activateChapter({
    required NovelBook novel,
    required int chapterIndex,
    required bool persistLastRead,
    bool stopPlayback = true,
    int? expectedPlaybackSession,
    bool resumePlayback = false,
  }) async {
    final activation = ++_chapterActivationId;
    var playbackSession =
        expectedPlaybackSession ?? _ttsService.playbackSessionId;
    bool isCurrent() => activation == _chapterActivationId && !_disposed;
    await _saveReadingPosition();
    if (!isCurrent()) return;
    if (playbackSession != _ttsService.playbackSessionId) {
      return;
    }
    if (stopPlayback) {
      final stopping = _ttsService.stop(
        preserveSleepTimer: true,
        keepAudioSession: resumePlayback || _ttsService.isPaused,
      );
      playbackSession = _ttsService.playbackSessionId;
      await stopping;
    }
    if (!isCurrent()) return;
    if (playbackSession != _ttsService.playbackSessionId) {
      return;
    }

    final textUpdate = _ttsService.updateText(
      novel.chapters[chapterIndex].content,
      resetPosition: true,
      initialPosition: stopPlayback
          ? _storageService.positionForChapter(
              novel.id,
              novel.chapters[chapterIndex].url,
            )
          : 0,
    );
    _activeNovel = novel;
    _activeChapterIndex = chapterIndex;
    notifyListeners();
    await textUpdate;
    if (!isCurrent() || playbackSession != _ttsService.playbackSessionId) {
      return;
    }

    await _storageService.saveActiveNovelId(novel.id);
    if (!isCurrent()) return;
    await _storageService.saveActiveChapterIndex(chapterIndex);
    if (!isCurrent()) return;
    if (persistLastRead) {
      await _updateLastReadChapter(novel.id, chapterIndex);
    }
    if (!isCurrent()) return;
    notifyListeners();
    if (resumePlayback && playbackSession == _ttsService.playbackSessionId) {
      await _ttsService.play();
    }
  }

  Future<void> _saveReadingPosition() async {
    final novel = _activeNovel;
    final chapter = activeChapter;
    if (novel == null ||
        chapter == null ||
        chapter.content != _ttsService.text) {
      return;
    }
    await _storageService.saveChapterPosition(
      novel.id,
      chapter.url,
      _ttsService.currentCharIndex,
    );
  }

  Future<void> _mutateLibrary(Future<void> Function() action) {
    final next = _libraryMutation.then((_) => action());
    _libraryMutation = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  String _sourceKey(String source) {
    if (!source.startsWith('http')) return source;
    try {
      return WebNovelImportService.normalizeUri(source).toString();
    } on FormatException {
      return source;
    }
  }

  Future<NovelBook> _saveImportedBook(NovelBook imported) async {
    var saved = imported;
    await _mutateLibrary(() async {
      final incomingUrls = imported.chapters
          .map((c) => _sourceKey(c.url))
          .toSet();
      final existingIndex = _library.indexWhere(
        (book) =>
            _sourceKey(book.sourceUrl) == _sourceKey(imported.sourceUrl) ||
            book.chapters.any((c) => incomingUrls.contains(_sourceKey(c.url))),
      );
      final updated = [..._library];
      if (existingIndex >= 0) {
        final existing = updated[existingIndex];
        final chapters = <String, NovelChapter>{
          for (final chapter in existing.chapters)
            _sourceKey(chapter.url): chapter,
        };
        // Keep saved content so retrying does not invalidate reading offsets.
        for (final chapter in imported.chapters) {
          chapters.putIfAbsent(_sourceKey(chapter.url), () => chapter);
        }
        final merged = chapters.values.toList();
        int? number(NovelChapter c) => int.tryParse(
          RegExp(
                r'(?:chapter|episode|part)[\s_-]*(\d+)',
                caseSensitive: false,
              ).firstMatch(c.title)?.group(1) ??
              '',
        );
        if (merged.every((c) => number(c) != null)) {
          merged.sort((a, b) => number(a)!.compareTo(number(b)!));
        }
        final lastUrl = existing.chapters.isEmpty
            ? null
            : existing
                  .chapters[existing.lastReadChapterIndex.clamp(
                    0,
                    existing.chapters.length - 1,
                  )]
                  .url;
        saved = existing.copyWith(
          importedAt: imported.importedAt,
          chapters: [
            for (var i = 0; i < merged.length; i++)
              NovelChapter(
                title: merged[i].title,
                url: merged[i].url,
                content: merged[i].content,
                order: i,
              ),
          ],
          lastReadChapterIndex: merged
              .indexWhere((c) => c.url == lastUrl)
              .clamp(0, merged.length - 1),
        );
        updated[existingIndex] = saved;
      } else {
        updated.insert(0, saved);
      }
      await _novelLibraryService.saveLibrary(updated);
      final activeUrl = activeChapter?.url;
      // Chapter selection can change while the disk write is in flight.
      _library = updated.map((book) {
        final current = _library.where((b) => b.id == book.id).firstOrNull;
        if (current == null || current.chapters.isEmpty) return book;
        final url = current
            .chapters[current.lastReadChapterIndex.clamp(
              0,
              current.chapters.length - 1,
            )]
            .url;
        final index = book.chapters.indexWhere((c) => c.url == url);
        return index < 0 ? book : book.copyWith(lastReadChapterIndex: index);
      }).toList();
      saved = _library.firstWhere((book) => book.id == saved.id);
      if (_activeNovel?.id == saved.id) {
        _activeNovel = saved;
        _activeChapterIndex = saved.chapters
            .indexWhere((c) => c.url == activeUrl)
            .clamp(0, saved.chapters.length - 1);
        await _storageService.saveActiveChapterIndex(_activeChapterIndex);
      }
      await _storageService.saveNovelChapterIndex(
        saved.id,
        saved.lastReadChapterIndex,
      );
    });
    return saved;
  }

  void clearImportMessage() {
    if (_isImporting) return;
    _importStatus = null;
    _errorMessage = null;
    notifyListeners();
  }

  NovelBook _buildSampleBook() {
    const chapters = [
      NovelChapter(
        title: 'Chapter 1 Welcome to DhebeVoice',
        url: 'sample://dhebevoice/welcome',
        order: 0,
        content:
            'Welcome to DhebeVoice. This sample book is here to help you try the app right away.\n\n'
            'Use the Play button below to hear this chapter aloud. You can also open the chapters sheet to jump between sections, or open the full reader view to focus on the current paragraph.',
      ),
      NovelChapter(
        title: 'Chapter 2 Import and Continue',
        url: 'sample://dhebevoice/import',
        order: 1,
        content:
            'DhebeVoice can read pasted text, imported files, and readable web pages.\n\n'
            'Try importing a TXT, EPUB, or PDF file, or share a web link from your browser. Imported books and pages appear in the Book List so you can return to them later.',
      ),
      NovelChapter(
        title: 'Chapter 3 Voices and Controls',
        url: 'sample://dhebevoice/voices',
        order: 2,
        content:
            'Open Settings to choose a voice, adjust speed, change pitch, or switch theme.\n\n'
            'You can pause, resume, stop, jump by chapter, or play from a selected paragraph. If you no longer want this sample book, you can delete it from the Book List at any time.',
      ),
    ];

    return NovelBook(
      id: 'sample_dhebevoice_book',
      title: 'Getting Started with DhebeVoice',
      sourceUrl: 'sample://dhebevoice/getting-started',
      importedAt: DateTime(2026, 5, 15),
      chapters: chapters,
    );
  }
}
