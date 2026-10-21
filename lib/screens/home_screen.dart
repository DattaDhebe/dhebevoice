import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/novel_book.dart';
import '../models/chapter_number.dart';
import '../models/reading_bookmark.dart';
import '../services/audio_handler_controller.dart';
import '../services/novel_import_controller.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../widgets/import_web_link_dialog.dart';
import '../widgets/home_reading_content.dart';
import '../widgets/book_library_sheet.dart';
import '../widgets/bookmark_sheet.dart';
import '../widgets/player_controls.dart';
import '../widgets/playback_status.dart';
import '../widgets/reader_consumer.dart';
import '../widgets/reader_list_sheet.dart';
import '../widgets/reader_view_dialog.dart';
import 'settings_screen.dart';

enum _ReaderAction {
  importFile,
  sleepTimer,
  settings,
  guide,
  saveBookmark,
  bookmarks,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _textController;
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  bool _isImportDialogOpen = false;
  DialogRoute<void>? _importProgressRoute;
  bool _isImportSetupDialogOpen = false;
  bool _isImportDialogMinimized = false;
  bool _hasScheduledFirstRunGuide = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = context.read<TtsService>();
    _textController = TextEditingController(text: service.text);
    _listenForSharedText();
    _scheduleFirstRunGuide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }

    final ttsService = context.read<TtsService>();
    unawaited(ttsService.handleAppLifecycleState(state));

    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  void _scheduleFirstRunGuide() {
    if (_hasScheduledFirstRunGuide) {
      return;
    }
    _hasScheduledFirstRunGuide = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showFirstRunGuideIfNeeded());
    });
  }

  Future<void> _showFirstRunGuideIfNeeded({bool force = false}) async {
    if (!mounted) {
      return;
    }

    final storage = context.read<StorageService>();
    if (storage.hasSeenHomeGuide && !force) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      return;
    }
    if (!force &&
        (_isImportSetupDialogOpen ||
            context.read<NovelImportController>().hasPendingSharedUrl)) {
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          title: const Text('Welcome to DhebeVoice'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Here is the quickest way to get started:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                const _GuideRow(
                  icon: Icons.edit_note_rounded,
                  title: 'Paste or import text',
                  body:
                      'Use the editor, import a file, or share a web link from your browser.',
                ),
                const SizedBox(height: 14),
                const _GuideRow(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Start playback',
                  body:
                      'Use Play, Pause, and Stop at the bottom to control reading aloud.',
                ),
                const SizedBox(height: 14),
                const _GuideRow(
                  icon: Icons.library_books_outlined,
                  title: 'Open your Book List',
                  body:
                      'Imported books and web pages stay in your library so you can return later.',
                ),
                const SizedBox(height: 14),
                const _GuideRow(
                  icon: Icons.menu_book_rounded,
                  title: 'Jump by chapter or paragraph',
                  body:
                      'Use Chapters and Play from paragraph to continue from the exact place you want.',
                ),
                const SizedBox(height: 14),
                const _GuideRow(
                  icon: Icons.tune_rounded,
                  title: 'Choose your voice',
                  body:
                      'Open Settings to change voice, speed, pitch, volume, and theme.',
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );

    await storage.saveHasSeenHomeGuide(true);
  }

  Future<void> _listenForSharedText() async {
    final importer = context.read<NovelImportController>();

    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((
      value,
    ) async {
      final sharedText = _extractSharedText(value);
      if (sharedText != null) {
        await _handleIncomingSharedText(importer, sharedText);
      }
    });

    final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
    final initialText = _extractSharedText(initialMedia);
    if (initialText != null) {
      await _handleIncomingSharedText(importer, initialText);
      await ReceiveSharingIntent.instance.reset();
    }
  }

  Future<void> _handleIncomingSharedText(
    NovelImportController importer,
    String sharedText,
  ) async {
    await importer.handleSharedPayload(sharedText);
    if (!mounted || !importer.hasPendingSharedUrl) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isImportSetupDialogOpen || _isImportDialogOpen) {
        return;
      }
      unawaited(_showImportUrlDialog());
    });
  }

  Future<void> _showImportUrlDialog() async {
    final importer = context.read<NovelImportController>();
    if (importer.isImporting) {
      setState(() => _isImportDialogMinimized = false);
      return;
    }
    if (_isImportSetupDialogOpen) {
      return;
    }
    _isImportSetupDialogOpen = true;
    String? url;
    try {
      url = await showDialog<String>(
        context: context,
        builder: (_) =>
            ImportWebLinkDialog(initialUrl: importer.pendingSharedUrl ?? ''),
      );
    } finally {
      _isImportSetupDialogOpen = false;
    }
    if (mounted && url != null) {
      await importer.importNovelFromUrl(url);
    }
  }

  void _showLibrarySheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BookLibrarySheet(onDelete: _confirmDeleteBook),
    );
  }

  Future<void> _confirmDeleteBook(NovelBook book) async {
    final importer = context.read<NovelImportController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete book?'),
        content: Text(
          'Remove "${book.title}" from your Book List? This cannot be undone. Text already open in the reader will remain until you replace it.',
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
    if (confirmed != true) return;
    try {
      final warning = await importer.deleteNovel(book.id);
      if (mounted && warning != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(warning)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete the book. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _saveBookmark() async {
    final importer = context.read<NovelImportController>();
    try {
      await importer.saveCurrentBookmark();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bookmark saved on this device.'),
            action: SnackBarAction(label: 'View', onPressed: _showBookmarks),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save this bookmark. Open a saved book and try again.',
            ),
          ),
        );
      }
    }
  }

  void _showBookmarks() {
    final importer = context.read<NovelImportController>();
    final book = importer.activeNovel;
    if (book == null) return;
    try {
      final bookmarks = importer.bookmarksForBook(book.id);
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => BookmarkSheet(
          bookId: book.id,
          importer: importer,
          bookmarks: bookmarks,
          onOpen: (mark, play) {
            Navigator.pop(sheetContext);
            unawaited(_openBookmark(book.id, mark, play));
          },
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved bookmarks could not be read. They have not been changed.',
          ),
        ),
      );
    }
  }

  Future<void> _openBookmark(
    String bookId,
    ReadingBookmark mark,
    bool play,
  ) async {
    try {
      await context.read<NovelImportController>().openBookmark(
        bookId,
        mark,
        play: play,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this bookmark. Its book or chapter may have changed.',
            ),
          ),
        );
      }
    }
  }

  void _showChapterSheet() {
    if (context.read<NovelImportController>().activeNovel == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Consumer<NovelImportController>(
        builder: (context, importer, _) => ReaderListSheet<NovelChapter>(
          title: 'Chapters',
          items: importer.activeNovel?.chapters ?? const [],
          selectedIndex: importer.activeChapterIndex,
          itemExtent: 88,
          searchHint: 'Search chapter name or number',
          searchText: (chapter, index) =>
              '${_chapterBadgeLabel(chapter, index)} ${chapter.title}',
          itemBuilder: (context, chapter, index) => ListTile(
            selected: index == importer.activeChapterIndex,
            leading: SizedBox(
              width: 62,
              child: _ChapterBadge(label: _chapterBadgeLabel(chapter, index)),
            ),
            title: Text(
              chapter.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: index == importer.activeChapterIndex
                ? const Icon(Icons.bookmark, size: 20)
                : null,
            onTap: () {
              Navigator.pop(context);
              unawaited(importer.selectChapter(index));
            },
          ),
        ),
      ),
    );
  }

  void _showParagraphSheet() {
    if (context.read<TtsService>().paragraphCount == 0) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ReaderConsumer(
        builder: (context, service) => ReaderListSheet<String>(
          title: 'Play from paragraph',
          items: service.paragraphs,
          selectedIndex: service.currentParagraphIndex,
          itemExtent: 112,
          searchHint: 'Search paragraph text or number',
          searchText: (paragraph, index) => '${index + 1} $paragraph',
          itemBuilder: (context, paragraph, index) => ListTile(
            selected: index == service.currentParagraphIndex,
            leading: _ChapterBadge(label: '${index + 1}'),
            title: Text(
              'Paragraph ${index + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              paragraph,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.pop(context);
              unawaited(service.playFromParagraph(index));
            },
          ),
        ),
      ),
    );
  }

  void _showReaderPopup() => _showReadingView(fullContent: false);
  void _showContentPopup() => _showReadingView(fullContent: true);

  void _showSettings() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _showReadingView({required bool fullContent}) {
    FocusManager.instance.primaryFocus?.unfocus();
    showDialog<void>(
      context: context,
      builder: (_) => ReaderViewDialog(
        fullContent: fullContent,
        onPlay: () => unawaited(_playUsingBestAvailableController()),
        onPause: () => unawaited(_pauseUsingBestAvailableController()),
        onStop: () => unawaited(_stopUsingBestAvailableController()),
        onSaveBookmark:
            context.read<NovelImportController>().activeNovel == null
            ? null
            : () => unawaited(_saveBookmark()),
      ),
    );
  }

  Future<void> _replaceEditorText(String value) async {
    final service = context.read<TtsService>();
    final importer = context.read<NovelImportController>();
    if (service.text.trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace reading text?'),
          content: const Text(
            'This stops playback and replaces the open text. Imported books stay in your Book List with their saved reading position.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await importer.clearActiveNovel();
    await service.updateText(value, resetPosition: true);
  }

  Future<void> _pasteText() async {
    final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted) return;
    if (value == null || value.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The clipboard does not contain text.')),
      );
      return;
    }
    await _replaceEditorText(value);
  }

  void _showSleepTimer() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ReaderConsumer(
        builder: (context, service) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sleep timer',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pause automatically without losing your place. The timer continues if you pause or change chapters.',
                ),
                const SizedBox(height: 16),
                for (final minutes in [15, 30, 45, 60])
                  ListTile(
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text('$minutes minutes'),
                    onTap: () {
                      service.setSleepTimer(Duration(minutes: minutes));
                      Navigator.pop(context);
                    },
                  ),
                if (service.sleepTimerEndsAt != null)
                  TextButton.icon(
                    onPressed: () {
                      service.setSleepTimer(null);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.timer_off_outlined),
                    label: const Text('Turn off timer'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _extractSharedText(List<SharedMediaFile> sharedItems) {
    for (final item in sharedItems) {
      final candidate = switch (item.type) {
        SharedMediaType.text || SharedMediaType.url => item.path,
        SharedMediaType.file ||
        SharedMediaType.image ||
        SharedMediaType.video => item.message,
      };

      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return null;
  }

  String _chapterBadgeLabel(NovelChapter chapter, int index) {
    final chapterNumber =
        ChapterNumber.parse(chapter.title, url: chapter.url) ?? (index + 1);
    return '#$chapterNumber';
  }

  Future<void> _playUsingBestAvailableController() async {
    final audioHandler = context.read<AudioHandlerController>().audioHandler;
    if (audioHandler != null) {
      await audioHandler.play();
      return;
    }

    await context.read<TtsService>().play();
  }

  Future<void> _pauseUsingBestAvailableController() async {
    final audioHandler = context.read<AudioHandlerController>().audioHandler;
    if (audioHandler != null) {
      await audioHandler.pause();
      return;
    }

    await context.read<TtsService>().pause();
  }

  Future<void> _stopUsingBestAvailableController() async {
    context.read<TtsService>().setSleepTimer(null);
    final audioHandler = context.read<AudioHandlerController>().audioHandler;
    if (audioHandler != null) {
      await audioHandler.stop();
      return;
    }

    await context.read<TtsService>().stop();
  }

  Future<void> _skipToPreviousUsingBestAvailableController() async {
    final audioHandler = context.read<AudioHandlerController>().audioHandler;
    if (audioHandler != null) {
      await audioHandler.skipToPrevious();
      return;
    }

    final importer = context.read<NovelImportController>();
    await importer.goToPreviousChapter();
  }

  Future<void> _skipToNextUsingBestAvailableController() async {
    final audioHandler = context.read<AudioHandlerController>().audioHandler;
    if (audioHandler != null) {
      await audioHandler.skipToNext();
      return;
    }

    final importer = context.read<NovelImportController>();
    await importer.goToNextChapter();
  }

  void _syncImportDialog(NovelImportController importer) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (importer.isImporting && !_isImportDialogOpen) {
        if (_isImportDialogMinimized) {
          return;
        }
        _isImportDialogOpen = true;
        final route = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _ImportProgressDialog(
            onMinimize: () {
              _closeImportProgress();
              if (mounted) {
                setState(() {
                  _isImportDialogMinimized = true;
                });
              }
            },
          ),
        );
        _importProgressRoute = route;
        Navigator.of(context, rootNavigator: true).push(route).then((_) {
          if (identical(_importProgressRoute, route)) {
            _importProgressRoute = null;
            _isImportDialogOpen = false;
          }
        });
        return;
      }

      if (!importer.isImporting && _isImportDialogOpen) {
        _closeImportProgress();
        return;
      }

      if (!importer.isImporting && _isImportDialogMinimized) {
        setState(() {
          _isImportDialogMinimized = false;
        });
      }
    });
  }

  void _closeImportProgress() {
    final route = _importProgressRoute;
    _importProgressRoute = null;
    _isImportDialogOpen = false;
    if (route == null || !route.isActive) return;
    final navigator = route.navigator;
    if (route.isCurrent) {
      navigator?.pop();
    } else {
      navigator?.removeRoute(route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderConsumer(
      builder: (context, ttsService) => Consumer<NovelImportController>(
        builder: (context, importer, _) {
          _syncImportDialog(importer);
          final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
          final audioHandlerController = context
              .watch<AudioHandlerController>();
          final controlsReady = ttsService.hasInitialized;
          final servicesReady = controlsReady && audioHandlerController.isReady;
          final startupError =
              audioHandlerController.errorMessage ?? ttsService.errorMessage;

          if (_textController.text != ttsService.text) {
            _textController.value = TextEditingValue(
              text: ttsService.text,
              selection: TextSelection.collapsed(
                offset: ttsService.text.length,
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  if (MediaQuery.sizeOf(context).width >= 360 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.5) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 21,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Flexible(
                    child: Text(
                      'DhebeVoice',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Import web link',
                  onPressed: _showImportUrlDialog,
                  icon: Badge(
                    isLabelVisible: importer.hasPendingSharedUrl,
                    child: const Icon(Icons.link),
                  ),
                ),
                IconButton(
                  tooltip: 'Library',
                  onPressed: _showLibrarySheet,
                  icon: Badge(
                    isLabelVisible: importer.library.isNotEmpty,
                    label: Text('${importer.library.length}'),
                    child: const Icon(Icons.library_books_outlined),
                  ),
                ),
                PopupMenuButton<_ReaderAction>(
                  tooltip: 'More options',
                  icon: Badge(
                    isLabelVisible: ttsService.sleepTimerEndsAt != null,
                    child: const Icon(Icons.more_vert),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _ReaderAction.importFile:
                        unawaited(importer.importLocalFile());
                      case _ReaderAction.sleepTimer:
                        _showSleepTimer();
                      case _ReaderAction.settings:
                        _showSettings();
                      case _ReaderAction.guide:
                        unawaited(_showFirstRunGuideIfNeeded(force: true));
                      case _ReaderAction.saveBookmark:
                        unawaited(_saveBookmark());
                      case _ReaderAction.bookmarks:
                        _showBookmarks();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _ReaderAction.importFile,
                      enabled: !importer.isImporting,
                      child: const ListTile(
                        leading: Icon(Icons.upload_file_outlined),
                        title: Text('Import file'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReaderAction.sleepTimer,
                      child: ListTile(
                        leading: const Icon(Icons.bedtime_outlined),
                        title: const Text('Sleep timer'),
                        subtitle: ttsService.sleepTimerEndsAt == null
                            ? null
                            : Text(
                                'Pause at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(ttsService.sleepTimerEndsAt!))}',
                              ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _ReaderAction.settings,
                      child: ListTile(
                        leading: Icon(Icons.tune),
                        title: Text('Settings'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _ReaderAction.guide,
                      child: ListTile(
                        leading: Icon(Icons.help_outline),
                        title: Text('Getting started'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReaderAction.saveBookmark,
                      enabled:
                          importer.activeChapter != null &&
                          ttsService.paragraphCount > 0,
                      child: const ListTile(
                        leading: Icon(Icons.bookmark_add_outlined),
                        title: Text('Save bookmark'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReaderAction.bookmarks,
                      enabled: importer.activeNovel != null,
                      child: const ListTile(
                        leading: Icon(Icons.bookmarks_outlined),
                        title: Text('Bookmarks & notes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: PlayerControls(
                      key: const ValueKey('home-playback-controls'),
                      embedded: true,
                      compactIconsOnly:
                          isKeyboardOpen &&
                          MediaQuery.sizeOf(context).height -
                                  MediaQuery.viewInsetsOf(context).bottom <
                              420,
                      status: PlaybackStatus(
                        service: ttsService,
                        compact:
                            isKeyboardOpen ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.4,
                      ),
                      stopEnabled:
                          ttsService.isPlaying ||
                          ttsService.isPaused ||
                          ttsService.isAdvancingChapter ||
                          ttsService.switchingVoice,
                      enabled:
                          controlsReady &&
                          !ttsService.switchingVoice &&
                          ttsService.paragraphCount > 0,
                      isPlaying:
                          ttsService.isPlaying || ttsService.isAdvancingChapter,
                      canResume:
                          ttsService.isPaused ||
                          ttsService.currentCharIndex > 0,
                      onPlay: () =>
                          unawaited(_playUsingBestAvailableController()),
                      onPause: () =>
                          unawaited(_pauseUsingBestAvailableController()),
                      onStop: () =>
                          unawaited(_stopUsingBestAvailableController()),
                      wrapInSafeArea: false,
                    ),
                  ),
                ),
              ),
            ),
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor,
                    Theme.of(context).colorScheme.surfaceContainerLow,
                  ],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final editorHeight = isKeyboardOpen
                        ? 180.0
                        : (constraints.maxHeight * 0.20).clamp(112.0, 240.0);

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: ListView(
                          key: const PageStorageKey('home-reader-scroll'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            if (importer.isImporting &&
                                _isImportDialogMinimized)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _ImportMiniBar(
                                  importer: importer,
                                  onOpenProgress: () {
                                    setState(() {
                                      _isImportDialogMinimized = false;
                                    });
                                  },
                                  onStop: () =>
                                      unawaited(importer.cancelImport()),
                                ),
                              ),
                            if (importer.activeNovel == null &&
                                controlsReady &&
                                !isKeyboardOpen &&
                                !importer.isImporting &&
                                !importer.hasPendingSharedUrl)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _StartListeningCard(
                                  onImportFile: importer.isImporting
                                      ? null
                                      : () => unawaited(
                                          importer.importLocalFile(),
                                        ),
                                  onWebLink: _showImportUrlDialog,
                                  onSleepTimer: _showSleepTimer,
                                  timerActive:
                                      ttsService.sleepTimerEndsAt != null,
                                  timerLabel:
                                      ttsService.sleepTimerEndsAt == null
                                      ? 'Sleep timer'
                                      : 'Pause at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(ttsService.sleepTimerEndsAt!))}',
                                ),
                              ),
                            if (startupError != null) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Text(
                                    startupError,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (startupError == null && !servicesReady) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.6,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          'Preparing voices and playback controls…',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ),
                                      if (!audioHandlerController.isReady)
                                        Text(
                                          'Starting',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (!importer.isImporting &&
                                importer.hasPendingSharedUrl)
                              _ImportStatusCard(
                                importer: importer,
                                onStartImport: _showImportUrlDialog,
                                onStartPendingImport: () => unawaited(
                                  importer.importPendingSharedUrl(),
                                ),
                                onClearSharedLink: () =>
                                    unawaited(importer.clearPendingSharedUrl()),
                              ),
                            if (!importer.isImporting &&
                                !importer.hasPendingSharedUrl &&
                                (importer.importStatus != null ||
                                    importer.errorMessage != null))
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          [
                                            if (importer.importStatus != null)
                                              importer.importStatus!,
                                            if (importer.errorMessage != null)
                                              importer.errorMessage!,
                                          ].join('\n'),
                                          style: importer.errorMessage == null
                                              ? null
                                              : TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Dismiss import message',
                                        onPressed: importer.clearImportMessage,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (importer.activeNovel != null) ...[
                              if (importer.isImporting &&
                                  _isImportDialogMinimized)
                                const SizedBox(height: 16)
                              else if (!importer.isImporting &&
                                  importer.hasPendingSharedUrl)
                                const SizedBox(height: 16),
                              _ActiveNovelCard(
                                importer: importer,
                                onOpenChapters: _showChapterSheet,
                                onPreviousChapter: () => unawaited(
                                  _skipToPreviousUsingBestAvailableController(),
                                ),
                                onNextChapter: () => unawaited(
                                  _skipToNextUsingBestAvailableController(),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            HomeReadingContent(
                              key: const ValueKey('home-content-section'),
                              controller: _textController,
                              editorHeight: editorHeight,
                              showBookEditingHint:
                                  importer.activeNovel != null &&
                                  isKeyboardOpen,
                              onViewFull: _showContentPopup,
                              onPaste: _pasteText,
                              onNewText: () =>
                                  unawaited(_replaceEditorText('')),
                              onPlaySelection: (selection) => unawaited(
                                ttsService.playSelection(selection),
                              ),
                              onChanged: (value) {
                                unawaited(importer.detachIfTextChanged(value));
                                unawaited(ttsService.updateText(value));
                              },
                            ),
                            if (!isKeyboardOpen &&
                                ttsService.paragraphCount > 0) ...[
                              const SizedBox(height: 16),
                              _NowReadingCard(
                                ttsService: ttsService,
                                chapterLabel: importer.activeChapter?.title,
                                onOpenParagraphs: _showParagraphSheet,
                                onOpenPopup: _showReaderPopup,
                                onVoiceSettings: _showSettings,
                                onSaveBookmark: importer.activeNovel == null
                                    ? null
                                    : () => unawaited(_saveBookmark()),
                                onBookmarks: importer.activeNovel == null
                                    ? null
                                    : _showBookmarks,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChapterBadge extends StatelessWidget {
  const _ChapterBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog({required this.onMinimize});

  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Consumer<NovelImportController>(
        builder: (context, importer, _) {
          final progressPercent = importer.importProgress == null
              ? null
              : (importer.importProgress! * 100).clamp(0, 100).round();

          return AlertDialog(
            scrollable: true,
            title: Row(
              children: [
                const Expanded(child: Text('Importing content')),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onMinimize,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    importer.importStatus ?? 'Preparing import...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: importer.importProgress),
                  if (progressPercent != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$progressPercent% complete',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    Text(
                      'Preparing and importing text...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: importer.isCancellingImport
                    ? null
                    : () => unawaited(importer.cancelImport()),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(
                  importer.isCancellingImport ? 'Stopping...' : 'Stop import',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImportMiniBar extends StatelessWidget {
  const _ImportMiniBar({
    required this.importer,
    required this.onOpenProgress,
    required this.onStop,
  });

  final NovelImportController importer;
  final VoidCallback onOpenProgress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final progressPercent = importer.importProgress == null
        ? null
        : (importer.importProgress! * 100).clamp(0, 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Importing content',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenProgress,
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Open'),
                ),
              ],
            ),
            if (importer.importStatus != null) ...[
              const SizedBox(height: 8),
              Text(
                importer.importStatus!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            LinearProgressIndicator(value: importer.importProgress),
            if (progressPercent != null) ...[
              const SizedBox(height: 10),
              Text('$progressPercent% complete'),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: importer.isCancellingImport ? null : onStop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(
                importer.isCancellingImport ? 'Stopping...' : 'Stop import',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportStatusCard extends StatelessWidget {
  const _ImportStatusCard({
    required this.importer,
    required this.onStartImport,
    required this.onStartPendingImport,
    required this.onClearSharedLink,
  });

  final NovelImportController importer;
  final VoidCallback onStartImport;
  final VoidCallback onStartPendingImport;
  final VoidCallback onClearSharedLink;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPendingSharedUrl = importer.hasPendingSharedUrl;
    final hasImportError = importer.errorMessage != null;
    final pendingUri = hasPendingSharedUrl
        ? Uri.tryParse(importer.pendingSharedUrl!)
        : null;
    final pendingLabel = pendingUri == null
        ? importer.pendingSharedUrl
        : pendingUri.host.isEmpty
        ? importer.pendingSharedUrl
        : pendingUri.host;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasPendingSharedUrl
                      ? Icons.share_outlined
                      : importer.isImporting
                      ? Icons.downloading_outlined
                      : Icons.link,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    importer.isImporting
                        ? 'Importing web content'
                        : hasImportError && hasPendingSharedUrl
                        ? 'Web import failed'
                        : hasPendingSharedUrl
                        ? 'Shared web link ready'
                        : 'Web import',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasPendingSharedUrl && !importer.isImporting)
                  IconButton(
                    tooltip: 'Clear shared link',
                    onPressed: onClearSharedLink,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (hasPendingSharedUrl) ...[
              const SizedBox(height: 10),
              Text(
                pendingLabel ?? importer.pendingSharedUrl!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (importer.pendingSharedUrl != pendingLabel) ...[
                const SizedBox(height: 4),
                Text(
                  importer.pendingSharedUrl!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
            if (importer.importStatus != null) ...[
              const SizedBox(height: 10),
              Text(importer.importStatus!),
            ],
            if (importer.isImporting || importer.importProgress != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: importer.importProgress),
            ],
            if (importer.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                importer.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (hasPendingSharedUrl && !importer.isImporting) ...[
              const SizedBox(height: 16),
              const SizedBox(height: 8),
              Text(
                'Only import text you own, are licensed to access, or that is in the public domain.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (importer.isImporting)
              TextButton.icon(
                onPressed: importer.isCancellingImport
                    ? null
                    : () => unawaited(importer.cancelImport()),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(
                  importer.isCancellingImport ? 'Stopping...' : 'Stop import',
                ),
              )
            else
              FilledButton.tonalIcon(
                onPressed: hasPendingSharedUrl
                    ? onStartPendingImport
                    : onStartImport,
                icon: Icon(
                  hasPendingSharedUrl
                      ? hasImportError
                            ? Icons.refresh_rounded
                            : Icons.play_circle_outline
                      : Icons.add_link,
                ),
                label: Text(
                  hasPendingSharedUrl
                      ? hasImportError
                            ? 'Try web import again'
                            : 'Start web import'
                      : 'Paste or import web link',
                ),
                style: FilledButton.styleFrom(
                  foregroundColor: colorScheme.onSecondaryContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StartListeningCard extends StatelessWidget {
  const _StartListeningCard({
    required this.onImportFile,
    required this.onWebLink,
    required this.onSleepTimer,
    required this.timerActive,
    required this.timerLabel,
  });

  final VoidCallback? onImportFile;
  final VoidCallback onWebLink;
  final VoidCallback onSleepTimer;
  final bool timerActive;
  final String timerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('start-listening'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What would you like to hear?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bring a book, a web page, or a few words of your own.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onImportFile,
                icon: const Icon(Icons.upload_file_outlined, size: 20),
                label: const Text('Import file'),
              ),
              OutlinedButton.icon(
                onPressed: onWebLink,
                icon: const Icon(Icons.link_rounded, size: 20),
                label: const Text('Web link'),
              ),
              TextButton.icon(
                onPressed: onSleepTimer,
                icon: Icon(
                  timerActive ? Icons.bedtime : Icons.bedtime_outlined,
                  size: 20,
                ),
                label: Text(timerLabel),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'TXT, EPUB and text-based PDF',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveNovelCard extends StatelessWidget {
  const _ActiveNovelCard({
    required this.importer,
    required this.onOpenChapters,
    required this.onPreviousChapter,
    required this.onNextChapter,
  });

  final NovelImportController importer;
  final VoidCallback onOpenChapters;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;

  @override
  Widget build(BuildContext context) {
    final novel = importer.activeNovel!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const ValueKey('active-book-card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_stories_outlined,
                    color: colors.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT BOOK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        novel.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (importer.activeChapter != null)
              Text(
                importer.activeChapter!.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '${importer.activeChapterIndex + 1} of ${novel.chapters.length} saved chapters - ${novel.sourceLabel}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Previous chapter',
                  onPressed: importer.activeChapterIndex > 0
                      ? onPreviousChapter
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onOpenChapters,
                    icon: const Icon(
                      Icons.format_list_bulleted_rounded,
                      size: 20,
                    ),
                    label: const Text(
                      'Chapters',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Next chapter',
                  onPressed:
                      importer.activeChapterIndex < novel.chapters.length - 1
                      ? onNextChapter
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NowReadingCard extends StatelessWidget {
  const _NowReadingCard({
    required this.ttsService,
    required this.chapterLabel,
    required this.onOpenParagraphs,
    required this.onOpenPopup,
    required this.onVoiceSettings,
    this.onSaveBookmark,
    this.onBookmarks,
  });

  final TtsService ttsService;
  final String? chapterLabel;
  final VoidCallback onOpenParagraphs;
  final VoidCallback onOpenPopup;
  final VoidCallback onVoiceSettings;
  final VoidCallback? onSaveBookmark;
  final VoidCallback? onBookmarks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surface = theme.cardTheme.color ?? colors.surface;
    final canNavigate = ttsService.hasInitialized && !ttsService.switchingVoice;
    return Card(
      key: const ValueKey('now-reading-card'),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        key: const ValueKey('now-reading-surface'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(colors.primary.withValues(alpha: .06), surface),
              surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Now reading',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: TextButton(
                      key: const ValueKey('now-reading-full-view'),
                      onPressed: onOpenPopup,
                      child: const Text(
                        'View full',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'Paragraph ${ttsService.currentParagraphIndex + 1} of ${ttsService.paragraphCount}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: ttsService.playbackState == ReaderPlaybackState.completed
                    ? 1
                    : ttsService.currentParagraphIndex /
                          ttsService.paragraphCount,
                minHeight: 3,
                borderRadius: BorderRadius.circular(4),
                semanticsLabel: 'Chapter reading progress',
              ),
              if (chapterLabel != null && chapterLabel!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  chapterLabel!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors.primary, width: 3),
                  ),
                ),
                child: Text(
                  ttsService.currentParagraph,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.65,
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous paragraph',
                    onPressed:
                        canNavigate && ttsService.currentParagraphIndex > 0
                        ? () => unawaited(ttsService.playPreviousParagraph())
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('paragraph-picker'),
                      onPressed: onOpenParagraphs,
                      icon: const Icon(
                        Icons.format_list_numbered_rounded,
                        size: 18,
                      ),
                      label: const Text(
                        'Play from paragraph',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next paragraph',
                    onPressed:
                        canNavigate &&
                            ttsService.currentParagraphIndex <
                                ttsService.paragraphCount - 1
                        ? () => unawaited(ttsService.playNextParagraph())
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              if (onSaveBookmark != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: onSaveBookmark,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('Save bookmark'),
                    ),
                    TextButton.icon(
                      onPressed: onBookmarks,
                      icon: const Icon(Icons.bookmarks_outlined, size: 18),
                      label: const Text('Bookmarks'),
                    ),
                  ],
                ),
              ],
              if (ttsService.selectedVoice != null) ...[
                const Divider(height: 20),
                Tooltip(
                  message: 'Voice & playback settings',
                  child: Semantics(
                    button: true,
                    child: InkWell(
                      onTap: onVoiceSettings,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectedVoiceLabel(service: ttsService),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.tune_rounded,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
