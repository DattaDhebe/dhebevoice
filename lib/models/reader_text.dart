import 'dart:math';

/// Paragraph and speech offsets refer to the original, unmodified editor text.
class ReaderText {
  ReaderText(this.source) {
    final ranges = <_ParagraphRange>[];
    var start = 0;
    for (final separator in RegExp(r'\r?\n\s*\r?\n').allMatches(source)) {
      _addParagraph(ranges, start, separator.start);
      start = separator.end;
    }
    _addParagraph(ranges, start, source.length);
    _ranges = List.unmodifiable(ranges);
    paragraphs = List.unmodifiable(
      ranges.map((range) => source.substring(range.start, range.end)),
    );
  }

  final String source;
  late final List<_ParagraphRange> _ranges;
  late final List<String> paragraphs;

  void _addParagraph(List<_ParagraphRange> ranges, int start, int end) {
    final raw = source.substring(start, end);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final leading = raw.length - raw.trimLeft().length;
    ranges.add(
      _ParagraphRange(start + leading, start + leading + trimmed.length),
    );
  }

  int offsetForParagraph(int index) => _ranges[index].start;

  int paragraphIndexForOffset(int offset) {
    if (_ranges.isEmpty) return 0;
    var low = 0;
    var high = _ranges.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (offset <= _ranges[middle].end) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }

  List<SpeechChunk> chunks({
    required int startOffset,
    int? endOffset,
    int maxChunkLength = 2800,
  }) {
    if (maxChunkLength < 2) throw ArgumentError.value(maxChunkLength);
    final result = <SpeechChunk>[];
    final limit = (endOffset ?? source.length).clamp(0, source.length);
    for (
      var index = paragraphIndexForOffset(startOffset);
      index < _ranges.length;
      index++
    ) {
      final range = _ranges[index];
      var start = max(range.start, startOffset);
      final end = min(range.end, limit);
      if (range.start >= limit) break;
      while (start < end) {
        var chunkEnd = min(start + maxChunkLength, end);
        if (chunkEnd < end) {
          final candidate = source.substring(start, chunkEnd);
          final sentence = candidate.lastIndexOf(RegExp(r'[.!?]\s'));
          final space = candidate.lastIndexOf(' ');
          if (sentence > 0) {
            chunkEnd = start + sentence + 1;
          } else if (space > 0) {
            chunkEnd = start + space;
          } else {
            // Do not split a UTF-16 surrogate pair between speech requests.
            final last = source.codeUnitAt(chunkEnd - 1);
            if (last >= 0xD800 && last <= 0xDBFF) chunkEnd--;
          }
        }
        final raw = source.substring(start, chunkEnd);
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) {
          final actualStart = start + raw.length - raw.trimLeft().length;
          result.add(
            SpeechChunk(
              text: trimmed,
              start: actualStart,
              end: actualStart + trimmed.length,
              paragraphIndex: index,
            ),
          );
        }
        start = chunkEnd;
      }
    }
    return result;
  }
}

class _ParagraphRange {
  const _ParagraphRange(this.start, this.end);
  final int start;
  final int end;
}

class SpeechChunk {
  const SpeechChunk({
    required this.text,
    required this.start,
    required this.end,
    required this.paragraphIndex,
  });

  final String text;
  final int start;
  final int end;
  final int paragraphIndex;
}
