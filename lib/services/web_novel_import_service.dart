import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/import_cancellation.dart';
import '../models/novel_book.dart';
import '../models/readable_html.dart';

class WebNovelImportService {
  WebNovelImportService({
    http.Client Function()? clientFactory,
    this.maxChapters = 200,
    this.maxPageBytes = 2 * 1024 * 1024,
    this.maxBookCharacters = 12 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 25),
    this.requestInterval = const Duration(milliseconds: 350),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  static const defaultAccessModeId = 'mobile_browser';
  static const accessModes = [
    WebAccessMode(
      id: defaultAccessModeId,
      label: 'Standard browser',
      description: 'Uses normal web requests to import accessible text.',
    ),
  ];
  final http.Client Function() _clientFactory;
  final int maxChapters;
  final int maxPageBytes;
  final int maxBookCharacters;
  final Duration requestTimeout;
  final Duration requestInterval;

  Future<NovelBook> importNovelFromUrl(
    String rawUrl, {
    String accessModeId = defaultAccessModeId,
    void Function(int current, int? total, String status)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final result = await importNovelResultFromUrl(
      rawUrl,
      accessModeId: accessModeId,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
    if (result.book != null) return result.book!;
    throw Exception('Import stopped before any chapters were imported.');
  }

  Future<NovelImportResult> importNovelResultFromUrl(
    String rawUrl, {
    String accessModeId = defaultAccessModeId,
    void Function(int current, int? total, String status)? onProgress,
    bool Function()? shouldCancel,
    ImportCancellation? cancellation,
  }) async {
    final startingUri = normalizeUri(rawUrl);
    final client = _clientFactory();
    final chapters = <NovelChapter>[];
    _FetchedPage? firstPage;
    String? warning;
    var cancelled = false;
    var characterCount = 0;
    bool isCancelled() =>
        (cancellation?.isCancelled ?? false) || (shouldCancel?.call() ?? false);
    void checkCancelled() {
      if (isCancelled()) throw const ImportCancelled();
    }

    Future<T> interruptible<T>(Future<T> operation) async {
      checkCancelled();
      if (cancellation == null) return operation;
      return Future.any([
        operation,
        cancellation.whenCancelled.then<T>(
          (_) => throw const ImportCancelled(),
        ),
      ]);
    }

    Future<_FetchedPage> fetch(Uri uri, {bool first = false}) async {
      checkCancelled();
      if (!first) await interruptible(Future<void>.delayed(requestInterval));
      final page = await interruptible(
        _fetchPage(client, uri).timeout(requestTimeout),
      );
      checkCancelled();
      if (!first && page.uri.host != firstPage!.uri.host) {
        throw Exception(
          'The chapter redirected to a different website. Import stopped.',
        );
      }
      return page;
    }

    void addPage(_FetchedPage page, {String? linkTitle}) {
      final content = _extractReadableText(page.document);
      if (content.isEmpty) {
        throw Exception('No readable text was found on this page.');
      }
      if (characterCount + content.length > maxBookCharacters) {
        throw Exception(
          'This import reached the text size limit. Import the remaining chapters separately.',
        );
      }
      final title = _chapterTitle(page, linkTitle);
      chapters.add(
        NovelChapter(
          title: title,
          url: page.uri.toString(),
          content: content,
          order: chapters.length,
        ),
      );
      characterCount += content.length;
    }

    try {
      firstPage = await fetch(startingUri, first: true);
      final links = _chapterLinks(firstPage.document, firstPage.uri);
      final isIndex = links.isNotEmpty && !_isChapterPage(firstPage);
      final visited = <String>{};
      if (isIndex) {
        final total = links.length.clamp(0, maxChapters);
        for (final entry in links.take(maxChapters)) {
          checkCancelled();
          onProgress?.call(chapters.length, total, 'Downloading ${entry.text}');
          final page = await fetch(entry.uri);
          if (!visited.add(page.uri.toString())) continue;
          addPage(page, linkTitle: entry.text);
          onProgress?.call(
            chapters.length,
            total,
            'Saved ${chapters.last.title}',
          );
        }
        if (links.length > maxChapters) {
          warning =
              'Saved the first $maxChapters chapters. Import the remaining chapters separately.';
        }
      } else {
        var page = firstPage;
        while (chapters.length < maxChapters) {
          checkCancelled();
          if (!visited.add(page.uri.toString())) break;
          onProgress?.call(
            chapters.length,
            null,
            'Importing ${_chapterTitle(page)}',
          );
          addPage(page);
          final next = _nextChapter(page.document, page.uri, visited);
          if (next == null) break;
          if (chapters.length == maxChapters) {
            warning =
                'Saved the first $maxChapters chapters. Import the remaining chapters separately.';
            break;
          }
          onProgress?.call(
            chapters.length,
            null,
            'Downloading ${_pathTitle(next)}',
          );
          page = await fetch(next);
        }
      }
    } on ImportCancelled {
      cancelled = true;
    } catch (error) {
      if (isCancelled()) {
        cancelled = true;
      } else {
        final message = _friendlyError(error, startingUri.host);
        if (chapters.isEmpty) throw Exception(message);
        warning = message;
      }
    } finally {
      // Closing also aborts a pending network request when Stop wins the race.
      client.close();
    }

    cancelled = cancelled || isCancelled();
    if (chapters.isEmpty) {
      if (cancelled) return const NovelImportResult(wasCancelled: true);
      throw Exception(
        'DhebeVoice could not detect readable content on this page.',
      );
    }
    final source = firstPage!.uri.toString();
    final document = firstPage.document;
    final title = _cleanTitle(
      document
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'] ??
          document.querySelector('h1')?.text ??
          document.querySelector('title')?.text ??
          chapters.first.title,
    );
    return NovelImportResult(
      book: NovelBook(
        id: 'web_${sha256.convert(utf8.encode(source)).toString().substring(0, 24)}',
        title: title.isEmpty ? chapters.first.title : title,
        sourceUrl: source,
        importedAt: DateTime.now(),
        chapters: chapters,
      ),
      wasCancelled: cancelled,
      warning: warning,
    );
  }

  static String normalizeAccessModeId(String? value) => defaultAccessModeId;

  static Uri normalizeUri(String value) {
    final input = value.trim();
    final candidate = input.contains('://') ? input : 'https://$input';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'\s').hasMatch(input)) {
      throw const FormatException('Enter a valid http or https web link.');
    }
    final query = Map<String, dynamic>.from(uri.queryParametersAll)
      ..removeWhere(
        (key, _) =>
            key.toLowerCase().startsWith('utm_') ||
            {'fbclid', 'gclid'}.contains(key.toLowerCase()),
      );
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Future<_FetchedPage> _fetchPage(http.Client client, Uri start) async {
    var uri = start;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(const {
          'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9',
          'Accept-Language': 'en-US,en;q=0.9',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/136.0 Mobile Safari/537.36',
        });
      final response = await client.send(request);
      final status = response.statusCode;
      if ({301, 302, 303, 307, 308}.contains(status)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null || redirects == 5) {
          throw Exception(
            'The website returned an invalid or repeated redirect.',
          );
        }
        uri = normalizeUri(uri.resolve(location).toString());
        continue;
      }
      if (status < 200 || status >= 300) {
        await response.stream.listen((_) {}).cancel();
        if (status == 401 || status == 403) {
          throw Exception(
            '${uri.host} does not allow this import (HTTP $status). '
            'Only import content you are authorized to access.',
          );
        }
        if (status == 429) {
          throw Exception(
            '${uri.host} is limiting requests. Wait before trying again.',
          );
        }
        throw Exception('Could not open ${uri.host} (HTTP $status).');
      }
      final type = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (type != null &&
          !{
            'text/html',
            'application/xhtml+xml',
            'text/plain',
          }.contains(type)) {
        await response.stream.listen((_) {}).cancel();
        throw Exception(
          'This link is not a readable web page. Use file import for PDF, EPUB or TXT files.',
        );
      }
      if ((response.contentLength ?? 0) > maxPageBytes) {
        await response.stream.listen((_) {}).cancel();
        throw Exception('This web page is too large to import safely.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxPageBytes) {
          throw Exception('This web page is too large to import safely.');
        }
        bytes.add(chunk);
      }
      final charset = RegExp(
        r'charset\s*=\s*"?([^;"\s]+)',
        caseSensitive: false,
      ).firstMatch(response.headers['content-type'] ?? '')?.group(1);
      final encoding = Encoding.getByName(charset) ?? utf8;
      final data = bytes.takeBytes();
      final decoded = encoding == utf8
          ? utf8.decode(data, allowMalformed: true)
          : encoding.decode(data);
      final document = type == 'text/plain'
          ? html_parser.parse('<article></article>')
          : decoded.length > 128 * 1024
          ? await compute(_parseHtml, decoded)
          : _parseHtml(decoded);
      if (type == 'text/plain') {
        for (final paragraph in decoded.split(RegExp(r'\r?\n'))) {
          document
              .querySelector('article')!
              .append(dom.Element.tag('p')..text = paragraph);
        }
      }
      return _FetchedPage(uri: uri, document: document);
    }
    throw Exception('Too many redirects.');
  }

