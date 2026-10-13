import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/novel_book.dart';

class NovelLibraryService {
  NovelLibraryService({Directory? directory}) : _directory = directory;

  final Directory? _directory;
  Future<void> _pendingWrite = Future<void>.value();

  Future<File> _libraryFile() async {
    final directory = _directory ?? await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}novel_library.json');
  }

  Future<List<NovelBook>> loadLibrary() async {
    await _pendingWrite;
    final file = await _libraryFile();
    if (!await file.exists()) {
      return const [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    return raw.length < 128 * 1024
        ? _decodeLibrary(raw)
        : compute(_decodeLibrary, raw);
  }

  static List<NovelBook> _decodeLibrary(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return const [];
    }

    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(NovelBook.fromJson)
        .toList();
  }

  Future<void> saveLibrary(List<NovelBook> books) {
    final snapshot = List<NovelBook>.of(books);
    final write = _pendingWrite.then((_) => _writeLibrary(snapshot));
    // Keep later saves usable after a failed write; the caller still sees it.
    _pendingWrite = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }

  Future<void> _writeLibrary(List<NovelBook> books) async {
    final file = await _libraryFile();
    final payload = await compute(_encodeLibrary, books);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    await temporary.rename(file.path);
  }

  static String _encodeLibrary(List<NovelBook> books) =>
      jsonEncode(books.map((book) => book.toJson()).toList());
}
