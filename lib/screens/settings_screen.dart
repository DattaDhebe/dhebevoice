import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_controller.dart';
import '../services/tts_service.dart';
import '../widgets/tts_settings_panel.dart';
import '../widgets/offline_voice_panel.dart';
import '../widgets/reader_consumer.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmResetSettings(
    BuildContext context,
    TtsService ttsService,
  ) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset TTS settings'),
          content: const Text(
            'Reset language, voice, speech rate, pitch, and volume back to the default English India settings?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset == true) {
      await ttsService.resetSettings();
    }
  }

  @override
  Widget build(BuildContext context) => TtsSettingsConsumer(
    builder: (context, ttsService) => Consumer<ThemeController>(
      builder: (context, themeController, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            IconButton(
              tooltip: 'Reset voice settings',
              onPressed: () => _confirmResetSettings(context, ttsService),
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    'Voice & playback',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a speech engine, then tune your listening experience.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (ttsService.supportsOfflineVoice) ...[
                    OfflineVoicePanel(service: ttsService),
                    const SizedBox(height: 16),
                  ],
                  TtsSettingsPanel(
                    key: ValueKey(ttsService.usesOfflineVoice),
                    pitchEnabled: !ttsService.usesOfflineVoice,
                    onRefreshVoices: ttsService.usesOfflineVoice
                        ? null
                        : ttsService.refreshVoices,
                    onBestVoice: ttsService.usesOfflineVoice
                        ? null
                        : ttsService.selectBestInstalledVoice,
                    languages: ttsService.availableLanguages(),
                    selectedLanguage: ttsService.selectedLanguage,
                    selectedVoice: ttsService.selectedVoice,
                    voices: ttsService.voices,
                    rate: ttsService.speechRate,
                    pitch: ttsService.pitch,
                    volume: ttsService.volume,
                    padding: EdgeInsets.zero,
                    onLanguageChanged: (value) {
                      if (value != null) ttsService.setLanguage(value);
                    },
                    onVoiceSelected: (voice) =>
                        ttsService.setVoice(voice, confirmOnline: true),
                    onRateChanged: ttsService.setSpeechRate,
                    onPitchChanged: ttsService.setPitch,
                    onVolumeChanged: ttsService.setVolume,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Appearance',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<ThemeMode>(
                            key: ValueKey(themeController.themeMode),
                            initialValue: themeController.themeMode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'App theme',
                              prefixIcon: Icon(Icons.palette_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: ThemeMode.system,
                                child: Text('Follow device'),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.light,
                                child: Text('Light'),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.dark,
                                child: Text('Dark'),
                              ),
                            ],
                            onChanged: (mode) {
                              if (mode != null) {
                                themeController.setThemeMode(mode);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Content & privacy'),
                      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'DhebeVoice reads text you paste, import from local files, or choose to import from a web link. Books and reading positions are stored on this device.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Import only content you own, are licensed to access, or that is in the public domain. This app does not host books or grant rights to copyrighted material.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Offline neural voices process text on this device. Optional model downloads contact Hugging Face. Online Android voices may send text to your chosen TTS provider. No paid cloud TTS API is used.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'DhebeVoice',
                    ),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Open-source & voice model licenses'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
