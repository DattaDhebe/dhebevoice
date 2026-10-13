import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:epub_pro/epub_pro.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/novel_book.dart';
import '../models/readable_html.dart';

enum ImportedReaderFileKind { text, epub, pdf }

class ImportedReaderFile {
  const ImportedReaderFile._({
    required this.kind,
    required this.name,
    this.text,
    this.book,
  });

  factory ImportedReaderFile.text({
    required String name,
    required String text,
  }) {
    return ImportedReaderFile._(
      kind: ImportedReaderFileKind.text,
      name: name,
      text: text,
    );
  }

  factory ImportedReaderFile.epub({
    required String name,
    required NovelBook book,
  }) {
    return ImportedReaderFile._(
      kind: ImportedReaderFileKind.epub,
      name: name,
      book: book,
    );
  }

  factory ImportedReaderFile.pdf({
    required String name,
    required NovelBook book,
  }) {
    return ImportedReaderFile._(
      kind: ImportedReaderFileKind.pdf,
      name: name,
      book: book,
    );
  }

  final ImportedReaderFileKind kind;
  final String name;
  final String? text;
  final NovelBook? book;
}

class FileImportService {
  static const maxFileBytes = 50 * 1024 * 1024;
  static const _maxTextCharacters = 12 * 1024 * 1024;

  Future<ImportedReaderFile?> importReaderFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub', 'pdf'],
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final fileName = file.name.trim().isEmpty
        ? 'Imported file'
        : file.name.trim();
    final extension = _fileExtension(fileName);
    if (!{'txt', 'epub', 'pdf'}.contains(extension)) {
      throw const FormatException('Choose a TXT, EPUB or PDF file.');
    }
    final bytes = await _readBytes(file);

