import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:text_reader_app/main.dart';
import 'package:text_reader_app/models/novel_book.dart';
import 'package:text_reader_app/services/audio_handler_controller.dart';
import 'package:text_reader_app/services/file_import_service.dart';
import 'package:text_reader_app/services/novel_import_controller.dart';
import 'package:text_reader_app/services/novel_library_service.dart';
import 'package:text_reader_app/services/reader_audio_handler.dart';
import 'package:text_reader_app/services/storage_service.dart';
import 'package:text_reader_app/services/theme_controller.dart';
import 'package:text_reader_app/services/tts_service.dart';
import 'package:text_reader_app/services/web_novel_import_service.dart';
import 'package:text_reader_app/widgets/reader_consumer.dart';
import 'package:text_reader_app/widgets/reader_list_sheet.dart';
import 'package:text_reader_app/widgets/reader_view_dialog.dart';
import 'package:text_reader_app/widgets/bookmark_sheet.dart';

class _MemoryLibrary extends NovelLibraryService {
  List<NovelBook> books = [
    NovelBook(
      id: 'story',
      title: 'The Lantern Keeper',
      sourceUrl: 'sample://lantern',
      importedAt: DateTime(2026),
      chapters: [
        for (var i = 0; i < 100; i++)
          NovelChapter(
            title: 'Chapter ${101 + i} - A light across the quiet harbor',
            url: 'sample://lantern/chapter-${101 + i}',
            order: i,
            content: List.generate(
              12,
              (p) =>
                  'Lantern-${(p + 1).toString().padLeft(2, '0')}. The keeper watched the boats return across the harbor. Each light carried a story, and each story found its way home.',
            ).join('\n\n'),
          ),
      ],
    ),
    NovelBook(
      id: 'notes',
      title: 'Evening notes',
      sourceUrl: 'local-pdf://notes',
      importedAt: DateTime(2026),
      chapters: const [
        NovelChapter(
          title: 'A quiet evening',
          url: 'notes:1',
          content: 'A quiet evening.',
          order: 0,
        ),
      ],
    ),
  ];

  @override
  Future<List<NovelBook>> loadLibrary() async => books;
  @override
  Future<void> saveLibrary(List<NovelBook> value) async => books = value;
}

class _Harness {
  _Harness(this.tts, this.importer, this.theme, this.engine, this.key);
  final TtsService tts;
  final NovelImportController importer;
  final ThemeController theme;
  final FlutterTts engine;
  final GlobalKey key;

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['DHEBEVOICE_CAPTURE_UI'] != '1') return;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/ui-check/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}

