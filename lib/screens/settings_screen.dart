import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_controller.dart';
import '../services/tts_service.dart';
import '../widgets/tts_settings_panel.dart';
import '../widgets/offline_voice_panel.dart';

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
  Widget build(BuildContext context) {
    return Consumer2<ThemeController, TtsService>(
      builder: (context, themeController, ttsService, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            actions: [
              IconButton(
                tooltip: 'Reset settings',
                onPressed: () => _confirmResetSettings(context, ttsService),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {themeController.themeMode},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            themeController.setThemeMode(selection.first);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Content & Privacy',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'DhebeVoice is a personal reader for text you paste, import from local files, or choose to import from a link.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Import only content you own, are licensed to access, or that is in the public domain. DhebeVoice does not host books or grant rights to copyrighted material.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Offline neural voices process reading text on this device. Optional model downloads contact Hugging Face. Online Android voices may send reading text to your chosen TTS provider. DhebeVoice uses no paid cloud TTS API.',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Before publishing on Google Play, add a public privacy policy URL in Play Console and complete the Data safety form with your real data practices.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                  if (value != null) {
                    ttsService.setLanguage(value);
                  }
                },
                onVoiceSelected: (voice) =>
                    ttsService.setVoice(voice, confirmOnline: true),
                onRateChanged: ttsService.setSpeechRate,
                onPitchChanged: ttsService.setPitch,
                onVolumeChanged: ttsService.setVolume,
              ),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'DhebeVoice',
                ),
                child: const Text('Open-source and voice model licenses'),
              ),
            ],
          ),
        );
      },
    );
  }
}
