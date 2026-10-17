import 'package:flutter/material.dart';

import '../models/speech_locale.dart';
import '../services/tts_service.dart';
import 'voice_avatar.dart';

class PlaybackStatus extends StatelessWidget {
  const PlaybackStatus({
    super.key,
    required this.service,
    this.compact = false,
  });

  final TtsService service;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final theme = Theme.of(context);
      final color = theme.colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                service.isBuffering
                    ? Icons.hourglass_top_rounded
                    : service.isPlaying
                    ? Icons.equalizer_rounded
                    : service.isPaused
                    ? Icons.pause_circle_outline
                    : Icons.headphones_rounded,
                color: color.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service.playbackStatusLabel,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!compact && service.paragraphCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${service.currentParagraphIndex + 1} / ${service.paragraphCount}',
                  semanticsLabel:
                      'Paragraph ${service.currentParagraphIndex + 1} of ${service.paragraphCount}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (service.isBuffering) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: service.preparationProgress,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: service.preparationStages ?? 'Speech preparation',
            ),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                service.preparationMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      );
    },
  );
}

class SelectedVoiceLabel extends StatelessWidget {
  const SelectedVoiceLabel({super.key, required this.service});

  final TtsService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final theme = Theme.of(context);
      final voice = service.selectedVoice;
      if (voice == null) return const SizedBox.shrink();
      return Row(
        children: [
          VoiceAvatar(voice: voice, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${voice.label} - ${SpeechLocale.label(service.selectedLanguage)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    },
  );
}
