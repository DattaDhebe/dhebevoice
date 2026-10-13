import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:text_reader_app/models/import_cancellation.dart';
import 'package:text_reader_app/services/web_novel_import_service.dart';

String chapter(int number, {String next = '', String extra = ''}) =>
    '<h1>Chapter $number - A real title</h1><article>'
    '<p>Yes.</p><p>No!</p><p>A <b>bold</b> word.<br>Another line.</p>'
    '$extra<nav>$next</nav></article>';

WebNovelImportService service(
  FutureOr<http.Response> Function(http.Request) handler, {
  int maxPageBytes = 2 * 1024 * 1024,
  int maxChapters = 200,
  int maxBookCharacters = 12 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 2),
}) => WebNovelImportService(
  clientFactory: () => MockClient((r) async => handler(r)),
  requestInterval: Duration.zero,
  requestTimeout: timeout,
  maxPageBytes: maxPageBytes,
  maxChapters: maxChapters,
  maxBookCharacters: maxBookCharacters,
);

http.Response html(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

void main() {
  test('an index containing only one chapter imports that chapter', () async {
    final result = await service(
      (r) => r.url.path == '/story'
          ? html('<h1>Story</h1><a href="/story/chapter-1">Chapter 1</a>')
          : html(chapter(1)),
    ).importNovelResultFromUrl('https://books.test/story');
    expect(
      result.book!.chapters.single.url,
      'https://books.test/story/chapter-1',
    );
    expect(result.book!.chapters.single.content, contains('Yes.'));
  });

  test('book text limit preserves earlier chapters', () async {
    final result = await service(
      (r) => r.url.path.endsWith('chapter-1')
          ? html(chapter(1, next: '<a rel="next" href="chapter-2">Next</a>'))
          : html(chapter(2, extra: '<p>${"x" * 200}</p>')),
      maxBookCharacters: 100,
    ).importNovelResultFromUrl('https://books.test/story/chapter-1');
    expect(result.book!.chapters, hasLength(1));
    expect(result.warning, contains('text size limit'));
  });

  test(
    'keeps short dialogue, line breaks, titles and navigation links',
    () async {
      final requests = <String>[];
      final result = await service((r) {
        requests.add(r.url.path);
        return html(
          chapter(
            requests.length,
            next: requests.length == 1
                ? '<a rel="next" href="chapter-2">Next chapter</a>'
                : '',
          ),
        );
      }).importNovelResultFromUrl('https://books.test/story/chapter-1');
      expect(requests, ['/story/chapter-1', '/story/chapter-2']);
      expect(result.book!.chapters, hasLength(2));
      expect(result.book!.chapters.first.title, 'Chapter 1 - A real title');
      expect(
        result.book!.chapters.first.content,
        'Yes.\n\nNo!\n\nA bold word.\nAnother line.',
      );
    },
  );

  test('does not follow previous or recommended books', () async {
    var count = 0;
    final result = await service((r) {
      count++;
      return html(
        chapter(
          5,
          next:
              '<a href="chapter-4">Previous chapter</a>'
              '<a href="/another-story/chapter-6">Next chapter</a>'
              '<a href="chapter-20">Recommended chapter 20</a>',
        ),
      );
    }).importNovelResultFromUrl('https://books.test/story/chapter-5');
    expect(count, 1);
    expect(result.book!.chapters, hasLength(1));
  });

  test(
    'later HTTP failure keeps completed chapters and reports incomplete',
    () async {
      final result = await service(
        (r) => r.url.path.endsWith('chapter-1')
            ? html(chapter(1, next: '<a rel="next" href="chapter-2">Next</a>'))
            : http.Response('', 503),
      ).importNovelResultFromUrl('https://books.test/story/chapter-1');
      expect(result.book!.chapters, hasLength(1));
      expect(result.warning, contains('503'));
      expect(result.wasCancelled, isFalse);
    },
  );

  test(
    'Stop interrupts an in-flight request and retains downloaded chapters',
    () async {
      final pending = Completer<http.Response>();
      final entered = Completer<void>();
      final cancellation = ImportCancellation();
      final task =
          service((r) {
            if (r.url.path.endsWith('chapter-1')) {
              return html(
                chapter(1, next: '<a rel="next" href="chapter-2">Next</a>'),
              );
            }
            entered.complete();
            return pending.future;
          }).importNovelResultFromUrl(
            'https://books.test/story/chapter-1',
            cancellation: cancellation,
          );
      await entered.future;
      cancellation.cancel();
      final result = await task.timeout(const Duration(milliseconds: 300));
      expect(result.wasCancelled, isTrue);
      expect(result.book!.chapters, hasLength(1));
      pending.complete(html(chapter(2)));
    },
  );

  test('already cancelled import never opens a request', () async {
    final cancellation = ImportCancellation()..cancel();
    var requests = 0;
    final result =
        await service((r) {
          requests++;
          return html(chapter(1));
        }).importNovelResultFromUrl(
          'https://books.test/story/chapter-1',
          cancellation: cancellation,
        );
    expect(requests, 0);
    expect(result.book, isNull);
    expect(result.wasCancelled, isTrue);
  });

  test(
    'large index is not mistaken for content and sorts actual chapter numbers',
    () async {
      final paths = <String>[];
      final result = await service((r) {
        paths.add(r.url.path);
        if (r.url.path == '/story-2026') {
          return html(
            '<h1>A story</h1><div>'
            '<a href="/story-2026/chapter-102">Chapter 102</a>'
            '<a href="/story-2026/chapter-101">Chapter 101</a>'
            '<a href="/story-2026/chapter-101#read">Chapter 101</a>'
            '<a href="/story-2026/chapter-101?utm_source=share">Chapter 101</a>'
            '<a href="/other/chapter-1">Chapter 1</a>'
            '${List.filled(140, "index").join(" ")}</div>',
          );
        }
        return html(chapter(int.parse(r.url.path.split('-').last)));
      }).importNovelResultFromUrl('https://books.test/story-2026');
      expect(paths, [
        '/story-2026',
        '/story-2026/chapter-101',
        '/story-2026/chapter-102',
      ]);
      expect(result.book!.chapters.map((c) => c.title), [
        'Chapter 101 - A real title',
        'Chapter 102 - A real title',
      ]);
    },
  );

  test('chapter limit and progress total agree', () async {
    final totals = <int?>[];
    final result =
        await service(
          (r) => r.url.path == '/story'
              ? html(
                  '<a href="/story/chapter-1">Chapter 1</a>'
                  '<a href="/story/chapter-2">Chapter 2</a>'
                  '<a href="/story/chapter-3">Chapter 3</a>',
                )
              : html(chapter(1)),
          maxChapters: 2,
        ).importNovelResultFromUrl(
          'https://books.test/story',
          onProgress: (current, total, _) {
            totals.add(total);
            if (total != null) expect(current, lessThanOrEqualTo(total));
          },
        );
    expect(result.book!.chapters, hasLength(2));
    expect(result.warning, contains('first 2 chapters'));
    expect(totals, everyElement(2));
  });

  test(
    'follows a normal redirect using the final URL for relative links',
    () async {
      final paths = <String>[];
      final result = await service((r) {
        paths.add(r.url.path);
        if (r.url.path == '/start') {
          return http.Response(
            '',
            302,
            headers: {'location': '/story/chapter-1'},
          );
        }
        return html(
          chapter(
            paths.length - 1,
            next: paths.length == 2
                ? '<a href="chapter-2" rel="next">Next</a>'
                : '',
          ),
        );
      }).importNovelResultFromUrl('https://books.test/start');
      expect(paths, ['/start', '/story/chapter-1', '/story/chapter-2']);
      expect(result.book!.sourceUrl, 'https://books.test/story/chapter-1');
    },
  );

  test('rejects redirect loops', () async {
    await expectLater(
      service(
        (r) => http.Response('', 302, headers: {'location': '/again'}),
      ).importNovelResultFromUrl('https://books.test/start'),
      throwsA(predicate((e) => e.toString().contains('redirect'))),
    );
  });

  test('rejects unsupported URLs before network access', () async {
    for (final url in [
      'file:///tmp/book',
      'ftp://books.test/a',
      'https://user:password@books.test',
      'not a url',
    ]) {
      await expectLater(
        service(
          (r) => throw StateError('must not request'),
        ).importNovelResultFromUrl(url),
        throwsFormatException,
      );
    }
  });

  test(
    '403 and rate limits are surfaced without alternate access attempts',
    () async {
      for (final code in [403, 429]) {
        var requests = 0;
        await expectLater(
          service((r) {
            requests++;
            return http.Response('', code);
          }).importNovelResultFromUrl('https://books.test/story'),
          throwsA(isA<Exception>()),
        );
        expect(requests, 1);
      }
    },
  );

  test('rejects oversized responses and binary documents', () async {
    await expectLater(
      service(
        (r) => html('too large'),
        maxPageBytes: 3,
      ).importNovelResultFromUrl('https://books.test/story'),
      throwsA(predicate((e) => e.toString().contains('too large'))),
    );
    await expectLater(
      service(
        (r) => http.Response(
          'pdf',
          200,
          headers: {'content-type': 'application/pdf'},
        ),
      ).importNovelResultFromUrl('https://books.test/story'),
      throwsA(predicate((e) => e.toString().contains('file import'))),
    );
  });

  test('timeout is actionable', () async {
    final pending = Completer<http.Response>();
    await expectLater(
      service(
        (r) => pending.future,
        timeout: const Duration(milliseconds: 20),
      ).importNovelResultFromUrl('https://books.test/story'),
      throwsA(predicate((e) => e.toString().contains('too long'))),
    );
    pending.complete(html(chapter(1)));
  });

  test('200 browser challenge is not saved as a book', () async {
    await expectLater(
      service(
        (r) => html(
          '<title>Just a moment...</title>'
          '<main>Checking your browser. Please wait.</main>',
        ),
      ).importNovelResultFromUrl('https://books.test/story'),
      throwsA(predicate((e) => e.toString().contains('browser verification'))),
    );
  });

  test(
    'large HTML parsing runs on a worker and plain text keeps paragraphs',
    () async {
      final result = await service(
        (r) => html(
          chapter(1, extra: '<!--${List.filled(140000, "x").join()}-->'),
        ),
      ).importNovelResultFromUrl('https://books.test/story/chapter-1');
      expect(result.book!.chapters.single.content, contains('Yes.\n\nNo!'));
      final plain = await service(
        (r) => http.Response(
          'First\n\nSecond',
          200,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        ),
      ).importNovelResultFromUrl('https://books.test/story');
      expect(plain.book!.chapters.single.content, 'First\n\nSecond');
    },
  );
}