    switch (extension) {
      case 'pdf':
        final book = await compute(_parsePdfInBackground, (bytes, fileName));
        return ImportedReaderFile.pdf(name: fileName, book: book);
      case 'epub':
        final book = await compute(_parseEpubInBackground, (bytes, fileName));
        return ImportedReaderFile.epub(name: fileName, book: book);
      case 'txt':
      default:
        final text = await compute(_decodeText, bytes);
        if (text.trim().isEmpty) {
          throw const FormatException('This text file is empty.');
        }
        return ImportedReaderFile.text(name: fileName, text: text.trim());
    }
  }

  Future<String?> importTextFile() async {
    final imported = await importReaderFile();
    if (imported == null || imported.kind != ImportedReaderFileKind.text) {
      return null;
    }
    return imported.text;
  }

  static NovelBook _parsePdfInBackground((Uint8List, String) input) {
    try {
      return FileImportService()._parsePdf(input.$1, input.$2);
    } on FormatException {
      rethrow;
    } catch (error) {
      if (error.toString().contains('readable text')) rethrow;
      throw const FormatException(
        'Could not read this PDF. It may be damaged or password-protected. '
        'Use an unprotected copy you are authorized to read.',
      );
    }
  }

  static Future<NovelBook> _parseEpubInBackground(
    (Uint8List, String) input,
  ) async {
    try {
      return await FileImportService()._parseEpub(input.$1, input.$2);
    } on FormatException {
      rethrow;
    } catch (error) {
      if (error.toString().contains('readable chapter text')) rethrow;
      throw const FormatException(
        'Could not read this EPUB. It may be damaged or encrypted. '
        'Use an unprotected copy you are authorized to read.',
      );
    }
  }

  Future<Uint8List> _readBytes(PlatformFile file) async {
    if (file.size > maxFileBytes) {
      throw const FormatException('This file exceeds the 50 MB import limit.');
    }
    if (file.bytes != null) {
      _validateBytes(file.bytes!);
      return file.bytes!;
    }

    final path = file.path;
    if (path == null) {
      throw const FormatException('Could not read this file. Select it again.');
    }
    final source = File(path);
    if (await source.length() > maxFileBytes) {
      throw const FormatException('This file exceeds the 50 MB import limit.');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      if (buffer.length + chunk.length > maxFileBytes) {
        throw const FormatException(
          'This file exceeds the 50 MB import limit.',
        );
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    _validateBytes(bytes);
    return bytes;
  }

  void _validateBytes(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('This file is empty.');
    if (bytes.length > maxFileBytes) {
      throw const FormatException('This file exceeds the 50 MB import limit.');
    }
  }

  static String _decodeText(Uint8List bytes) {
    String text;
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) {
        throw const FormatException('This UTF-16 text file is incomplete.');
      }
      final data = ByteData.sublistView(bytes);
      final endian = bytes[0] == 0xff ? Endian.little : Endian.big;
      text = String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2) data.getUint16(i, endian),
      ]);
    } else {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw const FormatException(
          'Save this text file as UTF-8 or UTF-16 and try again.',
        );
      }
    }
    text = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    if (text.contains('\u0000')) {
      throw const FormatException(
        'This file does not contain supported plain text.',
      );
    }
    if (text.length > _maxTextCharacters) {
      throw const FormatException(
        'This text file is too long. Split it into smaller files.',
      );
    }
    return text;
  }

  Future<NovelBook> _parseEpub(Uint8List bytes, String fileName) async {
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.isEmpty) {
      throw const FormatException(
        'This EPUB is damaged or is not an EPUB archive.',
      );
    }
    final expandedSize = directory.fileHeaders.fold<int>(
      0,
      (total, file) => total + file.uncompressedSize,
    );
    if (directory.fileHeaders.length > 5000 ||
        expandedSize > 100 * 1024 * 1024 ||
        directory.fileHeaders.any(
          (file) => file.uncompressedSize > 20 * 1024 * 1024,
        )) {
      throw const FormatException(
        'This EPUB is too large after unpacking. Choose a smaller book.',
      );
    }
    if (directory.fileHeaders.any(
      (file) => file.generalPurposeBitFlag & 1 != 0,
    )) {
      throw const FormatException('Encrypted EPUB files are not supported.');
    }
    final epubBook = await EpubReader.readBook(bytes);
    final chapters = <NovelChapter>[];
    final source = 'local-epub://${sha256.convert(bytes)}';
    final seen = <String>{};
    var characters = 0;

    void visitChapter(EpubChapter chapter, {String? inheritedTitle}) {
      final rawTitle = (chapter.title ?? '').trim();
      final chapterTitle = rawTitle.isNotEmpty
          ? rawTitle
          : (inheritedTitle?.trim().isNotEmpty ?? false)
          ? inheritedTitle!.trim()
          : 'Chapter ${chapters.length + 1}';
      final plainText = _extractPlainText(chapter.htmlContent);

      final key = chapter.contentFileName?.trim();
      final identity = key == null || key.isEmpty
          ? sha256.convert(utf8.encode(plainText)).toString()
          : key;
      if (plainText.isNotEmpty && seen.add(identity)) {
        characters += plainText.length;
        if (characters > _maxTextCharacters) {
          throw const FormatException(
            'This EPUB has too much text. Import a smaller book.',
          );
        }
        chapters.add(
          NovelChapter(
            title: chapterTitle,
            url: '$source#${chapters.length + 1}',
            content: plainText,
            order: chapters.length,
          ),
        );
      }

      for (final subChapter in chapter.subChapters) {
        visitChapter(subChapter, inheritedTitle: chapterTitle);
      }
    }

    for (final chapter in epubBook.chapters) {
      visitChapter(chapter);
    }

    if (chapters.isEmpty) {
      throw Exception(
        'DhebeVoice could not find readable chapter text inside this EPUB.',
      );
    }

    final title = (epubBook.title ?? '').trim().isNotEmpty
        ? epubBook.title!.trim()
        : _fileNameWithoutExtension(fileName);

    return NovelBook(
      id: 'epub_${sha256.convert(bytes)}',
      title: title,
      sourceUrl: source,
      importedAt: DateTime.now(),
      chapters: chapters,
    );
  }

  NovelBook _parsePdf(Uint8List bytes, String fileName) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      if (document.pages.count > 1500) {
        throw const FormatException(
          'This PDF exceeds the 1,500-page import limit.',
        );
      }
      final extractor = PdfTextExtractor(document);
      final chapters = <NovelChapter>[];
      final source = 'local-pdf://${sha256.convert(bytes)}';
      var characters = 0;

      for (var pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
        final pageNumber = pageIndex + 1;
        final text = _normalizePdfText(
          extractor.extractText(
            startPageIndex: pageIndex,
            endPageIndex: pageIndex,
          ),
        );
        if (text.isEmpty) {
          continue;
        }
        characters += text.length;
        if (characters > _maxTextCharacters) {
          throw const FormatException(
            'This PDF has too much text. Split it into smaller files.',
          );
        }

        chapters.add(
          NovelChapter(
            title: 'Page $pageNumber',
            url: '$source#$pageNumber',
            content: text,
            order: chapters.length,
          ),
        );
      }

      if (chapters.isEmpty) {
        throw Exception(
          'DhebeVoice could not find readable text inside this PDF. Scanned pages need OCR first.',
        );
      }

      final rawTitle = document.documentInformation.title;
      final title = rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : _fileNameWithoutExtension(fileName);

      return NovelBook(
        id: 'pdf_${sha256.convert(bytes)}',
        title: title,
        sourceUrl: source,
        importedAt: DateTime.now(),
        chapters: chapters,
      );
    } finally {
      document.dispose();
    }
  }

  String _extractPlainText(String? htmlContent) {
    if (htmlContent == null || htmlContent.trim().isEmpty) {
      return '';
    }

    final document = html_parser.parse(htmlContent);
    return readableHtml(document.body ?? document.documentElement);
  }

  String _normalizePdfText(String? input) {
    if (input == null || input.trim().isEmpty) {
      return '';
    }

    final lines = input
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n\n');
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _fileNameWithoutExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}
