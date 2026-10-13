import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/reader_text.dart';

void main() {
  test('neural-sized chunks preserve text offsets and surrogate pairs', () {
    final source = '${'Story sentence. ' * 100}\n\n${'x' * 239}\u{1F600}end';
    final chunks = ReaderText(
      source,
    ).chunks(startOffset: 0, maxChunkLength: 240);
    for (final chunk in chunks) {
      expect(chunk.text.length, lessThanOrEqualTo(240));
      expect(source.substring(chunk.start, chunk.end), chunk.text);
      expect(chunk.text.runes, isNot(contains(0xFFFD)));
    }
    expect(chunks.last.text, '\u{1F600}end');
  });

  test('paragraph offsets preserve spaces, CRLF and variable separators', () {
    const source = '  First paragraph.  \r\n\r\n\r\n  Second.\n \n\tThird. ';
    final reader = ReaderText(source);
    expect(reader.paragraphs, ['First paragraph.', 'Second.', 'Third.']);
    for (var i = 0; i < reader.paragraphs.length; i++) {
      final offset = reader.offsetForParagraph(i);
      expect(source.substring(offset).startsWith(reader.paragraphs[i]), isTrue);
      expect(reader.paragraphIndexForOffset(offset), i);
    }
  });

  test('selection speaks only the exact selected source range', () {
    const source = '  First.\n\n\n   Second paragraph.\n\nThird.';
    final start = source.indexOf('paragraph');
    final chunks = ReaderText(
      source,
    ).chunks(startOffset: start, endOffset: start + 9);
    expect(chunks.single.text, 'paragraph');
    expect(chunks.single.start, start);
    expect(chunks.single.paragraphIndex, 1);
  });

  test('long chunks preserve offsets after trimming at split boundaries', () {
    final source = '  ${'A sentence.   ' * 800}\n\nLast paragraph.';
    final chunks = ReaderText(source).chunks(startOffset: 0);
    expect(chunks.length, greaterThan(3));
    for (final chunk in chunks) {
      expect(chunk.text.length, lessThanOrEqualTo(2800));
      expect(source.substring(chunk.start, chunk.end), chunk.text);
    }
    expect(chunks.last.text, 'Last paragraph.');
    expect(chunks.last.paragraphIndex, 1);
  });

  test('hard split does not separate a surrogate pair', () {
    final source = '${'x' * 2799}\u{1F600}${'y' * 10}';
    final chunks = ReaderText(source).chunks(startOffset: 0);
    expect(chunks.first.text.length, 2799);
    expect(chunks.map((chunk) => chunk.text).join(), source);
  });

  test('empty text and selections in whitespace produce no speech', () {
    expect(ReaderText(' \n\n ').paragraphs, isEmpty);
    expect(ReaderText('').chunks(startOffset: 0), isEmpty);
    expect(
      ReaderText('One.\n\nTwo.').chunks(startOffset: 4, endOffset: 6),
      isEmpty,
    );
  });

  test('resume at end does not replay the last paragraph', () {
    const source = 'First.\n\nLast.';
    expect(ReaderText(source).chunks(startOffset: source.length), isEmpty);
  });

  test('paragraph lookups reuse the same immutable cache', () {
    final reader = ReaderText('paragraph\n\n' * 10000);
    expect(identical(reader.paragraphs, reader.paragraphs), isTrue);
    expect(() => reader.paragraphs.add('changed'), throwsUnsupportedError);
    expect(
      reader.paragraphIndexForOffset(reader.offsetForParagraph(9999)),
      9999,
    );
  });
}
