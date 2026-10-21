import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/chapter_number.dart';

void main() {
  for (final entry in <String, int>{
    '# chapter 102 - A new start': 102,
    '#chapter 103: The city': 103,
    'CHAPTER I. Down the Rabbit-Hole': 1,
    'Chapter IV - Return': 4,
    'Chapter XXXIX: Home': 39,
    'Part XCIX': 99,
    'Chapter MCMXCIV': 1994,
    'Episode 204': 204,
    '102 - A new start': 102,
    'Ch. 12: Arrival': 12,
  }.entries) {
    test('chapter number: ${entry.key}', () {
      expect(ChapterNumber.parse(entry.key), entry.value);
    });
  }
  test(
    'local hashes, hosts, query parameters and title years are not chapter numbers',
    () {
      for (final url in [
        'local-epub://8a123def/chapter',
        'local-pdf://f123/page-4',
        'https://chapter-999.test/books/a?chapter-77#chapter-88',
        'https://books.test/a/b123',
      ]) {
        expect(ChapterNumber.parse('A journey through 2026', url: url), isNull);
      }
    },
  );
  test(
    'only explicit chapter headings in the final web path segment are used',
    () {
      expect(
        ChapterNumber.parse(
          'A new start',
          url: 'https://novelbin.com/b/story/chapter-102-arrival',
        ),
        102,
      );
      expect(
        ChapterNumber.parse('Chapter 7', url: 'https://books.test/chapter-102'),
        7,
      );
      expect(ChapterNumber.parse('Chapter IIII - Wrong'), isNull);
      expect(ChapterNumber.parse('Chapter IC - Wrong'), isNull);
      expect(ChapterNumber.parse('Important changes'), isNull);
    },
  );
  test('Unicode heading separators and trailing slashes work safely', () {
    expect(ChapterNumber.parse('Chapter\u2013102\u2013Arrival'), 102);
    expect(
      ChapterNumber.parse('Arrival', url: 'https://books.test/chapter-102/'),
      102,
    );
    expect(
      ChapterNumber.parse('Arrival', url: 'https://books.test/%FF'),
      isNull,
    );
  });
}
