import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:text_reader_app/services/file_import_service.dart';

class PdfPicker extends FilePicker {
  PdfPicker(this.bytes);
  final Uint8List bytes;

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
    PlatformFile(name: 'sample.pdf', size: bytes.length, bytes: bytes),
  ]);
}

void main() {
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
