import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/offline_voice_pack.dart';
import 'package:text_reader_app/models/speech_locale.dart';

void main() {
  test('all neural languages have readable names', () {
    for (final code in OfflineVoicePack.languages) {
      expect(SpeechLocale.label(code), isNot(code));
      expect(SpeechLocale.label(code), isNot(startsWith('Language (')));
    }
    expect(SpeechLocale.label('en'), 'English');
    expect(SpeechLocale.label('hi'), 'Hindi');
    expect(SpeechLocale.label('ar'), 'Arabic');
  });

  test(
    'locale names distinguish regions, scripts, and legacy Android codes',
    () {
      expect(SpeechLocale.label('en_IN'), 'English (India)');
      expect(SpeechLocale.label('en-US'), 'English (United States)');
      expect(SpeechLocale.label('pt-BR'), 'Portuguese (Brazil)');
      expect(SpeechLocale.label('zh-Hant-TW'), 'Chinese (Traditional, Taiwan)');
      expect(SpeechLocale.label('iw-IL'), 'Hebrew (Israel)');
      expect(SpeechLocale.label('in-ID'), 'Indonesian (Indonesia)');
      expect(SpeechLocale.label('en-IN-x-private'), 'English (India)');
    },
  );

  test('unknown locales are shown honestly rather than misidentified', () {
    expect(SpeechLocale.label(''), 'Unknown language');
    expect(SpeechLocale.label('zz-AB'), 'Language (zz-AB)');
    expect(SpeechLocale.label('en-XX'), 'English (XX)');
  });
}
