import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/models/import_cancellation.dart';
import 'package:text_reader_app/models/novel_book.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/novel_import_controller.dart';
import 'package:text_reader_app/services/novel_library_service.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/tts_service.dart';
import 'package:text_reader_app/services/web_novel_import_service.dart';

NovelBook book(String id, List<int> chapters) => NovelBook(
  id: id,
  title: 'Story',
  sourceUrl: 'https://books.test/story',
  importedAt: DateTime(2026),
  chapters: [
    for (final n in chapters)
      NovelChapter(
        title: 'Chapter $n - Title',
        url: 'https://books.test/story/chapter-$n',
        content: 'Paragraph one in chapter $n.\n\nParagraph two.',
        order: n - 1,
      ),
  ],
);

class MemoryLibrary extends NovelLibraryService {
  List<NovelBook> books = [];
  bool failLoad = false;
  bool failSave = false;
  int saves = 0;
  Completer<void>? barrier;
  @override
  Future<List<NovelBook>> loadLibrary() async {
    if (failLoad) throw const FormatException('corrupt');
    return [...books];
  }

  @override
  Future<void> saveLibrary(List<NovelBook> value) async {
    await barrier?.future;
    if (failSave) throw Exception('Disk full');
    saves++;
    books = [...value];
  }
}

class FakeWeb extends WebNovelImportService {
  NovelImportResult result = NovelImportResult(book: book('new', [1, 2]));
  Completer<void>? barrier;
  Completer<void>? entered;
  int calls = 0;
  @override
  Future<NovelImportResult> importNovelResultFromUrl(
    String rawUrl, {
    String accessModeId = WebNovelImportService.defaultAccessModeId,
    void Function(int, int?, String)? onProgress,
    bool Function()? shouldCancel,
    ImportCancellation? cancellation,
  }) async {
    calls++;
    onProgress?.call(0, 2, 'Downloading Chapter 1');
    entered?.complete();
    await barrier?.future;
    if (cancellation?.isCancelled ?? false) {
      return NovelImportResult(book: result.book, wasCancelled: true);
    }
    return result;
  }
}

class FakeFiles extends FileImportService {
  final pending = Completer<ImportedReaderFile?>();
  int calls = 0;
  @override
  Future<ImportedReaderFile?> importReaderFile() {
    calls++;
    return pending.future;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StorageService storage;
  late MemoryLibrary library;
  late FakeWeb web;
  late FakeFiles files;
  late TtsService tts;
  late NovelImportController importer;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({'reader_sample_book_seeded': true});
    storage = StorageService();
    await storage.initialize();
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      if (call.method == 'getVoices') {
        return [{'name': 'en-in-x-ene-local', 'locale': 'en-IN'}];
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    library = MemoryLibrary();
    web = FakeWeb();
    files = FakeFiles();
    tts = TtsService(storageService: storage, fileImportService: files);
    await tts.initialize();
    importer = NovelImportController(
      storageService: storage,
      fileImportService: files,
      novelLibraryService: library,
      webNovelImportService: web,
      ttsService: tts,
    );
  });

