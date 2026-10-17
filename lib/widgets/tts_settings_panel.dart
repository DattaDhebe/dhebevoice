import 'package:flutter/material.dart';

import '../models/speech_locale.dart';
import '../models/voice_model.dart';
import 'voice_avatar.dart';
import 'voice_picker_sheet.dart';

class TtsSettingsPanel extends StatelessWidget {
  const TtsSettingsPanel({
    super.key,
    required this.languages,
    required this.selectedLanguage,
    required this.selectedVoice,
    required this.voices,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.onLanguageChanged,
    required this.onVoiceSelected,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
    this.pitchEnabled = true,
    this.onRefreshVoices,
    this.onBestVoice,
    this.onVoiceTypeChanged,
    this.showOnlineVoices = true,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });

  final List<String> languages;
  final String selectedLanguage;
  final VoiceModel? selectedVoice;
  final List<VoiceModel> voices;
  final double rate;
  final double pitch;
  final double volume;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<VoiceModel?> onVoiceSelected;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onVolumeChanged;
  final EdgeInsets padding;
  final bool pitchEnabled;
  final VoidCallback? onRefreshVoices;
  final VoidCallback? onBestVoice;
  final Future<void> Function(VoiceModel voice, String? type)?
  onVoiceTypeChanged;
  final bool showOnlineVoices;

  Future<void> _chooseVoice(
    BuildContext context,
    List<VoiceModel> choices, {
    bool onlineOnly = false,
  }) async {
    final result = await showModalBottomSheet<VoiceModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: .9,
          child: VoicePickerSheet(
            voices: choices,
            selectedVoice: selectedVoice,
            onlineOnly: onlineOnly,
            onVoiceTypeChanged: onVoiceTypeChanged,
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.requiresNetwork == true) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use an online Android voice?'),
          content: const Text(
            'This voice needs internet and may send reading text to your installed TTS provider. DhebeVoice does not use a paid TTS API or require an API key. Provider terms and mobile data charges still apply. Choose an offline voice to keep speech local.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use online voice'),
            ),
          ],
        ),
      );
      if (accepted != true || !context.mounted) return;
    }
    onVoiceSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final sortedLanguages = [...languages]
      ..sort((a, b) => SpeechLocale.label(a).compareTo(SpeechLocale.label(b)));
    final languageVoices = voices
        .where((voice) => voice.locale == selectedLanguage)
        .toList();
    final onlineVoices =
        voices
            .where(
              (voice) => voice.isInstalled && voice.requiresNetwork == true,
            )
            .toList()
          ..sort(
            (a, b) => (b.qualityScore ?? 0).compareTo(a.qualityScore ?? 0),
          );

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Language',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedLanguage),
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    menuMaxHeight: MediaQuery.sizeOf(context).height * .6,
                    initialValue: languages.contains(selectedLanguage)
                        ? selectedLanguage
                        : (languages.isEmpty ? null : languages.first),
                    selectedItemBuilder: (_) => sortedLanguages
                        .map(
                          (language) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Tooltip(
                              message: SpeechLocale.label(language),
                              child: Text(
                                SpeechLocale.label(language),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    items: sortedLanguages
                        .map(
                          (language) => DropdownMenuItem(
                            value: language,
                            child: Text(SpeechLocale.label(language)),
                          ),
                        )
                        .toList(),
                    onChanged: onLanguageChanged,
                    decoration: const InputDecoration(
                      hintText: 'Select a language',
                      prefixIcon: Icon(Icons.language),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Voice', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: languageVoices.isEmpty
                        ? null
                        : () => _chooseVoice(context, languageVoices),
                    icon: selectedVoice == null
                        ? const Icon(Icons.record_voice_over)
                        : VoiceAvatar(voice: selectedVoice!, size: 28),
                    label: Text(
                      selectedVoice?.selectionLabel ?? 'Choose installed voice',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Voice and language changes continue automatically at the next speech segment. Language changes pronunciation, not the written text.',
                  ),
                  if (showOnlineVoices) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _chooseVoice(context, onlineVoices, onlineOnly: true),
                      icon: const Icon(Icons.cloud_outlined),
                      label: Text(
                        'Online Android voices (${onlineVoices.length})',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      onlineVoices.isEmpty
                          ? 'Your current Android engine reports no online voices. Enable or update a speech engine such as Google Speech Recognition & Synthesis in device TTS settings, then reopen DhebeVoice.'
                          : 'Browse online voices across all languages, ranked by engine-reported quality. No paid API key is used by DhebeVoice; provider terms and data charges apply.',
                    ),
                  ],
                  if (onRefreshVoices != null)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: onRefreshVoices,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh voices'),
                        ),
                        TextButton.icon(
                          onPressed: onBestVoice,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Best installed voice'),
                        ),
                      ],
                    ),
                  if (onBestVoice != null)
                    const Text(
                      'Prefers offline voices, then engine-reported quality. A higher quality rating is not a guarantee of a more natural voice.',
                    ),
                ],
              ),
            ),
          ),
          _SettingSlider(
            title: 'Speech rate',
            value: pitchEnabled ? rate : (rate / .48).clamp(.5, 2),
            min: pitchEnabled ? 0.1 : .5,
            max: pitchEnabled ? 1.0 : 2,
            divisions: pitchEnabled ? 18 : 30,
            valueText: pitchEnabled
                ? rate.toStringAsFixed(2)
                : '${(rate / .48).clamp(.5, 2).toStringAsFixed(2)}x',
            onChanged: (value) =>
                onRateChanged(pitchEnabled ? value : value * .48),
          ),
          if (pitchEnabled)
            _SettingSlider(
              title: 'Pitch',
              value: pitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              valueText: pitch.toStringAsFixed(2),
              onChanged: onPitchChanged,
            ),
          _SettingSlider(
            title: 'Volume',
            value: volume,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            valueText: volume.toStringAsFixed(2),
            onChanged: onVolumeChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(valueText),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueText,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
