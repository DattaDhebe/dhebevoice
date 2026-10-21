import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/models/reading_bookmark.dart';
import 'package:text_reader_app/services/reader_bookmark_store.dart';
import 'package:text_reader_app/services/storage_service.dart';

ReadingBookmark mark(int offset, {String note = ''}) => ReadingBookmark(
  chapterUrl: 'local-epub://abc/chapter-2',
  chapterTitle: 'Chapter II - Home',
  position: offset,
  paragraphIndex: offset ~/ 20,
  excerpt: 'A memorable passage.',
  note: note,
  createdAt: DateTime(2026, 10, 21),
);

class FailingStorage extends StorageService {
  bool fail = false;
  Completer<void>? barrier;
  @override
  Future<void> saveBookmarkData(String bookId, String? value) async {
    await barrier?.future;
    if (fail) throw StateError('Storage unavailable');
    await super.saveBookmarkData(bookId, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FailingStorage storage;
  late ReaderBookmarkStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = FailingStorage();
    await storage.initialize();
    store = ReaderBookmarkStore(storage);
  });
  test(
    'bookmarks and notes survive restart and stay scoped to the book',
    () async {
      await store.save('one', mark(20, note: 'Important'));
      await store.save('two', mark(40));
      final restarted = ReaderBookmarkStore(storage);
      expect(restarted.forBook('one').single.note, 'Important');
      expect(restarted.forBook('two').single.position, 40);
      expect(restarted.forBook('missing'), isEmpty);
      expect(() => restarted.forBook('one').clear(), throwsUnsupportedError);
    },
  );
  test(
    'saving a position again updates the note without duplicate entries',
    () async {
      await store.save('one', mark(20, note: 'First'));
      await store.save('one', mark(20, note: 'Revised'));
      expect(store.forBook('one'), hasLength(1));
      expect(store.forBook('one').single.note, 'Revised');
      await store.remove('one', mark(20).id);
      expect(ReaderBookmarkStore(storage).forBook('one'), isEmpty);
    },
  );
  test('overlapping writes are serialized and keep every bookmark', () async {
    storage.barrier = Completer<void>();
    final first = store.save('one', mark(20));
    final second = store.save('one', mark(40));
    storage.barrier!.complete();
    await Future.wait([first, second]);
    expect(store.forBook('one').map((mark) => mark.position), [40, 20]);
  });
  test(
    'failed save keeps old metadata and does not poison future writes',
    () async {
      await store.save('one', mark(20, note: 'Original'));
      storage.fail = true;
      await expectLater(
        store.save('one', mark(20, note: 'Lost')),
        throwsStateError,
      );
      expect(store.forBook('one').single.note, 'Original');
      expect(
        ReaderBookmarkStore(storage).forBook('one').single.note,
        'Original',
      );
      storage.fail = false;
      await store.save('one', mark(40));
      expect(store.forBook('one'), hasLength(2));
    },
  );
  test('corrupt metadata is reported rather than overwritten', () async {
    for (final raw in ['{bad', '{}', '[42]', '[{"position":-1}]']) {
      await storage.saveBookmarkData('bad', raw);
      final fresh = ReaderBookmarkStore(storage);
      expect(() => fresh.forBook('bad'), throwsFormatException);
      await expectLater(fresh.save('bad', mark(20)), throwsFormatException);
      expect(storage.bookmarkData('bad'), raw);
    }
  });
  test('deleting a book clears only its own bookmark metadata', () async {
    await store.save('one', mark(20));
    await store.save('two', mark(20));
    await store.removeBook('one');
    expect(storage.bookmarkData('one'), isNull);
    expect(store.forBook('one'), isEmpty);
    expect(store.forBook('two'), hasLength(1));
  });
  test(
    'bookmark limit and note length are enforced without data loss',
    () async {
      await storage.saveBookmarkData(
        'full',
        jsonEncode(List.generate(500, (i) => mark(i).toJson())),
      );
      await expectLater(store.save('full', mark(501)), throwsStateError);
      expect(store.forBook('full'), hasLength(500));
      await store.save('full', mark(0, note: 'Updated'));
      await expectLater(
        store.save('one', mark(20, note: 'x' * 1001)),
        throwsArgumentError,
      );
      expect(store.forBook('one'), isEmpty);
    },
  );
  test('library sort is validated and persisted', () async {
    expect(storage.librarySort, 'newest');
    await storage.saveLibrarySort('title');
    expect(storage.librarySort, 'title');
    await expectLater(storage.saveLibrarySort('unknown'), throwsArgumentError);
    expect(storage.librarySort, 'title');
  });
  test(
    'emoji notes count user-perceived characters consistently with the editor',
    () async {
      final note = '\u{1F3A7}' * 700;
      await store.save('emoji', mark(20, note: note));
      expect(ReaderBookmarkStore(storage).forBook('emoji').single.note, note);
    },
  );
}
