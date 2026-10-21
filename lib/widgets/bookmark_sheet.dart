import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reading_bookmark.dart';
import '../services/novel_import_controller.dart';
import 'reader_list_sheet.dart';

class BookmarkSheet extends StatefulWidget {
  const BookmarkSheet({
    super.key,
    required this.bookId,
    required this.importer,
    required this.bookmarks,
    required this.onOpen,
  });
  final String bookId;
  final NovelImportController importer;
  final List<ReadingBookmark> bookmarks;
  final void Function(ReadingBookmark, bool) onOpen;

  @override
  State<BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends State<BookmarkSheet> {
  late List<ReadingBookmark> _marks = widget.bookmarks;
  bool _busy = false;

  Future<void> _edit(ReadingBookmark mark) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => BookmarkNoteDialog(initialNote: mark.note),
    );
    if (!mounted || note == null) return;
    await _mutate(
      () => widget.importer.updateBookmark(widget.bookId, mark, note),
    );
  }

  Future<void> _delete(ReadingBookmark mark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete bookmark?'),
        content: const Text(
          'This removes the bookmark and its note, not the book.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _mutate(() => widget.importer.deleteBookmark(widget.bookId, mark));
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        setState(
          () => _marks = widget.importer.bookmarksForBook(widget.bookId),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save bookmark changes. Your saved notes have not been replaced.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReaderListSheet<ReadingBookmark>(
    title: 'Bookmarks & notes',
    items: _marks,
    itemExtent: 144,
    searchHint: 'Search chapter, passage or note',
    emptyMessage:
        'No bookmarks yet. Use Save bookmark while reading a saved book.',
    searchText: (mark, _) =>
        '${mark.chapterTitle} ${mark.paragraphIndex + 1} ${mark.excerpt} ${mark.note}',
    itemBuilder: (context, mark, _) => ListTile(
      enabled: !_busy,
      title: Text(
        mark.note.isEmpty ? mark.chapterTitle : mark.note,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Paragraph ${mark.paragraphIndex + 1}${mark.note.isEmpty ? '' : ' - ${mark.chapterTitle}'}\n${mark.excerpt}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => widget.onOpen(mark, false),
      trailing: PopupMenuButton<String>(
        tooltip: 'Bookmark actions',
        enabled: !_busy,
        onSelected: (value) {
          switch (value) {
            case 'play':
              widget.onOpen(mark, true);
            case 'edit':
              _edit(mark);
            case 'delete':
              _delete(mark);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'play', child: Text('Play from bookmark')),
          PopupMenuItem(value: 'edit', child: Text('Edit note')),
          PopupMenuItem(value: 'delete', child: Text('Delete bookmark')),
        ],
      ),
    ),
  );
}

class BookmarkNoteDialog extends StatefulWidget {
  const BookmarkNoteDialog({super.key, required this.initialNote});
  final String initialNote;
  @override
  State<BookmarkNoteDialog> createState() => _BookmarkNoteDialogState();
}

class _BookmarkNoteDialogState extends State<BookmarkNoteDialog> {
  late final _controller = TextEditingController(text: widget.initialNote);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Bookmark note'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLines: 4,
      maxLength: 1000,
      inputFormatters: [
        TextInputFormatter.withFunction(
          (previous, next) => next.text.length <= 16000 ? next : previous,
        ),
      ],
      decoration: const InputDecoration(
        labelText: 'Note (optional)',
        hintText: 'Why save this passage?',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save note'),
      ),
    ],
  );
}
