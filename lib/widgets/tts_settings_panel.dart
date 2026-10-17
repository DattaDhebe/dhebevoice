import 'package:flutter/material.dart';

import '../models/voice_model.dart';

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
  final bool showOnlineVoices;

  Future<void> _chooseVoice(
    BuildContext context,
    List<VoiceModel> choices, {
    bool onlineOnly = false,
  }) async {
    final result = await showSearch<VoiceModel?>(
      context: context,
      delegate: _VoiceSearchDelegate(
        voices: choices,
        selectedVoice: selectedVoice,
        onlineOnly: onlineOnly,
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
                    initialValue: languages.contains(selectedLanguage)
                        ? selectedLanguage
                        : (languages.isEmpty ? null : languages.first),
                    items: languages
                        .map(
                          (language) => DropdownMenuItem(
                            value: language,
                            child: Text(language),
                          ),
                        )
                        .toList(),
                    onChanged: onLanguageChanged,
                    decoration: const InputDecoration(
                      hintText: 'Select a language',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Voice', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: languageVoices.isEmpty
                        ? null
                        : () => _chooseVoice(context, languageVoices),
                    icon: const Icon(Icons.record_voice_over),
                    label: Text(
                      selectedVoice?.selectionLabel ?? 'Choose installed voice',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
            value: rate,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            valueText: rate.toStringAsFixed(2),
            onChanged: onRateChanged,
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

class _VoiceSearchDelegate extends SearchDelegate<VoiceModel?> {
  _VoiceSearchDelegate({
    required this.voices,
    required this.selectedVoice,
    this.onlineOnly = false,
  }) : _connection = ValueNotifier<String>(onlineOnly ? 'Online' : 'All');

  final List<VoiceModel> voices;
  final VoiceModel? selectedVoice;
  final bool onlineOnly;
  final ValueNotifier<String> _connection;

  @override
  void dispose() {
    _connection.dispose();
    super.dispose();
  }

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildVoiceList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildVoiceList(context);

  Widget _buildVoiceList(
    BuildContext context,
  ) => ValueListenableBuilder<String>(
    valueListenable: _connection,
    builder: (context, filter, _) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final label
                  in onlineOnly ? ['Online'] : ['All', 'Offline', 'Online'])
                ChoiceChip(
                  label: Text(label),
                  selected: filter == label,
                  onSelected: (_) => _connection.value = label,
                ),
            ],
          ),
        ),
        if (filter == 'Online')
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Online voices come from your installed Android TTS engine, not a DhebeVoice paid API. Availability depends on that engine.',
            ),
          ),
        Expanded(child: _filteredVoiceList(context, filter)),
      ],
    ),
  );

  Widget _filteredVoiceList(BuildContext context, String filter) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = voices.where((voice) {
      if (filter == 'Offline' && voice.requiresNetwork != false) return false;
      if (filter == 'Online' && voice.requiresNetwork != true) return false;
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return voice.label.toLowerCase().contains(normalizedQuery) ||
          voice.selectionLabel.toLowerCase().contains(normalizedQuery) ||
          voice.name.toLowerCase().contains(normalizedQuery) ||
          voice.locale.toLowerCase().contains(normalizedQuery) ||
          voice.detailsLabel.toLowerCase().contains(normalizedQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            onlineOnly && voices.isEmpty
                ? 'No online voices are exposed by your current Android TTS engine. Check device TTS settings, update the engine, then reopen DhebeVoice and refresh voices.'
                : 'No installed voices match that search.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final voice = filtered[index];
        final isSelected =
            selectedVoice?.name == voice.name &&
            selectedVoice?.locale == voice.locale;
        return ListTile(
          title: Text(voice.label),
          subtitle: Text(
            [voice.detailsLabel, ...voice.metadataLabels].join('\n'),
          ),
          trailing: isSelected
              ? const Icon(Icons.check_circle)
              : voice.personaLabel == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    voice.personaLabel!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
          onTap: () => close(context, voice),
        );
      },
    );
  }
}
