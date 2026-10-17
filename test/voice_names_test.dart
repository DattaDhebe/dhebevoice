import 'package:flutter_test/flutter_test.dart';
import 'package:text_reader_app/models/voice_model.dart';
import 'package:text_reader_app/models/voice_names.dart';

void main() {
  test('all ten neural narrators have distinct friendly names', () {
    final ids = [
      for (final gender in ['F', 'M'])
        for (var i = 1; i <= 5; i++) '$gender$i',
    ];
    final names = ids.map(VoiceNames.supertonic).toList();
    expect(names.toSet().length, 10);
    expect(names, containsAll(['Asha', 'Mira', 'Arun', 'Theo']));
    expect(names.any((name) => RegExp(r'[0-9]').hasMatch(name)), isFalse);
  });

  test('Android nicknames preserve engine identity and reported metadata', () {
    final voice = VoiceModel.fromMap({
      'name': 'en-in-x-ene-local',
      'locale': 'en-IN',
      'network_required': false,
    });
    expect(voice.label, VoiceNames.android('en-in-x-ene-local', 'en-IN'));
    expect(voice.label, isNot(contains('en-in-x')));
    expect(voice.toTtsMap(), {'name': 'en-in-x-ene-local', 'locale': 'en-IN'});
    expect(voice.detailsLabel, contains('en-in-x-ene-local'));
    expect(voice.personaLabel, isNull);
    expect(voice.requiresNetwork, isFalse);
  });

  test('provider human-readable names are preserved', () {
    expect(VoiceNames.android('Sonia', 'en-GB'), 'Sonia');
    expect(VoiceNames.android('Arjun', 'en-IN'), 'Arjun');
  });

  test('Android catalog resolves nickname collisions without changing IDs', () {
    final used = <String>{};
    final voices = [
      for (var i = 0; i < 400; i++)
        VoiceModel.fromMap({
          'name': 'en-us-x-$i-local',
          'locale': 'en-US',
        }, usedNames: used),
    ];
    expect(voices.map((voice) => voice.label).toSet().length, 400);
    expect(voices[100].name, 'en-us-x-100-local');
  });

  test('different technical Android voices get friendly names', () {
    final ids = [
      'en-in-x-ene-local',
      'en-in-x-ena-local',
      'en-in-x-enc-local',
      'en-in-x-ene-network',
    ];
    final names = ids.map((id) => VoiceNames.android(id, 'en-IN')).toList();
    expect(names.toSet().length, ids.length);
  });
}