  static dom.Document _parseHtml(String value) => html_parser.parse(value);

  String _friendlyError(Object error, String host) {
    if (error is TimeoutException) {
      return '$host took too long to respond. Try again.';
    }
    if (error is SocketException || error is http.ClientException) {
      return 'Could not reach $host. Check your internet connection and try again.';
    }
    return error.toString().replaceFirst(
      RegExp(r'^(Exception|FormatException): '),
      '',
    );
  }

  bool _isChapterPage(_FetchedPage page) {
    if (_chapterNumber(page.uri.pathSegments.lastOrNull ?? '') != null) {
      return true;
    }
    if (page.document.querySelector(
          '#chr-content, #chapter-content, .reading-content',
        ) !=
        null) {
      return true;
    }
    final paragraphs = page.document.querySelectorAll(
      'article p, main p, .entry-content p, .post-content p',
    );
    return paragraphs.where((p) => p.text.trim().length > 80).length >= 3;
  }

  String _extractReadableText(dom.Document document) {
    final pageTitle =
        document.querySelector('title')?.text.trim().toLowerCase() ?? '';
    if (RegExp(
          r'^(just a moment|access denied|attention required|checking your browser)',
        ).hasMatch(pageTitle) &&
        document.querySelector(
              '#chr-content, #chapter-content, .reading-content',
            ) ==
            null) {
      throw Exception(
        'This website requires browser verification or does not allow web import.',
      );
    }
    for (final selector in const [
      '#chr-content',
      '#chapter-content',
      '.reading-content',
      '.chapter-content',
      '.entry-content',
      '.post-content',
      'article',
      'main',
      '#content',
      '.content',
    ]) {
      for (final element in document.querySelectorAll(selector)) {
        final text = readableHtml(element);
        if (text.isNotEmpty) return text;
      }
    }
    return readableHtml(document.body);
  }

