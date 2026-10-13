import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/voice_model.dart';

void main() {
  test('Android quality labels and network flags are parsed', () {
    final voice = VoiceModel.fromMap({
      'name': 'en-in-x-ene-network',
      'locale': 'en-IN',
      'quality': 'very high',
      'network_required': '1',
    });
    expect(voice.qualityScore, 500);
    expect(voice.requiresNetwork, isTrue);
    expect(
      voice.metadataLabels,
      containsAll(['High quality', 'Requires internet']),
    );
    expect(voice.personaLabel, isNull);
  });

  test('numeric quality and unavailable voice data are supported', () {
    final voice = VoiceModel.fromMap({
      'name': 'voice',
      'locale': 'en-US',
      'quality': 300,
      'network_required': false,
      'features': 'notInstalled',
    });
    expect(voice.qualityScore, 300);
    expect(voice.requiresNetwork, isFalse);
    expect(voice.isInstalled, isFalse);
  });

  test('missing connectivity information is not called offline', () {
    final voice = VoiceModel.fromMap({'name': 'voice', 'locale': 'en-IN'});
    expect(voice.requiresNetwork, isNull);
    expect(voice.metadataLabels, isNot(contains('Offline')));
  });
}
