import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/novel_book.dart';
import '../services/novel_import_controller.dart';
import '../services/storage_service.dart';
import 'reader_list_sheet.dart';

class BookLibrarySheet extends StatefulWidget {
  const BookLibrarySheet({super.key, required this.onDelete});
  final Future<void> Function(NovelBook) onDelete;

  @override
  State<BookLibrarySheet> createState() => _BookLibrarySheetState();
}

class _BookLibrarySheetState extends State<BookLibrarySheet> {
  late String _sort;
  List<NovelBook>? _source;
  List<NovelBook> _sorted = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = context.read<StorageService>().librarySort;
    _sort = const {'newest', 'title', 'chapters'}.contains(saved)
        ? saved
        : 'newest';
  }

  Future<void> _changeSort(String value) async {
    if (_saving || value == _sort) return;
    setState(() => _saving = true);
    try {
      await context.read<StorageService>().saveLibrarySort(value);
      if (!mounted) return;
      setState(() {
        _sort = value;
        _source = null;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the sort order. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<NovelImportController>(
    builder: (context, importer, _) {
      if (!identical(_source, importer.library)) {
        _source = importer.library;
        final titles = {
          for (final book in importer.library)
            book.id: book.title.toLowerCase(),
        };
        _sorted = [...importer.library]
          ..sort((a, b) {
            final primary = switch (_sort) {
              'title' => titles[a.id]!.compareTo(titles[b.id]!),
              'chapters' => b.chapters.length.compareTo(a.chapters.length),
              _ => b.importedAt.compareTo(a.importedAt),
            };
            return primary != 0 ? primary : a.id.compareTo(b.id);
          });
      }
      return ReaderListSheet<NovelBook>(
        title: 'Book List',
        items: _sorted,
        selectedIndex: _sorted.indexWhere(
          (book) => book.id == importer.activeNovel?.id,
        ),
        itemExtent: 112,
        searchHint: 'Search books',
        emptyMessage:
            'Your imported books and web pages will appear here. Use Import file or Web link to add one.',
        searchText: (book, _) => '${book.title} ${book.sourceLabel}',
        headerActions: PopupMenuButton<String>(
          tooltip: 'Sort books',
          enabled: !_saving,
          icon: const Icon(Icons.sort),
          onSelected: (value) => unawaited(_changeSort(value)),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'newest',
              checked: _sort == 'newest',
              child: const Text('Newest first'),
            ),
            CheckedPopupMenuItem(
              value: 'title',
              checked: _sort == 'title',
              child: const Text('Title A to Z'),
            ),
            CheckedPopupMenuItem(
              value: 'chapters',
              checked: _sort == 'chapters',
              child: const Text('Most chapters'),
            ),
          ],
        ),
        itemBuilder: (context, book, _) => ListTile(
          selected: book.id == importer.activeNovel?.id,
          leading: Icon(
            book.id == importer.activeNovel?.id
                ? Icons.bookmark
                : Icons.menu_book_outlined,
          ),
          title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${book.chapters.length} chapters - ${book.sourceLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Delete ${book.title}',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(widget.onDelete(book)),
          ),
          onTap: () {
            Navigator.pop(context);
            unawaited(importer.selectNovel(book.id));
          },
        ),
      );
    },
  );
}