  String _chapterTitle(_FetchedPage page, [String? linkTitle]) {
    final heading =
        page.document.querySelector('.chr-title, .chapter-title')?.text ??
        page.document.querySelector('h1')?.text;
    final title = _cleanTitle(
      heading ?? linkTitle ?? page.document.querySelector('title')?.text ?? '',
    );
    return title.isEmpty ? _pathTitle(page.uri) : title;
  }

  String _cleanTitle(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').split('|').first.trim();

  String _pathTitle(Uri uri) {
    final slug = uri.pathSegments.lastOrNull ?? 'Chapter';
    return slug
        .replaceAll(RegExp(r'\.(html?|xhtml)$'), '')
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();
  }

  int? _chapterNumber(String text) {
    final match = RegExp(
      r'(?:chapter|episode|part)[\s_-]*(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  bool _sameBook(Uri base, Uri candidate) {
    if (base.host != candidate.host || base.port != candidate.port) {
      return false;
    }
    final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return true;
    if (_chapterNumber(segments.last) != null ||
        RegExp(r'\.(html?|xhtml)$').hasMatch(segments.last)) {
      segments.removeLast();
    }
    // Use the book path to exclude recommendations for other novels.
    if (segments.isEmpty) return true;
    final root = '/${segments.join('/')}';
    return candidate.path == root || candidate.path.startsWith('$root/');
  }

  Uri? _resolveLink(Uri base, String? href) {
    if (href == null || href.trim().isEmpty || href.startsWith('#')) {
      return null;
    }
    try {
      final uri = normalizeUri(base.resolve(href.trim()).toString());
      return _sameBook(base, uri) ? uri : null;
    } on FormatException {
      return null;
    }
  }

  Uri? _nextChapter(dom.Document doc, Uri base, Set<String> visited) {
    final currentNumber = _chapterNumber(base.pathSegments.lastOrNull ?? '');
    final candidates = <_ChapterLink>[];
    for (final element in doc.querySelectorAll('a[href], link[rel~=next]')) {
      final uri = _resolveLink(base, element.attributes['href']);
      if (uri == null || uri == base || visited.contains(uri.toString())) {
        continue;
      }
      final text = _cleanTitle(element.text).toLowerCase();
      final rel = (element.attributes['rel'] ?? '').toLowerCase().split(' ');
      final nextNumber = _chapterNumber(uri.pathSegments.lastOrNull ?? '');
      if (currentNumber != null &&
          nextNumber != null &&
          nextNumber <= currentNumber) {
        continue;
      }
      var score = 0;
      if (rel.contains('next')) score = 30;
      if (RegExp(
        r'^(?:next(?:\s+chapter|\s+page)?|continue)\b',
      ).hasMatch(text)) {
        score = 20;
      }
      if (currentNumber != null && nextNumber == currentNumber + 1) score += 10;
      if (score > 0) candidates.add(_ChapterLink(uri, text, score));
    }
    candidates.sort((a, b) => b.order.compareTo(a.order));
    return candidates.firstOrNull?.uri;
  }

  List<_ChapterLink> _chapterLinks(dom.Document doc, Uri base) {
    final seen = <String>{};
    final links = <_ChapterLink>[];
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final uri = _resolveLink(base, anchor.attributes['href']);
      if (uri == null || uri == base) continue;
      final title = _cleanTitle(anchor.text);
      final number =
          _chapterNumber(title) ??
          _chapterNumber(uri.pathSegments.lastOrNull ?? '');
      final isPrologue = title.toLowerCase().contains('prologue');
      if ((number == null && !isPrologue) || !seen.add(uri.toString())) {
        continue;
      }
      links.add(
        _ChapterLink(uri, title.isEmpty ? _pathTitle(uri) : title, number ?? 0),
      );
    }
    links.sort((a, b) => a.order.compareTo(b.order));
    return links;
  }
}

class NovelImportResult {
  const NovelImportResult({this.book, this.wasCancelled = false, this.warning});
  final NovelBook? book;
  final bool wasCancelled;
  final String? warning;
}

class _FetchedPage {
  const _FetchedPage({required this.uri, required this.document});
  final Uri uri;
  final dom.Document document;
}

class _ChapterLink {
  const _ChapterLink(this.uri, this.text, this.order);
  final Uri uri;
  final String text;
  final int order;
}

class WebAccessMode {
  const WebAccessMode({
    required this.id,
    required this.label,
    required this.description,
  });
  final String id;
  final String label;
  final String description;
}
