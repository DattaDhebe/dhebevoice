import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _textKey = 'reader_text';
  static const _languageKey = 'reader_language';
  static const _voiceNameKey = 'reader_voice_name';
  static const _voiceLocaleKey = 'reader_voice_locale';
  static const _rateKey = 'reader_rate';
  static const _pitchKey = 'reader_pitch';
  static const _volumeKey = 'reader_volume';
  static const _positionKey = 'reader_position';
  static const _activeNovelIdKey = 'reader_active_novel_id';
  static const _activeChapterIndexKey = 'reader_active_chapter_index';
  static const _themeModeKey = 'reader_theme_mode';
  static const _webAccessModeKey = 'reader_web_access_mode';
  static const _homeGuideSeenKey = 'reader_home_guide_seen';
  static const _sampleBookSeededKey = 'reader_sample_book_seeded';

  late final SharedPreferences _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get text => _prefs.getString(_textKey) ?? '';
  String? get language => _prefs.getString(_languageKey);
  String? get voiceName => _prefs.getString(_voiceNameKey);
  String? get voiceLocale => _prefs.getString(_voiceLocaleKey);
  double get rate => _prefs.getDouble(_rateKey) ?? 0.48;
  double get pitch => _prefs.getDouble(_pitchKey) ?? 1.0;
  double get volume => _prefs.getDouble(_volumeKey) ?? 1.0;
  int get position => _prefs.getInt(_positionKey) ?? 0;
  String? get activeNovelId => _prefs.getString(_activeNovelIdKey);
  int get activeChapterIndex => _prefs.getInt(_activeChapterIndexKey) ?? 0;
  String? get themeMode => _prefs.getString(_themeModeKey);
  String? get webAccessModeId => _prefs.getString(_webAccessModeKey);
  bool get hasSeenHomeGuide => _prefs.getBool(_homeGuideSeenKey) ?? false;
  bool get hasSeededSampleBook => _prefs.getBool(_sampleBookSeededKey) ?? false;

  int? chapterIndexForNovel(String id) => _prefs.getInt('reader_chapter_$id');

  Future<void> saveNovelChapterIndex(String id, int index) =>
      _prefs.setInt('reader_chapter_$id', index);

  Future<void> saveText(String value) => _prefs.setString(_textKey, value);
  Future<void> saveLanguage(String value) =>
      _prefs.setString(_languageKey, value);

  Future<void> saveVoice(String? name, String? locale) async {
    if (name == null || locale == null) {
      await _prefs.remove(_voiceNameKey);
      await _prefs.remove(_voiceLocaleKey);
      return;
    }

    await _prefs.setString(_voiceNameKey, name);
    await _prefs.setString(_voiceLocaleKey, locale);
  }

  Future<void> saveRate(double value) => _prefs.setDouble(_rateKey, value);
  Future<void> savePitch(double value) => _prefs.setDouble(_pitchKey, value);
  Future<void> saveVolume(double value) => _prefs.setDouble(_volumeKey, value);
  Future<void> savePosition(int value) => _prefs.setInt(_positionKey, value);
  Future<void> saveThemeMode(String value) =>
      _prefs.setString(_themeModeKey, value);
  Future<void> saveWebAccessModeId(String value) =>
      _prefs.setString(_webAccessModeKey, value);
  Future<void> saveHasSeenHomeGuide(bool value) =>
      _prefs.setBool(_homeGuideSeenKey, value);
  Future<void> saveHasSeededSampleBook(bool value) =>
      _prefs.setBool(_sampleBookSeededKey, value);

  Future<void> resetTtsSettings() async {
    await _prefs.remove(_languageKey);
    await _prefs.remove(_voiceNameKey);
    await _prefs.remove(_voiceLocaleKey);
    await _prefs.remove(_rateKey);
    await _prefs.remove(_pitchKey);
    await _prefs.remove(_volumeKey);
  }

  Future<void> saveActiveNovelId(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_activeNovelIdKey);
      return;
    }
    await _prefs.setString(_activeNovelIdKey, value);
  }

  Future<void> saveActiveChapterIndex(int value) =>
      _prefs.setInt(_activeChapterIndexKey, value);
}
