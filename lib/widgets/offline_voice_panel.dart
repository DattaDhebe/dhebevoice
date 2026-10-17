import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tts_service.dart';
import 'reader_consumer.dart';

class OfflineVoicePanel extends StatefulWidget {
  const OfflineVoicePanel({super.key, required this.service});
  final TtsService service;
  @override
  State<OfflineVoicePanel> createState() => _OfflineVoicePanelState();
}

class _OfflineVoicePanelState extends State<OfflineVoicePanel> {
  @override
  void initState() {
    super.initState();
    widget.service.modelStore.initialize();
  }

  Future<void> _download() async {
    final license = await rootBundle.loadString(
      'assets/licenses/supertonic-model.txt',
    );
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download free offline voices'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Supertonic 3: about 402 MB, ten voices, no paid API. Requires 64-bit Android, substantial free memory, and at least 850 MB of free storage. Wi-Fi is recommended. Slower phones may pause between speech segments.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The files come from the official Hugging Face archive. Your reading text stays on this device. The download server receives normal connection details such as your IP address.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The model is free under OpenRAIL-M, not unrestricted. Use it lawfully and follow the full license below. The upstream project is archived and no longer maintained.',
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Read model license'),
                  children: [SelectableText(license)],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and download'),
          ),
        ],
      ),
    );
    if (accepted == true) await widget.service.modelStore.download();
  }

  Future<void> _remove() async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete offline voices?'),
        content: const Text(
          'Switches back to Android TTS and removes the voice pack. Your books stay unchanged. You can download the pack again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (remove == true) await widget.service.removeOfflineVoicePack();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final store = service.modelStore;
    return TtsSettingsConsumer(
      builder: (context, _) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Speech engine',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool>(
                  key: ValueKey(service.usesOfflineVoice),
                  initialValue: service.usesOfflineVoice,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: false,
                      child: Text(
                        'Android TTS - device & online',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (store.ready)
                      const DropdownMenuItem(
                        value: true,
                        child: Text(
                          'Supertonic 3 - offline neural',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: service.switchingVoice
                      ? null
                      : (value) {
                          if (value != null) {
                            service.setOfflineVoiceEnabled(value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  store.ready
                      ? 'Ten free neural voices installed. Select Supertonic above, then choose language and voice below.'
                      : 'Add ten free neural voices for local narration. Your current Android voices remain available.',
                ),
                const SizedBox(height: 12),
                if (store.downloading) ...[
                  LinearProgressIndicator(value: store.progress),
                  const SizedBox(height: 8),
                  Text(
                    '${(store.progress * 100).toStringAsFixed(0)}% - ${store.currentFile ?? 'Preparing download'}',
                  ),
                  TextButton.icon(
                    onPressed: store.cancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel download'),
                  ),
                ] else if (store.ready)
                  OutlinedButton.icon(
                    onPressed: service.switchingVoice ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete voice pack'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _download,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Supertonic 3'),
                  ),
                if (store.error != null)
                  Text(
                    store.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (service.errorMessage != null)
                  Text(
                    service.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (service.usesOfflineVoice) ...[
                  const SizedBox(height: 16),
                  const Text('Quality narration (5 steps)'),
                  const SizedBox(height: 12),
                  const Text(
                    'The experimental 3-step mode was removed because it can distort speech. Quality does not change your listening speed; use Speech rate below.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Background preparation is the default: playback starts when the first audio is ready, while up to eight upcoming segments are generated ahead. Quality and speech rate stay unchanged.',
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('neural-chapter-preparation'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Wait for the whole chapter (optional)'),
                    subtitle: const Text(
                      'Off: start sooner and prepare ahead while listening. On: wait for the whole chapter first.',
                    ),
                    value: service.prepareNeuralChapter,
                    onChanged: service.setPrepareNeuralChapter,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Voice or rate changes prepare the remaining chapter at the next segment. Preparation supports up to 50,000 text characters and 256 MB of temporary audio.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'On slower phones, generation may still fall behind playback and show buffering. Audio stays on this device and is cleared on Stop. Pause retains streaming audio; pausing whole-chapter preparation cancels that job. Pitch is fixed. Playback position is saved at segment boundaries.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
