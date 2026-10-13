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