  tearDown(() {
    importer.dispose();
    tts.dispose();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      null,
    );
  });

  test(
    'retry merges chapters, keeps identity and does not interrupt the reader',
    () async {
      library.books = [
        book('existing', [1, 2]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing', chapterIndex: 1);
      await tts.updateText(tts.text, initialPosition: 12);
      web.result = NovelImportResult(
        book: book('replacement', [2, 3]),
        warning: 'Network failed',
      );
      await importer.importNovelFromUrl('https://books.test/story');
      expect(importer.library.single.id, 'existing');
      expect(importer.library.single.chapters, hasLength(3));
      expect(importer.activeChapterIndex, 1);
      expect(tts.currentCharIndex, 12);
      expect(importer.errorMessage, 'Network failed');
      expect(importer.hasPendingSharedUrl, isTrue);
      await importer.selectChapter(0);
      await importer.selectChapter(1);
      expect(tts.currentCharIndex, 12);
    },
  );

  test('failed save does not change the in-memory or saved library', () async {
    library.books = [
      book('existing', [1]),
    ];
    await importer.initialize();
    library.failSave = true;
    await importer.importNovelFromUrl('https://books.test/story');
    expect(importer.library.single.id, 'existing');
    expect(importer.library.single.chapters, hasLength(1));
    expect(library.books.single.chapters, hasLength(1));
    expect(importer.errorMessage, contains('Disk full'));
  });

  test(
    'chapter chosen during save remains the saved current chapter',
    () async {
      library.books = [
        book('existing', [1, 2]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing');
      web.result = NovelImportResult(book: book('new', [2, 3]));
      library.barrier = Completer<void>();
      final task = importer.importNovelFromUrl('https://books.test/story');
      await flush();
      await importer.selectChapter(1);
      library.barrier!.complete();
      await task;
      expect(importer.activeChapterIndex, 1);
      expect(importer.library.single.lastReadChapterIndex, 1);
      expect(storage.chapterIndexForNovel('existing'), 1);
    },
  );

  test(
    'unreadable library blocks imports instead of overwriting saved data',
    () async {
      library.failLoad = true;
      await importer.importNovelFromUrl('https://books.test/story');
      await importer.importLocalFile();
      expect(web.calls, 0);
      expect(files.calls, 0);
      expect(library.saves, 0);
      expect(
        importer.errorMessage,
        contains('saved file has not been changed'),
      );
    },
  );

  test('local picker is busy and Stop discards its eventual result', () async {
    final first = importer.importLocalFile();
    await flush();
    expect(importer.isImporting, isTrue);
    await importer.importLocalFile();
    await importer.importNovelFromUrl('https://books.test/story');
    expect(files.calls, 1);
    expect(web.calls, 0);
    await importer.cancelImport();
    files.pending.complete(
      ImportedReaderFile.epub(name: 'story.epub', book: book('file', [1])),
    );
    await first;
    expect(importer.library, isEmpty);
    expect(importer.isImporting, isFalse);
    expect(importer.importStatus, 'Import stopped.');
  });

  test(
    'browser title and link are queued without automatic download',
    () async {
      await importer.handleSharedPayload(
        'A book title\nhttps://books.test/story?utm_source=share',
      );
      expect(importer.pendingSharedUrl, 'https://books.test/story');
      expect(web.calls, 0);
    },
  );

  test(
    'new shared link during import does not erase progress or get cleared',
    () async {
      web.barrier = Completer<void>();
      web.entered = Completer<void>();
      await importer.queueSharedUrl('https://books.test/story');
      final task = importer.importPendingSharedUrl();
      await web.entered!.future;
      await importer.queueSharedUrl('https://books.test/another');
      expect(importer.importStatus, 'Downloading Chapter 1');
      expect(importer.importProgress, 0);
      web.barrier!.complete();
      await task;
      expect(importer.pendingSharedUrl, 'https://books.test/another');
    },
  );

  test('delete during save is serialized and not lost', () async {
    library.books = [
      book('existing', [1]),
    ];
    await importer.initialize();
    library.barrier = Completer<void>();
    final task = importer.importNovelFromUrl('https://books.test/story');
    await flush();
    final deletion = importer.deleteNovel('existing');
    library.barrier!.complete();
    await Future.wait([task, deletion]);
    expect(importer.library, isEmpty);
    expect(library.books, isEmpty);
  });

  test('Stop during saving prevents auto-opening the imported book', () async {
    library.barrier = Completer<void>();
    final task = importer.importNovelFromUrl('https://books.test/story');
    await flush();
    await importer.cancelImport();
    library.barrier!.complete();
    await task;
    expect(importer.activeNovel, isNull);
    expect(importer.library, hasLength(1));
    expect(importer.importStatus, contains('Stopped'));
  });

  test(
    'bookmark saves paragraph start without stopping playback or rewriting books',
    () async {
      library.books = [
        book('existing', [1, 2]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing');
      await tts.playFromParagraph(1);
      final session = tts.playbackSessionId;
      final saves = library.saves;
      await importer.saveCurrentBookmark(note: 'Return here');
      final saved = importer.bookmarksForBook('existing').single;
      expect(saved.paragraphIndex, 1);
      expect(saved.position, tts.text.indexOf('Paragraph two.'));
      expect(saved.note, 'Return here');
      expect(tts.isPlaying, isTrue);
      expect(tts.playbackSessionId, session);
      expect(library.saves, saves);
      await importer.saveCurrentBookmark();
      expect(importer.bookmarksForBook('existing'), hasLength(1));
      expect(importer.bookmarksForBook('existing').single.note, 'Return here');
      await importer.updateBookmark('existing', saved, '');
      expect(importer.bookmarksForBook('existing').single.note, isEmpty);
    },
  );

  test(
    'bookmark navigates by stable chapter URL after earlier chapters are merged',
    () async {
      library.books = [
        book('existing', [2, 3]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing', chapterIndex: 1);
      await tts.playFromParagraph(1);
      await tts.pause();
      await importer.saveCurrentBookmark();
      final saved = importer.bookmarksForBook('existing').single;
      web.result = NovelImportResult(book: book('incoming', [1, 2]));
      await importer.importNovelFromUrl('https://books.test/story');
      await importer.selectChapter(0);
      await importer.openBookmark('existing', saved);
      expect(importer.activeChapter!.title, 'Chapter 3 - Title');
      expect(importer.activeChapterIndex, 2);
      expect(tts.currentParagraphIndex, 1);
      expect(tts.currentCharIndex, saved.position);
      expect(tts.isPlaying, isFalse);
      await importer.openBookmark('existing', saved, play: true);
      expect(tts.isPlaying, isTrue);
      expect(tts.currentParagraphIndex, 1);
    },
  );

  test(
    'manual or edited text cannot attach a bookmark to an unrelated book',
    () async {
      await expectLater(importer.saveCurrentBookmark(), throwsStateError);
      library.books = [
        book('existing', [1]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing');
      await tts.updateText('Different text.');
      await expectLater(importer.saveCurrentBookmark(), throwsStateError);
      expect(importer.bookmarksForBook('existing'), isEmpty);
    },
  );

  test(
    'book deletion removes bookmarks and stale navigation is rejected',
    () async {
      library.books = [
        book('existing', [1]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing');
      await importer.saveCurrentBookmark();
      final saved = importer.bookmarksForBook('existing').single;
      await importer.deleteNovel('existing');
      expect(importer.bookmarksForBook('existing'), isEmpty);
      await expectLater(
        importer.openBookmark('existing', saved),
        throwsStateError,
      );
    },
  );

  test(
    'roman-numbered chapter imports sort once and preserve the active chapter',
    () async {
      NovelBook roman(List<int> indices) => book('existing', indices).copyWith(
        chapters: [
          for (final i in indices)
            NovelChapter(
              title: 'Chapter ${['I', 'II', 'III'][i - 1]} - Heading',
              url: 'https://books.test/story/chapter-$i',
              content: 'Story $i.',
              order: i - 1,
            ),
        ],
      );
      library.books = [
        roman([2, 3]),
      ];
      await importer.initialize();
      await importer.selectNovel('existing');
      web.result = NovelImportResult(book: roman([1, 2]));
      await importer.importNovelFromUrl('https://books.test/story');
      expect(importer.library.single.chapters.map((c) => c.title), [
        'Chapter I - Heading',
        'Chapter II - Heading',
        'Chapter III - Heading',
      ]);
      expect(importer.activeChapterIndex, 1);
    },
  );
}
