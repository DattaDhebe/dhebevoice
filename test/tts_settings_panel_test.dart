import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/voice_model.dart';
import 'package:text_reader_app/widgets/tts_settings_panel.dart';

void main() {
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
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TtsSettingsPanel(
            languages: const ['en-IN'],
            selectedLanguage: 'en-IN',
            selectedVoice: offline,
            voices: voices,
            rate: .48,
            pitch: 1,
            volume: 1,
            showOnlineVoices: showOnlineVoices,
            onLanguageChanged: (_) {},
            onVoiceSelected: onSelected ?? (_) {},
            onRateChanged: (_) {},
            onPitchChanged: (_) {},
            onVolumeChanged: (_) {},
          ),
        ),
      ),
    ),
  );

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
    expect(find.text('Local narrator'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Offline'), findsNothing);
    await tester.tap(find.text('French narrator'));
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
      expect(find.text('Local narrator'), findsNothing);
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
      await tester.tap(find.text('Network narrator'));
      await tester.pumpAndSettle();
      expect(find.text('Use an online Android voice?'), findsOneWidget);
      expect(selection, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selection, isNull);
      await tester.tap(find.text('Choose installed voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network narrator'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use online voice'));
      await tester.pumpAndSettle();
      expect(selection, online);
      expect(tester.takeException(), isNull);
    },
  );
}
