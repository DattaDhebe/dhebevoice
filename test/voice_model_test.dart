import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/voice_model.dart';

void main() {
  test(
    'missing gender is displayed honestly, not guessed from an alias or code',
    () {
      final voice = VoiceModel.fromMap({
        'name': 'en-in-x-ene-local',
        'locale': 'en-IN',
      });
      expect(voice.personaLabel, isNull);
      expect(voice.personaDisplayLabel, 'Gender not provided');
      expect(voice.detailsLabel, contains('Gender not provided'));
    },
  );

  test('explicit engine gender fields and features are recognized', () {
    expect(
      VoiceModel.fromMap({
        'name': 'voice',
        'gender': '',
        'sex': 'F',
      }).personaLabel,
      'Female',
    );
    expect(
      VoiceModel.fromMap({'name': 'voice', 'voiceGender': 'male'}).personaLabel,
      'Male',
    );
    expect(
      VoiceModel.fromMap({
        'name': 'voice',
        'features': ['gender=FEMALE'],
      }).personaLabel,
      'Female',
    );
    expect(
      VoiceModel.fromMap({
        'name': 'voice',
        'features': '[network_required, voice-m1]',
      }).personaLabel,
      isNull,
    );
  });

  test(
    'personal voice types are separate, reversible, and do not change TTS identity',
    () {
      final original = VoiceModel.fromMap({
        'name': 'en-female-1',
        'locale': 'en-US',
        'gender': 'F',
        'network_required': true,
        'quality': 400,
      });
      final labeled = original.withUserPersonaLabel('Male');
      expect(labeled.personaLabel, 'Male');
      expect(labeled.reportedPersonaLabel, 'Female');
      expect(labeled.userPersonaLabel, 'Male');
      expect(labeled.selectionLabel, contains('Male'));
      expect(labeled.selectionLabel, contains('Your label'));
      expect(labeled.selectionLabel, isNot(contains('Female')));
      expect(labeled.toTtsMap(), original.toTtsMap());
      expect(labeled.requiresNetwork, isTrue);
      expect(labeled.qualityScore, 400);
      expect(labeled.withUserPersonaLabel(null).personaLabel, 'Female');
      expect(
        () => original.withUserPersonaLabel('Unknown guess'),
        throwsArgumentError,
      );
    },
  );

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

  test('unrelated voice names do not invent gender or age labels', () {
    for (final name in [
      'German narrator',
      'Roman',
      'Human voice',
      'skid',
      'boysenberry',
    ]) {
      expect(
        VoiceModel.fromMap({'name': name, 'locale': 'en'}).personaLabel,
        isNull,
      );
    }
    expect(VoiceModel.fromMap({'name': 'en-female-1'}).personaLabel, 'Female');
    expect(VoiceModel.fromMap({'name': 'en_male_2'}).personaLabel, 'Male');
    expect(VoiceModel.fromMap({'name': 'child3'}).personaLabel, 'Child');
    expect(
      VoiceModel.fromMap({'name': 'narrator', 'gender': 'F'}).personaLabel,
      'Female',
    );
    expect(
      VoiceModel.fromMap({'name': 'narrator', 'gender': 'M'}).personaLabel,
      'Male',
    );
  });
}
