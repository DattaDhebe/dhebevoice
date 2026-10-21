/// Reads chapter headings without interpreting digits in book IDs or hosts.
abstract final class ChapterNumber {
  static final _heading = RegExp(
    r'\b(?:chapter|chap|ch|episode|ep|part)[\s._:#\-\u2010-\u2015]*(\d+|[ivxlcdm]+)(?=$|[\s.,:;_!?\-\u2010-\u2015])',
    caseSensitive: false,
  );
  static final _leadingNumber = RegExp(r'^\s*#?\s*(\d+)\b');
  static final _roman = RegExp(
    r'^(?=.)M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$',
  );

  static int? parse(String title, {String? url}) {
    final heading = _heading.firstMatch(title)?.group(1);
    if (heading != null) {
      final number = _number(heading);
      if (number != null) return number;
    }
    final leading = _leadingNumber.firstMatch(title)?.group(1);
    if (leading != null) return int.tryParse(leading);
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
      return null;
    }
    // Restrict URL fallback to an explicit heading in the final path segment.
    // Local EPUB identifiers, hosts, query values, and fragments are not numbers.
    try {
      final last = uri.pathSegments.where((part) => part.isNotEmpty).lastOrNull;
      final segment = last == null ? null : _heading.firstMatch(last)?.group(1);
      return segment == null ? null : _number(segment);
    } on FormatException {
      return null;
    }
  }

  static int? _number(String token) {
    final arabic = int.tryParse(token);
    if (arabic != null) return arabic;
    final roman = token.toUpperCase();
    if (!_roman.hasMatch(roman)) return null;
    const values = {
      'I': 1,
      'V': 5,
      'X': 10,
      'L': 50,
      'C': 100,
      'D': 500,
      'M': 1000,
    };
    var result = 0;
    var previous = 0;
    for (var i = roman.length - 1; i >= 0; i--) {
      final value = values[roman[i]]!;
      result += value < previous ? -value : value;
      previous = value;
    }
    return result;
  }
}
