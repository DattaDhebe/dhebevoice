import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/novel_book.dart';
import 'package:text_reader_app/services/novel_library_service.dart';

NovelBook book(String id, {String content = 'Sample content.'}) => NovelBook(
  id: id,
  title: id,
  sourceUrl: 'sample://$id',
  importedAt: DateTime(2026),
  chapters: [
    NovelChapter(title: 'Chapter 1', url: '', content: content, order: 0),
  ],
);

void main() {
  late Directory directory;
  late NovelLibraryService library;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'dhebevoice-library-test-',
    );
    library = NovelLibraryService(directory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('missing library loads empty', () async {
    expect(await library.loadLibrary(), isEmpty);
  });

  test(
    'invalid JSON structure is not silently treated as an empty library',
    () async {
      final file = File('${directory.path}/novel_library.json');
      for (final content in [
        '{}',
        '[42]',
        '[{"id":"book","chapters":"broken"}]',
      ]) {
        await file.writeAsString(content);
        await expectLater(library.loadLibrary(), throwsFormatException);
        expect(await file.readAsString(), content);
      }
    },
  );

  test('overlapping saves finish in order without truncating JSON', () async {
    final first = library.saveLibrary([book('first')]);
    final last = library.saveLibrary([book('last')]);
    await Future.wait([first, last]);
    expect((await library.loadLibrary()).single.id, 'last');
    expect(
      await File('${directory.path}/novel_library.json.tmp').exists(),
      isFalse,
    );
  });

  test('large library is decoded with all content intact', () async {
    final content = 'Large paragraph.\n\n' * 12000;
    await library.saveLibrary([book('large', content: content)]);
    expect(
      (await library.loadLibrary()).single.chapters.single.content,
      content,
    );
  });

  test(
    'corrupt JSON is reported without overwriting the saved library',
    () async {
      final file = File('${directory.path}/novel_library.json');
      await file.writeAsString('{incomplete');
      await expectLater(library.loadLibrary(), throwsFormatException);
      expect(await file.readAsString(), '{incomplete');
    },
  );
}
