import 'voice_names.dart';

class VoiceModel {
  const VoiceModel({
    required this.name,
    required this.locale,
    required this.label,
    String? personaLabel,
    this.userPersonaLabel,
    this.metadataLabels = const [],
    this.qualityScore,
    this.requiresNetwork,
    this.isInstalled = true,
  }) : reportedPersonaLabel = personaLabel;

  final String name;
  final String locale;
  final String label;
  final String? reportedPersonaLabel;
  final String? userPersonaLabel;
  String? get personaLabel => userPersonaLabel ?? reportedPersonaLabel;
  String get personaDisplayLabel => personaLabel ?? 'Gender not provided';
  static const personaTypes = {'Female', 'Male', 'Child'};
  final List<String> metadataLabels;
  final int? qualityScore;
  final bool? requiresNetwork;
  final bool isInstalled;

  String get selectionLabel {
    final details = [
      ?personaLabel,
      if (userPersonaLabel != null) 'Your label',
      ...metadataLabels.where((label) => !personaTypes.contains(label)),
    ];
    if (details.isEmpty) {
      return label;
    }
    return '$label • ${details.join(' • ')}';
  }

  String get detailsLabel {
    final details = [
      personaDisplayLabel,
      if (userPersonaLabel != null) 'Your label',
      if (locale.isNotEmpty) locale,
      name,
    ];
    return details.join(' • ');
  }

  VoiceModel withUserPersonaLabel(String? value) {
    if (value != null && !personaTypes.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported voice type');
    }
    return VoiceModel(
      name: name,
      locale: locale,
      label: label,
      personaLabel: reportedPersonaLabel,
      userPersonaLabel: value,
      metadataLabels: metadataLabels,
      qualityScore: qualityScore,
      requiresNetwork: requiresNetwork,
      isInstalled: isInstalled,
    );
  }

  factory VoiceModel.fromMap(
    Map<String, dynamic> map, {
    Set<String>? usedNames,
  }) {
    final rawName = (map['name'] ?? map['voice'] ?? 'Unknown voice').toString();
    final rawLocale = (map['locale'] ?? map['language'] ?? '').toString();
    final label = VoiceNames.android(rawName, rawLocale, usedNames: usedNames);
    final personaLabel = _extractPersonaLabel(map, rawName);
    final metadataLabels = <String>[
      ?personaLabel,
      ..._extractMetadataLabels(map),
    ];

    return VoiceModel(
      name: rawName,
      locale: rawLocale,
      label: label,
      personaLabel: personaLabel,
      metadataLabels: metadataLabels,
      qualityScore: _qualityScore(map['quality']),
      requiresNetwork: _networkRequirement(map),
      isInstalled: !'${map['features']}'.contains('notInstalled'),
    );
  }

  Map<String, String> toTtsMap() => {'name': name, 'locale': locale};

  bool matchesIdentity(String? voiceName, String? voiceLocale) {
    return name == voiceName && locale == (voiceLocale ?? locale);
  }

  static String? _extractPersonaLabel(
    Map<String, dynamic> map,
    String rawName,
  ) {
    for (final key in ['gender', 'sex', 'voiceGender']) {
      final explicitGender = _normalizePersonaValue(map[key]?.toString());
      if (explicitGender != null) return explicitGender;
    }

    final featureGender = RegExp(
      r'\b(?:gender|sex)\s*[:=]\s*(female|male|woman|man|f|m)\b',
      caseSensitive: false,
    ).firstMatch('${map['features']}');
    if (featureGender != null) {
      return _normalizePersonaValue(featureGender.group(1));
    }

    final ageHint = _normalizePersonaValue(
      map['age']?.toString() ?? map['ageGroup']?.toString(),
    );
    if (ageHint == 'Child') {
      return ageHint;
    }

    return _personaNameHint(rawName.toLowerCase());
  }

  static String? _personaNameHint(String value) {
    if (RegExp(r'(?:^|[^a-z])(?:female|woman)(?=$|[^a-z])').hasMatch(value)) {
      return 'Female';
    }
    if (RegExp(r'(?:^|[^a-z])(?:male|man)(?=$|[^a-z])').hasMatch(value)) {
      return 'Male';
    }
    if (RegExp(
      r'(?:^|[^a-z])(?:child|kid|boy|girl)(?=$|[^a-z])',
    ).hasMatch(value)) {
      return 'Child';
    }
    return null;
  }

  static List<String> _extractMetadataLabels(Map<String, dynamic> map) {
    final labels = <String>{};
    final numericQuality = _qualityScore(map['quality']);
    final quality = numericQuality == null
        ? _normalizeMetadataValue(map['quality'])
        : numericQuality >= 400
        ? 'High quality'
        : numericQuality >= 300
        ? 'Normal quality'
        : 'Basic quality';
    final engine = _normalizeMetadataValue(map['engine']);

    if (quality != null) {
      labels.add(quality);
    }
    final network = _networkRequirement(map);
    if (network != null) labels.add(network ? 'Requires internet' : 'Offline');
    if (engine != null) {
      labels.add(engine);
    }

    return labels.toList();
  }

  static bool? _networkRequirement(Map<String, dynamic> map) {
    final raw = map['network_required'] ?? map['networkRequired'];
    if (raw == true || raw == 'true' || raw == 1 || raw == '1') return true;
    if (raw == false || raw == 'false' || raw == 0 || raw == '0') return false;
    return null;
  }

  static int? _qualityScore(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    return int.tryParse(text ?? '') ??
        const {
          'very high': 500,
          'high': 400,
          'normal': 300,
          'low': 200,
          'very low': 100,
        }[text];
  }

  static String? _normalizePersonaValue(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'f') {
      return 'Female';
    }
    if (normalized == 'm') {
      return 'Male';
    }
    return _personaNameHint(normalized);
  }

  static String? _normalizeMetadataValue(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value == 'null') {
      return null;
    }
    return value;
  }
}
