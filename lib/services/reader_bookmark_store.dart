import 'dart:convert';

import '../models/reading_bookmark.dart';
import 'storage_service.dart';

/// Small, serialized metadata writes never re-encode the book's chapter text.
class ReaderBookmarkStore {
  ReaderBookmarkStore(this._storage);

  final StorageService _storage;
  final _cache = <String, List<ReadingBookmark>>{};
  Future<void> _pending = Future<void>.value();

  List<ReadingBookmark> forBook(String bookId) =>
      _cache.putIfAbsent(bookId, () {
        final raw = _storage.bookmarkData(bookId);
        if (raw == null) return const [];
        final decoded = jsonDecode(raw);
        if (decoded is! List || decoded.length > 500) {
          throw const FormatException('Saved bookmarks could not be read.');
        }
        final result = decoded.map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Saved bookmarks could not be read.');
          }
          return ReadingBookmark.fromJson(entry);
        }).toList();
        if (result.map((mark) => mark.id).toSet().length != result.length) {
          throw const FormatException(
            'Saved bookmarks contain duplicate entries.',
          );
        }
        return List.unmodifiable(result);
      });

  Future<void> save(String bookId, ReadingBookmark bookmark) =>
      _mutate(() async {
        if (bookId.isEmpty ||
            !ReadingBookmark.validNote(bookmark.note) ||
            bookmark.position < 0 ||
            bookmark.paragraphIndex < 0 ||
            bookmark.chapterUrl.isEmpty) {
          throw ArgumentError('A valid book, position, and note are required.');
        }
        final current = forBook(bookId);
        final old = current.where((mark) => mark.id == bookmark.id).firstOrNull;
        if (old == null && current.length >= 500) {
          throw StateError(
            'This book has 500 bookmarks. Remove one before adding another.',
          );
        }
        final updated = [
          bookmark.copyWith(createdAt: old?.createdAt),
          ...current.where((mark) => mark.id != bookmark.id),
        ];
        await _write(bookId, updated);
      });

  Future<void> remove(String bookId, String id) => _mutate(() async {
    final updated = forBook(bookId).where((mark) => mark.id != id).toList();
    await _write(bookId, updated);
  });

  Future<void> removeBook(String bookId) => _mutate(() async {
    await _storage.saveBookmarkData(bookId, null);
    _cache.remove(bookId);
  });

  Future<void> _write(String bookId, List<ReadingBookmark> updated) async {
    await _storage.saveBookmarkData(
      bookId,
      jsonEncode(updated.map((mark) => mark.toJson()).toList()),
    );
    _cache[bookId] = List.unmodifiable(updated);
  }

  Future<void> _mutate(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
