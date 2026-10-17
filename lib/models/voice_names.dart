/// DhebeVoice nicknames, not provider identities or claims about voice quality.
class VoiceNames {
  static const _supertonic = {
    'F1': 'Asha',
    'F2': 'Mira',
    'F3': 'Clara',
    'F4': 'Iris',
    'F5': 'Nora',
    'M1': 'Arun',
    'M2': 'Theo',
    'M3': 'Rowan',
    'M4': 'Felix',
    'M5': 'Leo',
  };

  static String supertonic(String id) => _supertonic[id] ?? id;

  // Neutral names do not invent gender metadata for Android engine IDs.
  static const _given = [
    'Alex',
    'Avery',
    'Bailey',
    'Blair',
    'Cameron',
    'Casey',
    'Charlie',
    'Dakota',
    'Devon',
    'Drew',
    'Eden',
    'Ellis',
    'Emery',
    'Finley',
    'Frankie',
    'Harper',
    'Hayden',
    'Jamie',
    'Jesse',
    'Jordan',
    'Jules',
    'Kai',
    'Kendall',
    'Lane',
    'Logan',
    'Marley',
    'Morgan',
    'Parker',
    'Quinn',
    'Reese',
    'Riley',
    'Robin',
    'Rory',
    'Sage',
    'Sam',
    'Shay',
    'Skyler',
    'Taylor',
    'Terry',
    'Wren',
  ];
  static const _family = [
    'Ash',
    'Banks',
    'Bell',
    'Birch',
    'Brooks',
    'Brook',
    'Cedar',
    'Cole',
    'Dale',
    'Dawn',
    'Fern',
    'Finch',
    'Ford',
    'Forest',
    'Frost',
    'Glen',
    'Gray',
    'Green',
    'Hart',
    'Hill',
    'Lake',
    'Linden',
    'Marsh',
    'Meadow',
    'North',
    'Oak',
    'Park',
    'Reed',
    'River',
    'Stone',
    'Vale',
    'Wells',
  ];

  static String android(String id, String locale, {Set<String>? usedNames}) {
    final trimmed = id.trim();
    final technical =
        RegExp(r'[0-9_#-]').hasMatch(trimmed) ||
        RegExp(r'^[a-z]{2,3}$').hasMatch(trimmed) ||
        const {
          'voice',
          'narrator',
          'unknown voice',
        }.contains(trimmed.toLowerCase());
    if (!technical &&
        trimmed.isNotEmpty &&
        (usedNames == null || usedNames.add(trimmed))) {
      return trimmed;
    }
    var hash = 2166136261;
    // Unlike String.hashCode, this mapping is stable between app processes.
    for (final unit in '$id|$locale'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xffffffff;
    }
    final capacity = _given.length * _family.length;
    for (var attempt = 0; ; attempt++) {
      final index = (hash + attempt) % capacity;
      final alias =
          '${_given[index % _given.length]} ${_family[index ~/ _given.length]}';
      final candidate = attempt < capacity
          ? alias
          : '$alias ${attempt ~/ capacity + 1}';
      if (usedNames == null || usedNames.add(candidate)) return candidate;
    }
  }
}
