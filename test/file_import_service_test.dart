import 'dart:ui';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:text_reader_app/services/file_import_service.dart';

class PdfPicker extends FilePicker {
  PdfPicker(this.bytes, {this.name = 'sample.pdf', this.size});
  final Uint8List bytes;
  final String name;
  final int? size;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(name: name, size: size ?? bytes.length, bytes: bytes),
  ]);
}

void main() {
  test('text import supports UTF-8 BOM and both UTF-16 byte orders', () async {
    final samples = [
      Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('Hello')]),
      Uint8List.fromList([0xff, 0xfe, 72, 0, 105, 0]),
      Uint8List.fromList([0xfe, 0xff, 0, 72, 0, 105]),
    ];
    for (var i = 0; i < samples.length; i++) {
      FilePicker.platform = PdfPicker(samples[i], name: 'story.txt');
      final imported = await FileImportService().importReaderFile();
      expect(imported!.text, i == 0 ? 'Hello' : 'Hi');
    }
  });

  test(
    'empty, unsupported, binary and oversized files report errors',
    () async {
      final samples = [
        PdfPicker(Uint8List(0), name: 'empty.txt'),
        PdfPicker(Uint8List.fromList([1]), name: 'file.exe'),
        PdfPicker(Uint8List.fromList([65, 0, 66]), name: 'binary.txt'),
        PdfPicker(Uint8List.fromList([0xff, 0xfe, 65]), name: 'truncated.txt'),
        PdfPicker(
          Uint8List.fromList([65]),
          name: 'large.txt',
          size: FileImportService.maxFileBytes + 1,
        ),
      ];
      for (final picker in samples) {
        FilePicker.platform = picker;
        await expectLater(
          FileImportService().importReaderFile(),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'same PDF contents are stable and same filename cannot replace a different book',
    () async {
      Uint8List makePdf(String text) {
        final document = PdfDocument();
        document.pages.add().graphics.drawString(
          text,
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
        final bytes = Uint8List.fromList(document.saveSync());
        document.dispose();
        return bytes;
      }

      final firstBytes = makePdf('First book text');
      FilePicker.platform = PdfPicker(firstBytes);
      final first = (await FileImportService().importReaderFile())!.book!;
      FilePicker.platform = PdfPicker(firstBytes, name: 'renamed.pdf');
      final repeated = (await FileImportService().importReaderFile())!.book!;
      FilePicker.platform = PdfPicker(makePdf('Different book text'));
      final different = (await FileImportService().importReaderFile())!.book!;
      expect(repeated.id, first.id);
      expect(repeated.sourceUrl, first.sourceUrl);
      expect(different.sourceUrl, isNot(first.sourceUrl));
    },
  );

  test('EPUB preserves dialogue and does not repeat whole HTML for TOC anchors', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<?xml version="1.0"?><container version="1.0" '
              'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
              '<rootfiles><rootfile full-path="book.opf" '
              'media-type="application/oebps-package+xml"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'book.opf',
          '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">'
              '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
              '<dc:title>A sample book</dc:title><dc:identifier id="bookid">test</dc:identifier>'
              '<dc:language>en</dc:language></metadata><manifest>'
              '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
              '<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>'
              '</manifest><spine toc="ncx"><itemref idref="chapter"/></spine></package>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'toc.ncx',
          '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
              '<head/><docTitle><text>A sample book</text></docTitle><navMap>'
              '<navPoint id="one" playOrder="1"><navLabel><text>Chapter 1</text></navLabel>'
              '<content src="chapter.xhtml#a"/>'
              '<navPoint id="two" playOrder="2"><navLabel><text>Part two</text></navLabel>'
              '<content src="chapter.xhtml#b"/></navPoint></navPoint></navMap></ncx>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'chapter.xhtml',
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
              '<p id="a">Yes.</p><p id="b">No!</p><p>One<br/>Two</p></body></html>',
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    FilePicker.platform = PdfPicker(bytes, name: 'sample.epub');
    final imported = (await FileImportService().importReaderFile())!.book!;
    expect(imported.title, 'A sample book');
    expect(imported.chapters, hasLength(1));
    expect(imported.chapters.single.content, 'Yes.\n\nNo!\n\nOne\nTwo');
  });

  test(
    'EPUB expansion limits are checked before reading its content',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('large.html', 'Hello'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 28; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          data.setUint32(i + 24, 101 * 1024 * 1024, Endian.little);
          break;
        }
      }
      FilePicker.platform = PdfPicker(bytes, name: 'large.epub');
      await expectLater(
        FileImportService().importReaderFile(),
        throwsA(
          predicate((e) => e.toString().contains('too large after unpacking')),
        ),
      );
    },
  );

  test('PDF import extracts text on the background worker', () async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
      'A readable sample chapter.',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      bounds: const Rect.fromLTWH(10, 10, 400, 30),
    );
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    FilePicker.platform = PdfPicker(bytes);
    final imported = await FileImportService().importReaderFile();
    expect(imported!.kind, ImportedReaderFileKind.pdf);
    expect(
      imported.book!.chapters.single.content,
      contains('A readable sample chapter.'),
    );
    expect(imported.book!.chapters.single.title, 'Page 1');
  });

  test('PDF without readable text reports an actionable error', () async {
    final document = PdfDocument();
    document.pages.add();
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    FilePicker.platform = PdfPicker(bytes);
    await expectLater(
      FileImportService().importReaderFile(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('readable text'),
        ),
      ),
    );
  });
}
