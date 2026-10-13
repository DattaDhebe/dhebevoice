import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/novel_book.dart';
import '../services/audio_handler_controller.dart';
import '../services/novel_import_controller.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../widgets/player_controls.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _textController;
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  bool _isImportDialogOpen = false;
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

  Future<void> _showFirstRunGuideIfNeeded() async {
    if (!mounted) {
      return;
    }

    final storage = context.read<StorageService>();
    if (storage.hasSeenHomeGuide) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
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
    if (_isImportSetupDialogOpen) {
      return;
    }
    final controller = TextEditingController(
      text: importer.pendingSharedUrl ?? '',
    );
    _isImportSetupDialogOpen = true;

    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            scrollable: true,
            title: const Text('Import web link'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'Paste web page URL',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Import only text you own, are licensed to access, or that is in the public domain.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await importer.importNovelFromUrl(controller.text);
                },
                child: const Text('Start import'),
              ),
            ],
          );
        },
      );
    } finally {
      _isImportSetupDialogOpen = false;
      controller.dispose();
    }
  }

  void _showLibrarySheet() {
    final importer = context.read<NovelImportController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: importer.library.isEmpty
                ? const Center(
                    child: Text(
                      'Imported books and web pages will appear here.',
                    ),
                  )
                : ListView.builder(
                    itemCount: importer.library.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: Text(
                            'Book List',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        );
                      }

                      final book = importer.library[index - 1];
                      return ListTile(
                        title: Text(book.title),
                        subtitle: Text(
                          '${book.chapters.length} chapters • ${Uri.tryParse(book.sourceUrl)?.host ?? book.sourceUrl}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await importer.deleteNovel(book.id);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                        onTap: () async {
                          await importer.selectNovel(book.id);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _showChapterSheet() {
    final importer = context.read<NovelImportController>();
    final novel = importer.activeNovel;
    if (novel == null) {
      return;
    }
    final selectedIndex = importer.activeChapterIndex;
    final controller = ScrollController(
      initialScrollOffset: max(0.0, (selectedIndex - 2) * 72.0),
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: ListView.builder(
              controller: controller,
              itemExtent: 72,
              itemCount: novel.chapters.length,
              itemBuilder: (context, index) {
                final chapter = novel.chapters[index];
                final chapterBadge = _chapterBadgeLabel(chapter, index);
                return ListTile(
                  selected: index == importer.activeChapterIndex,
                  title: Row(
                    children: [
                      SizedBox(
                        width: 78,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _ChapterBadge(label: chapterBadge),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          chapter.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(importer.selectChapter(index));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showParagraphSheet() {
    final ttsService = context.read<TtsService>();
    if (ttsService.paragraphCount == 0) {
      return;
    }
    final selectedIndex = ttsService.currentParagraphIndex;
    final controller = ScrollController(
      initialScrollOffset: max(0.0, (selectedIndex - 2) * 88.0),
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: ListView.builder(
              controller: controller,
              itemExtent: 88,
              itemCount: ttsService.paragraphCount,
              itemBuilder: (context, index) {
                final preview = ttsService.paragraphs[index];
                return ListTile(
                  selected: index == ttsService.currentParagraphIndex,
                  leading: _ChapterBadge(label: '#P${index + 1}'),
                  title: Text(
                    'Paragraph ${index + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(ttsService.playFromParagraph(index));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showReaderPopup() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final dialogWidth = min(MediaQuery.sizeOf(context).width * 0.9, 620.0);
        final dialogHeight = min(
          MediaQuery.sizeOf(context).height * 0.6,
          540.0,
        );

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Consumer2<NovelImportController, TtsService>(
              builder: (context, importer, ttsService, _) {
                final colorScheme = Theme.of(context).colorScheme;
                final activeTitle = importer.activeChapter?.title ?? '';
                final chapterText = activeTitle.trim().isNotEmpty
                    ? activeTitle
                    : 'Manual text';

                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Now reading',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        chapterText,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: ttsService.currentParagraphIndex > 0
                                ? () => unawaited(
                                    ttsService.playPreviousParagraph(),
                                  )
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              'Paragraph ${ttsService.currentParagraphIndex + 1}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed:
                                ttsService.currentParagraphIndex <
                                    ttsService.paragraphCount - 1
                                ? () =>
                                      unawaited(ttsService.playNextParagraph())
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            ttsService.currentParagraph,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  height: 1.6,
                                  color: colorScheme.primary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      PlayerControls(
                        isPlaying: ttsService.isPlaying,
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
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showContentPopup() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final dialogWidth = min(MediaQuery.sizeOf(context).width * 0.94, 760.0);
        final dialogHeight = min(
          MediaQuery.sizeOf(context).height * 0.76,
          680.0,
        );
        final contentText = _textController.text.trim().isEmpty
            ? 'Paste text here, import a file, or share a web link from your browser.'
            : _textController.text;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Reading content',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: SelectionArea(
                        child: SingleChildScrollView(
                          child: Text(
                            contentText,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(height: 1.55),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        _extractChapterNumber(chapter.title) ??
        _extractChapterNumber(chapter.url) ??
        (index + 1);
    return '#$chapterNumber';
  }

  int? _extractChapterNumber(String value) {
    final match = RegExp(
      r'(?:chapter|chap|episode|ep|part)[\s\-_:]*(\d+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }

    final fallback = RegExp(r'(\d+)').firstMatch(value);
    return fallback == null ? null : int.tryParse(fallback.group(1) ?? '');
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
    final ttsService = context.read<TtsService>();
    final shouldResume = ttsService.isPlaying;
    await importer.goToPreviousChapter();
    if (shouldResume) {
      await ttsService.play();
    }
  }

  Future<void> _skipToNextUsingBestAvailableController() async {
    final audioHandler = context.read<AudioHandlerController>().audioHandler;
    if (audioHandler != null) {
      await audioHandler.skipToNext();
      return;
    }

    final importer = context.read<NovelImportController>();
    final ttsService = context.read<TtsService>();
    final shouldResume = ttsService.isPlaying;
    await importer.goToNextChapter();
    if (shouldResume) {
      await ttsService.play();
    }
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
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _ImportProgressDialog(
            onMinimize: () {
              Navigator.of(context, rootNavigator: true).pop();
              if (mounted) {
                setState(() {
                  _isImportDialogMinimized = true;
                });
              }
            },
          ),
        ).then((_) {
          _isImportDialogOpen = false;
        });
        return;
      }

      if (!importer.isImporting && _isImportDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        return;
      }

      if (!importer.isImporting && _isImportDialogMinimized) {
        setState(() {
          _isImportDialogMinimized = false;
        });
      }
    });
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
    return Consumer2<NovelImportController, TtsService>(
      builder: (context, importer, ttsService, _) {
        _syncImportDialog(importer);
        final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final audioHandlerController = context.watch<AudioHandlerController>();
        final controlsReady =
            ttsService.hasInitialized && audioHandlerController.isReady;
        final startupError =
            audioHandlerController.errorMessage ?? ttsService.errorMessage;

        if (_textController.text != ttsService.text) {
          _textController.value = TextEditingValue(
            text: ttsService.text,
            selection: TextSelection.collapsed(offset: ttsService.text.length),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('DhebeVoice'),
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
              IconButton(
                tooltip: 'Import .txt, .epub, or .pdf file',
                onPressed: () async {
                  await importer.importLocalFile();
                },
                icon: const Icon(Icons.upload_file),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Opacity(
              opacity: controlsReady ? 1 : 0.7,
              child: IgnorePointer(
                ignoring: !controlsReady,
                child: PlayerControls(
                  isPlaying: ttsService.isPlaying,
                  canResume:
                      ttsService.isPaused || ttsService.currentCharIndex > 0,
                  onPlay: () => unawaited(_playUsingBestAvailableController()),
                  onPause: () =>
                      unawaited(_pauseUsingBestAvailableController()),
                  onStop: () => unawaited(_stopUsingBestAvailableController()),
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final editorHeight = isKeyboardOpen
                    ? 220.0
                    : (constraints.maxHeight * 0.38).clamp(260.0, 460.0);

                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (startupError != null) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            startupError,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (startupError == null && !controlsReady) ...[
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
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              if (!audioHandlerController.isReady)
                                Text(
                                  'Starting',
                                  style: Theme.of(context).textTheme.labelMedium
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
                    if (importer.isImporting && _isImportDialogMinimized)
                      _ImportMiniBar(
                        importer: importer,
                        onOpenProgress: () {
                          setState(() {
                            _isImportDialogMinimized = false;
                          });
                        },
                        onStop: () => unawaited(importer.cancelImport()),
                      ),
                    if (!importer.isImporting && importer.hasPendingSharedUrl)
                      _ImportStatusCard(
                        importer: importer,
                        onStartImport: _showImportUrlDialog,
                        onStartPendingImport: () =>
                            unawaited(importer.importPendingSharedUrl()),
                        onClearSharedLink: () =>
                            unawaited(importer.clearPendingSharedUrl()),
                      ),
                    if (importer.activeNovel != null) ...[
                      if (importer.isImporting && _isImportDialogMinimized)
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
                    SizedBox(
                      height: editorHeight,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Reading content',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _showContentPopup,
                                    icon: const Icon(Icons.open_in_full),
                                    label: const Text('View full'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.copyWith(height: 1.5),
                                  contextMenuBuilder: (context, editableTextState) {
                                    final selection = editableTextState
                                        .textEditingValue
                                        .selection;
                                    final buttonItems = <ContextMenuButtonItem>[
                                      ...editableTextState
                                          .contextMenuButtonItems,
                                      if (selection.isValid &&
                                          !selection.isCollapsed)
                                        ContextMenuButtonItem(
                                          label: 'Play selection',
                                          onPressed: () {
                                            ContextMenuController.removeAny();
                                            unawaited(
                                              ttsService.playSelection(
                                                selection,
                                              ),
                                            );
                                          },
                                        ),
                                    ];

                                    return AdaptiveTextSelectionToolbar.buttonItems(
                                      anchors:
                                          editableTextState.contextMenuAnchors,
                                      buttonItems: buttonItems,
                                    );
                                  },
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Paste text here, import a .txt, .epub, or .pdf file, or share a web link from your browser.',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    filled: false,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (value) {
                                    unawaited(
                                      importer.detachIfTextChanged(value),
                                    );
                                    unawaited(ttsService.updateText(value));
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isKeyboardOpen) ...[
                      const SizedBox(height: 16),
                      _NowReadingCard(
                        ttsService: ttsService,
                        chapterLabel: importer.activeChapter?.title,
                        onOpenParagraphs: _showParagraphSheet,
                        onOpenPopup: _showReaderPopup,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
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
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
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
            title: Row(
              children: [
                const Expanded(child: Text('Importing web content')),
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
                      'Following links and importing text...',
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
                    'Importing web content',
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
              Text(importer.importStatus!),
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
    final chapter = importer.activeChapter;
    final actionStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(novel.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${novel.chapters.length} chapters • ${Uri.tryParse(novel.sourceUrl)?.host ?? novel.sourceUrl}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
            ),
            if (chapter != null) ...[
              const SizedBox(height: 12),
              Text(
                'Current chapter: ${chapter.title}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 9,
                  child: FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed: importer.activeChapterIndex > 0
                        ? onPreviousChapter
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text(
                      'Prev',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 12,
                  child: FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed: onOpenChapters,
                    icon: const Icon(Icons.menu_book),
                    label: const Text(
                      'Chapters',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed:
                        importer.activeChapterIndex < novel.chapters.length - 1
                        ? onNextChapter
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text(
                      'Next',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
  });

  final TtsService ttsService;
  final String? chapterLabel;
  final VoidCallback onOpenParagraphs;
  final VoidCallback onOpenPopup;

  @override
  Widget build(BuildContext context) {
    final chapterText = chapterLabel == null || chapterLabel!.trim().isEmpty
        ? 'Manual text'
        : chapterLabel!;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Now reading',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onOpenPopup,
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('View full'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paragraph ${ttsService.currentParagraphIndex + 1}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (chapterLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                chapterText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              ttsService.currentParagraph,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.45,
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (ttsService.paragraphCount > 0) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpenParagraphs,
                    icon: const Icon(Icons.format_list_numbered),
                    label: const Text('Play from paragraph'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