Future<void> _withReader(
  WidgetTester tester,
  Future<void> Function(_Harness harness) body, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool openBook = true,
  bool attachAudio = true,
  String? sharedUrl,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  late FlutterTts engine;
  SharedPreferences.setMockInitialValues({'reader_home_guide_seen': true});
  ReceiveSharingIntent.setMockValues(
    initialMedia: sharedUrl == null
        ? []
        : [SharedMediaFile(path: sharedUrl, type: SharedMediaType.url)],
    mediaStream: const Stream.empty(),
  );
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
    call,
  ) async {
    if (call.method == 'speak') {
      Future.microtask(() => engine.startHandler?.call());
    }
    return call.method == 'getVoices'
        ? [
            {'name': 'en-in-x-ene-local', 'locale': 'en-IN'},
          ]
        : 1;
  });
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.ryanheise.audio_session'),
    (_) async => null,
  );
  final storage = StorageService();
  await storage.initialize();
  final theme = ThemeController(storageService: storage);
  await theme.initialize();
  engine = FlutterTts();
  final tts = TtsService(
    storageService: storage,
    fileImportService: FileImportService(),
    flutterTts: engine,
  );
  final importer = NovelImportController(
    storageService: storage,
    fileImportService: FileImportService(),
    novelLibraryService: _MemoryLibrary(),
    webNovelImportService: WebNovelImportService(),
    ttsService: tts,
  );
  final audio = AudioHandlerController();
  final key = GlobalKey();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  try {
    await tts.initialize();
    await importer.initialize();
    if (openBook) await importer.selectNovel('story', chapterIndex: 63);
    if (attachAudio) {
      audio.attach(
        ReaderAudioHandler(ttsService: tts, novelImportController: importer),
      );
    } else {
      audio.reportError('Background playback controls could not start.');
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: TextReaderApp(
          storageService: storage,
          themeController: theme,
          ttsService: tts,
          novelImportController: importer,
          audioHandlerController: audio,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await body(_Harness(tts, importer, theme, engine, key));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    tts.dispose();
    importer.dispose();
    theme.dispose();
    audio.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    debugDefaultTargetPlatformOverride = null;
    await tester.pump();
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  for (
    var step = 0;
    step < 30 && finder.hitTestable().evaluate().isEmpty;
    step++
  ) {
    scrollable.position.jumpTo(
      (scrollable.position.pixels + 180).clamp(
        0.0,
        scrollable.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    final directory = Platform.environment['DHEBEVOICE_UI_FONT_DIR'];
    if (directory == null) return;
    for (final family in ['Roboto', 'Segoe UI']) {
      final loader = FontLoader(family);
      for (final name in [
        'roboto-regular.ttf',
        'roboto-medium.ttf',
        'roboto-bold.ttf',
      ]) {
        loader.addFont(
          File(
            '$directory/$name',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$directory/materialicons-regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        ))
        .load();
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(900, 1200),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('reader and full views fit $size at ${scale}x text', (
        tester,
      ) async {
        await _withReader(
          tester,
          (h) async {
            expect(tester.takeException(), isNull);
            if (size.width == 390 && scale == 1) {
              await h.capture(tester, 'reader-light');
            }
            await _scrollTo(
              tester,
              find.byKey(const ValueKey('content-full-view')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('content-full-view')));
            await tester.pumpAndSettle();
            expect(find.byType(ReaderViewDialog), findsOneWidget);
            expect(find.text('Pause').hitTestable(), findsOneWidget);
            expect(find.text('Stop').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (size.width == 390 && scale == 1) {
              await h.capture(tester, 'full-reading-light');
            }
            await tester.tap(find.byTooltip('Close'));
            await tester.pumpAndSettle();
            await _scrollTo(
              tester,
              find.byKey(const ValueKey('now-reading-full-view')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('now-reading-full-view')),
            );
            await tester.pumpAndSettle();
            final before = tester.getSize(find.byType(Dialog));
            await tester.tap(find.byTooltip('Play next paragraph'));
            await tester.pumpAndSettle();
            expect(h.tts.currentParagraphIndex, 1);
            expect(tester.getSize(find.byType(Dialog)), before);
            expect(tester.takeException(), isNull);
            if (size.width == 390 && scale == 1) {
              await h.capture(tester, 'now-reading-light');
            }
          },
          size: size,
          textScale: scale,
        );
      });
    }
  }

  testWidgets(
    'home paragraph shortcuts keep the player pinned and open voice settings',
    (tester) async {
      await _withReader(tester, (h) async {
        final player = find.byKey(const ValueKey('home-playback-controls'));
        final before = tester.getRect(player);
        await _scrollTo(tester, find.byTooltip('Next paragraph'));
        expect(tester.getRect(player), before);
        await h.capture(tester, 'home-listening-light');
        await tester.tap(find.byTooltip('Next paragraph'));
        await tester.pumpAndSettle();
        expect(h.tts.currentParagraphIndex, 1);
        expect(h.tts.isPlaying, isTrue);
        await tester.tap(find.byTooltip('Previous paragraph'));
        await tester.pumpAndSettle();
        expect(h.tts.currentParagraphIndex, 0);
        await tester.tap(find.byTooltip('Pause'));
        await tester.pumpAndSettle();
        expect(h.tts.isPaused, isTrue);
        await _scrollTo(tester, find.byTooltip('Voice & playback settings'));
        await tester.tap(find.byTooltip('Voice & playback settings'));
        await tester.pumpAndSettle();
        expect(find.text('Voice & playback'), findsOneWidget);
        expect(h.tts.isPaused, isTrue);
        expect(tester.takeException(), isNull);
      });
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'Now reading keeps passage contrast and neutral chapter title in $mode',
      (tester) async {
        await _withReader(tester, (h) async {
          await h.theme.setThemeMode(mode);
          await tester.pumpAndSettle();
          final card = find.byKey(const ValueKey('now-reading-card'));
          await _scrollTo(tester, card);
          final surface = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('now-reading-surface')),
          );
          final gradient = (surface.decoration as BoxDecoration).gradient!;
          final colors = Theme.of(tester.element(card)).colorScheme;
          final passage = tester.widget<Text>(
            find.descendant(
              of: card,
              matching: find.text(h.tts.currentParagraph),
            ),
          );
          expect(passage.style?.color, colors.primary);
          final foreground = colors.primary.computeLuminance();
          for (final backgroundColor in gradient.colors) {
            final background = backgroundColor.computeLuminance();
            final ratio = foreground > background
                ? (foreground + .05) / (background + .05)
                : (background + .05) / (foreground + .05);
            expect(ratio, greaterThanOrEqualTo(4.5));
          }
          final chapter = tester.widget<Text>(
            find.descendant(
              of: card,
              matching: find.text(h.importer.activeChapter!.title),
            ),
          );
          expect(chapter.style?.color, colors.onSurface);
          await h.capture(
            tester,
            'home-listening-${mode == ThemeMode.dark ? 'dark' : 'light'}',
          );
        });
      },
    );

    testWidgets(
      'empty home explains imports without showing an empty reading card in $mode',
      (tester) async {
        await _withReader(tester, (h) async {
          await h.theme.setThemeMode(mode);
          await tester.pumpAndSettle();
          expect(find.text('What would you like to hear?'), findsOneWidget);
          expect(find.text('Import file').hitTestable(), findsOneWidget);
          expect(find.text('Web link').hitTestable(), findsOneWidget);
          expect(find.byKey(const ValueKey('now-reading-card')), findsNothing);
          final play = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Play'),
          );
          expect(play.onPressed, isNull);
          expect(tester.takeException(), isNull);
          await h.capture(
            tester,
            'home-empty-${mode == ThemeMode.dark ? 'dark' : 'light'}',
          );
        }, openBook: false);
      },
    );

    for (final size in [const Size(320, 568), const Size(640, 360)]) {
      testWidgets(
        'home editor and player fit $size with keyboard and large text in $mode',
        (tester) async {
          await _withReader(
            tester,
            (h) async {
              await h.theme.setThemeMode(mode);
              await tester.pumpAndSettle();
              final editor = find.byKey(const ValueKey('reading-editor'));
              await _scrollTo(tester, editor);
              await tester.enterText(
                editor,
                'First paragraph.\n\nSecond paragraph.',
              );
              tester.view.viewInsets = const FakeViewPadding(bottom: 180);
              await tester.pumpAndSettle();
              expect(h.tts.text, 'First paragraph.\n\nSecond paragraph.');
              final editable = tester.state<EditableTextState>(
                find.byType(EditableText),
              );
              expect(editable.widget.focusNode.hasFocus, isTrue);
              expect(
                find.byKey(const ValueKey('now-reading-card')),
                findsNothing,
              );
              expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
              await tester.tap(find.byTooltip('Play'));
              await tester.pumpAndSettle();
              expect(h.tts.isPlaying, isTrue);
              await tester.tap(find.byTooltip('Pause'));
              await tester.pumpAndSettle();
              expect(h.tts.isPaused, isTrue);
              await tester.tap(find.byTooltip('Stop'));
              await tester.pumpAndSettle();
              expect(h.tts.isPlaying, isFalse);
              expect(tester.takeException(), isNull);
            },
            size: size,
            textScale: 2,
            openBook: false,
          );
        },
      );
    }
  }

  testWidgets('Book List search and safe deletion stay in the library', (
    tester,
  ) async {
    await _withReader(tester, (h) async {
      await tester.tap(find.byTooltip('Library'));
      await tester.pumpAndSettle();
      await h.capture(tester, 'book-list-light');
      await tester.enterText(find.byType(TextField).last, 'evening');
      await tester.pumpAndSettle();
      expect(find.text('Evening notes'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete Evening notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.importer.library.length, 2);
      await tester.tap(find.byTooltip('Delete Evening notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(h.importer.library.length, 1);
      expect(find.text('Book List'), findsOneWidget);
      expect(find.text('No matching results.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'bookmarks save without stopping, support notes, search and return to the passage',
    (tester) async {
      await _withReader(tester, (h) async {
        await h.tts.playFromParagraph(4);
        await h.importer.saveCurrentBookmark();
        final session = h.tts.playbackSessionId;
        await _scrollTo(tester, find.text('Bookmarks'));
        await tester.tap(find.text('Bookmarks'));
        await tester.pumpAndSettle();
        expect(find.byType(BookmarkSheet), findsOneWidget);
        await tester.tap(find.byTooltip('Bookmark actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit note'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'The lighthouse clue',
        );
        await tester.tap(find.text('Save note'));
        await tester.pumpAndSettle();
        expect(h.tts.isPlaying, isTrue);
        expect(h.tts.playbackSessionId, session);
        expect(find.text('The lighthouse clue'), findsOneWidget);
        await h.capture(tester, 'audit-bookmarks-notes');
        await tester.enterText(find.byType(TextField).last, 'lighthouse');
        await tester.pumpAndSettle();
        expect(find.text('The lighthouse clue'), findsOneWidget);
        await h.tts.pause();
        await tester.tap(find.text('The lighthouse clue'));
        await tester.pumpAndSettle();
        expect(h.tts.currentParagraphIndex, 4);
        expect(h.tts.isPlaying, isFalse);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'library sorting persists and search still filters sorted books',
    (tester) async {
      await _withReader(tester, (h) async {
        await tester.tap(find.byTooltip('Library'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Sort books'));
        await tester.pumpAndSettle();
        await h.capture(tester, 'audit-book-sort-menu');
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is CheckedPopupMenuItem<String> &&
                widget.value == 'title',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Provider.of<StorageService>(
            tester.element(find.text('Book List')),
            listen: false,
          ).librarySort,
          'title',
        );
        await h.capture(tester, 'audit-book-list-sorted');
        final sheet = find.byType(ReaderListSheet<NovelBook>);
        Finder bookTitle(String title) =>
            find.descendant(of: sheet, matching: find.text(title));
        expect(
          tester.getTopLeft(bookTitle('Evening notes')).dy,
          lessThan(tester.getTopLeft(bookTitle('The Lantern Keeper')).dy),
        );
        await tester.enterText(find.byType(TextField).last, 'lantern');
        await tester.pumpAndSettle();
        expect(bookTitle('The Lantern Keeper'), findsOneWidget);
        expect(bookTitle('Evening notes'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('bookmark notes fit narrow screens and large text in $mode', (
      tester,
    ) async {
      await _withReader(
        tester,
        (h) async {
          await h.theme.setThemeMode(mode);
          await h.importer.saveCurrentBookmark(
            note: 'A saved passage to revisit',
          );
          await tester.pumpAndSettle();
          await _scrollTo(tester, find.text('Bookmarks'));
          await tester.tap(find.text('Bookmarks'));
          await tester.pumpAndSettle();
          await h.capture(
            tester,
            'audit-bookmarks-${mode == ThemeMode.dark ? 'dark' : 'light'}-large',
          );
          await tester.enterText(find.byType(TextField).last, 'saved passage');
          tester.view.viewInsets = const FakeViewPadding(bottom: 180);
          await tester.pumpAndSettle();
          expect(find.text('A saved passage to revisit'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        size: const Size(320, 568),
        textScale: 2,
      );
    });
  }

  testWidgets(
    'a list opened before loading centers its selection when data arrives',
    (tester) async {
      final items = ValueNotifier<List<int>>([]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<List<int>>(
              valueListenable: items,
              builder: (_, value, _) => ReaderListSheet<int>(
                title: 'Loading list',
                items: value,
                selectedIndex: 80,
                searchText: (item, _) => '$item',
                itemBuilder: (_, item, _) =>
                    ListTile(title: Text('Entry $item')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      items.value = List.generate(100, (index) => index);
      await tester.pumpAndSettle();
      expect(find.text('Entry 80').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      items.dispose();
    },
  );

  testWidgets(
    'chapter picker centers current chapter and searches actual numbers',
    (tester) async {
      await _withReader(tester, (h) async {
        await tester.tap(find.text('Chapters'));
        await tester.pumpAndSettle();
        final sheet = find.byType(ReaderListSheet<NovelChapter>);
        final current = find.descendant(
          of: sheet,
          matching: find.text('Chapter 164 - A light across the quiet harbor'),
        );
        expect(current.hitTestable(), findsOneWidget);
        await h.capture(tester, 'chapters-light');
        await tester.enterText(find.byType(TextField).last, '158');
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Chapter 158 - A light across the quiet harbor'),
        );
        await tester.pumpAndSettle();
        expect(h.importer.activeChapterIndex, 57);
        expect(h.tts.isPlaying, isFalse);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('paragraph search starts playback from the original paragraph', (
    tester,
  ) async {
    await _withReader(tester, (h) async {
      await _scrollTo(tester, find.byKey(const ValueKey('paragraph-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paragraph-picker')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Lantern-08');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paragraph 8'));
      await tester.pumpAndSettle();
      expect(h.tts.currentParagraphIndex, 7);
      expect(h.tts.isPlaying, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'web link validates before importing and sleep timer can be cancelled',
    (tester) async {
      await _withReader(tester, (h) async {
        await tester.tap(find.byTooltip('Import web link'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'not a url');
        await tester.tap(find.text('Start import'));
        await tester.pumpAndSettle();
        expect(h.importer.isImporting, isFalse);
        expect(
          find.text('Enter a complete http or https web link.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sleep timer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('15 minutes'));
        await tester.pumpAndSettle();
        expect(h.tts.sleepTimerEndsAt, isNotNull);
        await tester.tap(find.byIcon(Icons.bedtime));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Turn off timer'));
        await tester.pumpAndSettle();
        expect(h.tts.sleepTimerEndsAt, isNull);
        expect(tester.takeException(), isNull);
      }, openBook: false);
    },
  );

  testWidgets('search sheets fit narrow screens with large text and keyboard', (
    tester,
  ) async {
    await _withReader(
      tester,
      (h) async {
        await tester.tap(find.byTooltip('Library'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.enterText(find.byType(TextField).last, 'missing book');
        await tester.pumpAndSettle();
        expect(find.text('No matching results.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await _scrollTo(tester, find.text('Chapters'));
        await tester.tap(find.text('Chapters'));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderListSheet<NovelChapter>), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(320, 568),
      textScale: 2,
    );
  });

  testWidgets(
    'shared links open for review without automatically starting import',
    (tester) async {
      await _withReader(tester, (h) async {
        expect(find.text('Import web link'), findsOneWidget);
        expect(find.text('Start import'), findsOneWidget);
        expect(h.importer.hasPendingSharedUrl, isTrue);
        expect(h.importer.isImporting, isFalse);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.importer.isImporting, isFalse);
      }, sharedUrl: 'https://example.com/my-page');
    },
  );

  testWidgets(
    'clipboard replacement requires confirmation and preserves book progress',
    (tester) async {
      await _withReader(tester, (h) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? {'text': 'New text from the clipboard.'}
              : null,
        );
        try {
          await h.tts.playFromParagraph(4);
          await h.tts.pause();
          final position = h.tts.currentCharIndex;
          final text = h.tts.text;
          await _scrollTo(tester, find.text('Paste text'));
          await tester.tap(find.text('Paste text'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(h.tts.text, text);
          await tester.tap(find.text('Paste text'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Replace'));
          await tester.pumpAndSettle();
          expect(h.tts.text, 'New text from the clipboard.');
          expect(h.importer.activeNovel, isNull);
          await h.importer.selectNovel('story', chapterIndex: 63);
          expect(h.tts.currentCharIndex, position);
        } finally {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        }
      });
    },
  );

  testWidgets(
    'foreground reading is available if media controls cannot initialize',
    (tester) async {
      await _withReader(tester, (h) async {
        expect(
          find.text('Background playback controls could not start.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();
        expect(h.tts.isPlaying, isTrue);
      }, attachAudio: false);
    },
  );

  testWidgets('settings and dark theme remain usable with the same controls', (
    tester,
  ) async {
    await _withReader(tester, (h) async {
      await h.theme.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      await h.capture(tester, 'reader-dark');
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Voice & playback'), findsOneWidget);
      await h.capture(tester, 'settings-dark');
      await _scrollTo(tester, find.text('Appearance'));
      expect(find.text('Dark'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'reader and settings consumers ignore unrelated speech notifications',
    (tester) async {
      await _withReader(tester, (h) async {
        var readerBuilds = 0;
        var settingsBuilds = 0;
        await tester.pumpWidget(
          ChangeNotifierProvider<TtsService>.value(
            value: h.tts,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  ReaderConsumer(
                    builder: (_, _) {
                      readerBuilds++;
                      return const Text('Reader');
                    },
                  ),
                  TtsSettingsConsumer(
                    builder: (_, _) {
                      settingsBuilds++;
                      return const Text('Settings');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        h.tts.notifyListeners();
        await tester.pump();
        expect(readerBuilds, 1);
        expect(settingsBuilds, 1);
        await h.tts.setSpeechRate(0.6);
        await tester.pump();
        expect(readerBuilds, 1);
        expect(settingsBuilds, 2);
      });
    },
  );
}
