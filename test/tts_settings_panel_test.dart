import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/voice_model.dart';
import 'package:text_reader_app/models/voice_names.dart';
import 'package:text_reader_app/widgets/tts_settings_panel.dart';
import 'package:text_reader_app/widgets/voice_picker_sheet.dart';
import 'package:text_reader_app/widgets/voice_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontDirectory = Platform.environment['DHEBEVOICE_TEST_FONTS'];
    if (fontDirectory == null) return;
    for (final entry in const {
      'Roboto': ['roboto-regular.ttf', 'roboto-bold.ttf'],
      'MaterialIcons': ['materialicons-regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final filename in entry.value) {
        loader.addFont(
          File(
            '$fontDirectory/$filename',
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  });
  const offline = VoiceModel(
    name: 'local',
    locale: 'en-IN',
    label: 'Local narrator',
    requiresNetwork: false,
  );
  const online = VoiceModel(
    name: 'network',
    locale: 'en-IN',
    label: 'Network narrator',
    requiresNetwork: true,
  );

  Future<void> openPanel(
    WidgetTester tester,
    List<VoiceModel> voices, {
    bool showOnlineVoices = true,
    ValueChanged<VoiceModel?>? onSelected,
    List<String> languages = const ['en-IN'],
    String selectedLanguage = 'en-IN',
    VoiceModel? currentVoice = offline,
    ValueChanged<String?>? onLanguageChanged,
    double textScale = 1,
    Brightness brightness = Brightness.light,
    Key? captureKey,
    Future<void> Function(VoiceModel voice, String? type)? onVoiceTypeChanged,
  }) => tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0E61C9),
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TtsSettingsPanel(
              languages: languages,
              selectedLanguage: selectedLanguage,
              selectedVoice: currentVoice,
              voices: voices,
              rate: .48,
              pitch: 1,
              volume: 1,
              showOnlineVoices: showOnlineVoices,
              onVoiceTypeChanged: onVoiceTypeChanged,
              onLanguageChanged: onLanguageChanged ?? (_) {},
              onVoiceSelected: onSelected ?? (_) {},
              onRateChanged: (_) {},
              onPitchChanged: (_) {},
              onVolumeChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'language menu displays full names but returns the original code',
    (tester) async {
      String? language;
      await openPanel(
        tester,
        const [offline],
        languages: ['en', 'en-IN', 'hi', 'pt-BR'],
        selectedLanguage: 'en',
        onLanguageChanged: (value) => language = value,
      );
      expect(find.text('English'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.text('Portuguese (Brazil)'), findsOneWidget);
      await tester.tap(find.text('Hindi'));
      await tester.pumpAndSettle();
      expect(language, 'hi');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Android voice types are visible, user labeled, and reversible', (
    tester,
  ) async {
    final saved = <(String, String?)>[];
    await openPanel(
      tester,
      const [offline],
      onVoiceTypeChanged: (voice, type) async {
        saved.add((voice.name, type));
      },
    );
    await tester.tap(find.text('Local narrator'));
    await tester.pumpAndSettle();
    expect(find.text('Gender not provided'), findsOneWidget);
    await tester.tap(find.byTooltip('Label selected voice type'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Male'));
    await tester.pumpAndSettle();
    expect(saved, [('local', 'Male')]);
    expect(find.text('Male'), findsOneWidget);
    expect(find.text('Your label'), findsOneWidget);
    expect(find.byIcon(Icons.face_6_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Label selected voice type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use provider label'));
    await tester.pumpAndSettle();
    expect(saved.last, ('local', null));
    expect(find.text('Gender not provided'), findsOneWidget);
    expect(find.text('Your label'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'voice cannot be applied with stale metadata while saving a label',
    (tester) async {
      final saving = Completer<void>();
      await openPanel(tester, const [
        offline,
      ], onVoiceTypeChanged: (_, _) => saving.future);
      await tester.tap(find.text('Local narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Label selected voice type'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Female'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use voice'),
            )
            .onPressed,
        isNull,
      );
      saving.complete();
      await tester.pumpAndSettle();
      expect(find.text('Female'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use voice'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('voice labeling fits small screens at 2x in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openPanel(
        tester,
        const [offline],
        brightness: brightness,
        textScale: 2,
        onVoiceTypeChanged: (_, _) async {},
      );
      await tester.tap(find.text('Local narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Label selected voice type'));
      await tester.pumpAndSettle();
      final choice = find.widgetWithText(SimpleDialogOption, 'Child');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed personal label save leaves voice metadata unchanged', (
    tester,
  ) async {
    await openPanel(
      tester,
      const [offline],
      onVoiceTypeChanged: (_, _) async {
        throw StateError('Storage failure');
      },
    );
    await tester.tap(find.text('Local narrator'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Label selected voice type'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'Female'));
    await tester.pumpAndSettle();
    expect(find.text('Gender not provided'), findsOneWidget);
    expect(
      find.text('Could not save the voice type. Try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'voice cards stage selection until Use voice and Cancel discards it',
    (tester) async {
      VoiceModel? selected;
      await openPanel(tester, const [
        offline,
        online,
      ], onSelected: (voice) => selected = voice);
      await tester.tap(find.text('Local narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network narrator'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('Local narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use voice'));
      await tester.pumpAndSettle();
      expect(selected, offline);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'voice search recognizes full language names and safely closes while focused',
    (tester) async {
      const hindi = VoiceModel(
        name: 'hi-voice',
        locale: 'hi-IN',
        label: 'Hindi narrator',
      );
      await openPanel(tester, const [offline, hindi, online]);
      await tester.tap(find.text('Online Android voices (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close voice picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local narrator'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(VoicePickerSheet),
          matching: find.byType(TextField),
        ),
        'English India',
      );
      await tester.pumpAndSettle();
      expect(find.text('No installed voices match that search.'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byType(VoicePickerSheet),
          matching: find.byType(TextField),
        ),
        'English',
      );
      await tester.pumpAndSettle();
      expect(find.text('Network narrator'), findsOneWidget);
      expect(find.text('Hindi narrator'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byType(VoicePickerSheet),
          matching: find.byType(TextField),
        ),
        'Hindi',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Hindi narrator'),
        findsNothing,
      ); // The main picker is scoped to English India.
      expect(
        find.text('No installed voices match that search.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use voice'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Close voice picker'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  final neural = [
    for (final gender in ['Female', 'Male'])
      for (var i = 1; i <= 5; i++)
        VoiceModel(
          name: '${gender == 'Female' ? 'F' : 'M'}$i',
          locale: 'en',
          label: VoiceNames.supertonic('${gender == 'Female' ? 'F' : 'M'}$i'),
          personaLabel: gender,
          metadataLabels: ['Offline', 'Neural'],
          requiresNetwork: false,
        ),
  ];

  testWidgets(
    'avatar cards expose selection and Male search excludes Female voices',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        VoiceModel? selected;
        await openPanel(
          tester,
          neural,
          languages: ['en'],
          selectedLanguage: 'en',
          currentVoice: null,
          showOnlineVoices: false,
          onSelected: (value) => selected = value,
        );
        await tester.tap(find.text('Choose installed voice'));
        await tester.pumpAndSettle();
        final female = find.byKey(const ValueKey('voice_en_F2'));
        await tester.tap(female);
        await tester.pumpAndSettle();
        final node = tester.getSemantics(female).getSemanticsData();
        expect(node.flagsCollection.isSelected, ui.Tristate.isTrue);
        expect(node.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(find.widgetWithText(ChoiceChip, 'Online'), findsNothing);
        await tester.enterText(
          find.descendant(
            of: find.byType(VoicePickerSheet),
            matching: find.byType(TextField),
          ),
          'Male',
        );
        await tester.pumpAndSettle();
        expect(find.text('Asha'), findsNothing);
        expect(find.text('Arun'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use voice'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('voice_en_M1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('voice_en_M1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use voice'));
        await tester.pumpAndSettle();
        expect(selected?.name, 'M1');
        expect(selected?.locale, 'en');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('uninstalled voices cannot be selected or applied', (
    tester,
  ) async {
    const missing = VoiceModel(
      name: 'missing',
      locale: 'en-IN',
      label: 'Missing voice',
      isInstalled: false,
    );
    await openPanel(tester, const [offline, missing], currentVoice: missing);
    await tester.tap(find.text('Missing voice'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(VoicePickerSheet),
        matching: find.text('Missing voice'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use voice'))
          .onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: find.byType(VoicePickerSheet),
        matching: find.byIcon(Icons.record_voice_over_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close voice picker'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('avatar picker fits $brightness at ${scale}x with keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = Size(
          scale == 1 ? 390 : 320,
          scale == 1 ? 844 : 568,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final captureKey = GlobalKey();
        await openPanel(
          tester,
          neural,
          languages: ['en', 'hi'],
          selectedLanguage: 'en',
          currentVoice: null,
          showOnlineVoices: false,
          brightness: brightness,
          textScale: scale,
          captureKey: captureKey,
        );
        await tester.tap(find.text('Choose installed voice'));
        await tester.pumpAndSettle();
        expect(find.byType(VoiceAvatar), findsWidgets);
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('voice_en_F1'))).dy,
            tester.getTopLeft(find.byKey(const ValueKey('voice_en_F2'))).dy,
          );
          await tester.tap(find.byKey(const ValueKey('voice_en_F2')));
          await tester.pumpAndSettle();
          if (Platform.environment['DHEBEVOICE_CAPTURE_VOICES'] == '1') {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'build/ui-check/voices-${brightness.name}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(png!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        }
        final search = find.descendant(
          of: find.byType(VoicePickerSheet),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.enterText(search, 'Male');
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Close voice picker'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('online shortcut finds other languages and still asks consent', (
    tester,
  ) async {
    const otherLanguage = VoiceModel(
      name: 'online-fr',
      locale: 'fr-FR',
      label: 'French narrator',
      requiresNetwork: true,
    );
    VoiceModel? selected;
    await openPanel(tester, const [
      offline,
      online,
      otherLanguage,
    ], onSelected: (voice) => selected = voice);
    await tester.tap(find.text('Online Android voices (2)'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(VoicePickerSheet),
        matching: find.text('Local narrator'),
      ),
      findsNothing,
    );
    expect(find.widgetWithText(ChoiceChip, 'Offline'), findsNothing);
    await tester.tap(find.text('French narrator'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Use voice'));
    await tester.pumpAndSettle();
    expect(find.text('Use an online Android voice?'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.text('Use online voice'));
    await tester.pumpAndSettle();
    expect(selected, otherLanguage);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no online voices gives setup guidance rather than inventing one',
    (tester) async {
      await openPanel(tester, const [offline]);
      await tester.tap(find.text('Online Android voices (0)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No online voices are exposed'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(VoicePickerSheet),
          matching: find.text('Local narrator'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('neural voice settings do not advertise Android online voices', (
    tester,
  ) async {
    await openPanel(tester, const [offline], showOnlineVoices: false);
    expect(find.textContaining('Online Android voices ('), findsNothing);
  });

  testWidgets(
    'voice picker filters connectivity and confirms online selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VoiceModel? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TtsSettingsPanel(
                languages: const ['en-IN'],
                selectedLanguage: 'en-IN',
                selectedVoice: null,
                voices: const [offline, online],
                rate: .48,
                pitch: 1,
                volume: 1,
                onLanguageChanged: (_) {},
                onVoiceSelected: (voice) => selection = voice,
                onRateChanged: (_) {},
                onPitchChanged: (_) {},
                onVolumeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose installed voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Online'));
      await tester.pumpAndSettle();
      expect(find.text('Local narrator'), findsNothing);
      expect(find.text('Network narrator'), findsOneWidget);
      await tester.ensureVisible(find.text('Network narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network narrator'));
      await tester.pumpAndSettle();
      expect(selection, isNull);
      await tester.tap(find.text('Use voice'));
      await tester.pumpAndSettle();
      expect(find.text('Use an online Android voice?'), findsOneWidget);
      expect(selection, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selection, isNull);
      await tester.tap(find.text('Choose installed voice'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Network narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use online voice'));
      await tester.pumpAndSettle();
      expect(selection, online);
      expect(tester.takeException(), isNull);
    },
  );
}
