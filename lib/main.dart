import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/audio_handler_controller.dart';
import 'services/file_import_service.dart';
import 'services/novel_import_controller.dart';
import 'services/novel_library_service.dart';
import 'services/reader_audio_handler.dart';
import 'services/storage_service.dart';
import 'services/theme_controller.dart';
import 'services/tts_service.dart';
import 'services/web_novel_import_service.dart';

const _playbackChannelId = 'com.dhebe.dhebevoice.playback.v5';
const _systemChannel = MethodChannel('com.dhebe.dhebevoice/system');
final _lightTheme = _buildTheme(brightness: Brightness.light);
final _darkTheme = _buildTheme(brightness: Brightness.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'Supertonic 3 model (OpenRAIL-M)': 'supertonic-model',
      'Supertonic inference reference (MIT)': 'supertonic-code',
      'ONNX Runtime (MIT)': 'onnxruntime',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/licenses/${entry.value}.txt'));
    }
  });

  final storageService = StorageService();
  await storageService.initialize();
  final novelLibraryService = NovelLibraryService();
  final webNovelImportService = WebNovelImportService();
  final fileImportService = FileImportService();
  final themeController = ThemeController(storageService: storageService);
  await themeController.initialize();
  final audioHandlerController = AudioHandlerController();

  final ttsService = TtsService(
    storageService: storageService,
    fileImportService: fileImportService,
  );
  final novelImportController = NovelImportController(
    storageService: storageService,
    fileImportService: fileImportService,
    novelLibraryService: novelLibraryService,
    webNovelImportService: webNovelImportService,
    ttsService: ttsService,
  );

  runApp(
    TextReaderApp(
      storageService: storageService,
      themeController: themeController,
      ttsService: ttsService,
      novelImportController: novelImportController,
      audioHandlerController: audioHandlerController,
    ),
  );

  unawaited(
    _initializeRuntimeServices(
      ttsService: ttsService,
      novelImportController: novelImportController,
      audioHandlerController: audioHandlerController,
    ),
  );
}

Future<void> _initializeRuntimeServices({
  required TtsService ttsService,
  required NovelImportController novelImportController,
  required AudioHandlerController audioHandlerController,
}) async {
  await WidgetsBinding.instance.endOfFrame;
  await Future.wait([
    ttsService.initialize(),
    novelImportController.initialize(),
    _initializeAudioHandler(
      ttsService: ttsService,
      novelImportController: novelImportController,
      audioHandlerController: audioHandlerController,
    ),
  ]);
}

Future<void> _initializeAudioHandler({
  required TtsService ttsService,
  required NovelImportController novelImportController,
  required AudioHandlerController audioHandlerController,
}) async {
  try {
    await _ensureAndroidPlaybackChannel();
    unawaited(_ensureAndroidNotificationPermission());
    final audioHandler = await AudioService.init(
      builder: () => ReaderAudioHandler(
        ttsService: ttsService,
        novelImportController: novelImportController,
      ),
      config: AudioServiceConfig(
        androidNotificationChannelId: _playbackChannelId,
        androidNotificationChannelName: 'DhebeVoice Playback',
        androidNotificationChannelDescription:
            'Playback controls for DhebeVoice reading sessions',
        androidNotificationIcon: 'drawable/dhebevoice_mark_monochrome',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );

    audioHandlerController.attach(audioHandler);
  } catch (error) {
    debugPrint('Audio service initialization failed: $error');
    audioHandlerController.reportError(
      'Playback controls could not start. Please close and reopen DhebeVoice.',
    );
  }
}

class TextReaderApp extends StatelessWidget {
  const TextReaderApp({
    super.key,
    required this.storageService,
    required this.themeController,
    required this.ttsService,
    required this.novelImportController,
    required this.audioHandlerController,
  });

  final StorageService storageService;
  final ThemeController themeController;
  final TtsService ttsService;
  final NovelImportController novelImportController;
  final AudioHandlerController audioHandlerController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<TtsService>.value(value: ttsService),
        ChangeNotifierProvider<NovelImportController>.value(
          value: novelImportController,
        ),
        ChangeNotifierProvider<AudioHandlerController>.value(
          value: audioHandlerController,
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: 'DhebeVoice',
            debugShowCheckedModeBanner: false,
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: controller.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final scaffoldColor = isDark
      ? const Color(0xFF071019)
      : const Color(0xFFEAF1F8);
  final cardColor = isDark ? const Color(0xFF182430) : Colors.white;
  final inputFillColor = isDark ? const Color(0xFF1C2936) : Colors.white;
  final seedScheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xFF5DB0FF),
  );
  final colorScheme = isDark
      ? seedScheme.copyWith(
          primary: const Color(0xFFA8CEFF),
          onPrimary: const Color(0xFF002B5F),
          primaryContainer: const Color(0xFF173E73),
          onPrimaryContainer: const Color(0xFFE0ECFF),
          secondary: const Color(0xFF8ED7E6),
          onSecondary: const Color(0xFF003640),
          surface: const Color(0xFF141B22),
          surfaceContainerLow: const Color(0xFF10202D),
          surfaceContainer: const Color(0xFF182A3A),
          surfaceContainerHigh: const Color(0xFF203446),
          surfaceContainerHighest: const Color(0xFF2A4055),
          onSurface: const Color(0xFFF2F6FC),
          onSurfaceVariant: const Color(0xFFC7D2E2),
          outline: const Color(0xFF8D9AAF),
          outlineVariant: const Color(0xFF3A4658),
          error: const Color(0xFFFFB4AB),
          onError: const Color(0xFF690005),
        )
      : seedScheme.copyWith(
          primary: const Color(0xFF0E61C9),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFDCEAFF),
          onPrimaryContainer: const Color(0xFF08264C),
          secondary: const Color(0xFF006B79),
          onSecondary: Colors.white,
          surface: Colors.white,
          surfaceContainerLow: const Color(0xFFF4F8FC),
          surfaceContainer: const Color(0xFFEDF3F9),
          surfaceContainerHigh: const Color(0xFFE5EEF7),
          surfaceContainerHighest: const Color(0xFFDCE7F2),
          onSurface: const Color(0xFF121A27),
          onSurfaceVariant: const Color(0xFF3A485B),
          outline: const Color(0xFF66768B),
          outlineVariant: const Color(0xFFD0D8E4),
          error: const Color(0xFFB3261E),
          onError: Colors.white,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldColor,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: colorScheme.primaryContainer,
      selectedColor: colorScheme.onPrimaryContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: isDark
          ? Colors.transparent
          : const Color(0xFF91A6C6).withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFillColor,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: isDark
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      modalBackgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerColor: colorScheme.outlineVariant,
    sliderTheme: const SliderThemeData(
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
  );
}

Future<void> _ensureAndroidPlaybackChannel() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _systemChannel
        .invokeMethod<void>('ensurePlaybackChannel', <String, dynamic>{
          'id': _playbackChannelId,
          'name': 'DhebeVoice Playback',
          'description': 'Playback controls for DhebeVoice reading sessions',
        });
  } on PlatformException {
    // The audio_service plugin can still create its own fallback channel.
  } on MissingPluginException {
    // Some platforms do not implement the app-specific notification channel.
  }
}

Future<void> _ensureAndroidNotificationPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _systemChannel.invokeMethod<bool>('ensureNotificationPermission');
  } on PlatformException {
    // Playback can still continue even if the permission prompt fails.
  } on MissingPluginException {
    // Notification permission is only requested on supported Android hosts.
  }
}
