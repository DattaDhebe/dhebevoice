import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tts_service.dart';

/// Word-level speech callbacks should not rebuild an entire reader screen.
class ReaderConsumer extends StatelessWidget {
  const ReaderConsumer({super.key, required this.builder});

  final Widget Function(BuildContext context, TtsService service) builder;

  @override
  Widget build(BuildContext context) {
    return Selector<TtsService, Object>(
      selector: (_, service) => (
        service.text,
        service.playbackState,
        service.isBuffering,
        service.isAdvancingChapter,
        service.currentParagraphIndex,
        service.hasInitialized,
        service.switchingVoice,
        service.errorMessage,
        service.sleepTimerEndsAt,
      ),
      builder: (context, _, _) => builder(context, context.read<TtsService>()),
    );
  }
}

class TtsSettingsConsumer extends StatelessWidget {
  const TtsSettingsConsumer({super.key, required this.builder});

  final Widget Function(BuildContext context, TtsService service) builder;

  @override
  Widget build(BuildContext context) => Selector<TtsService, Object>(
    selector: (_, service) => (
      service.voices,
      service.selectedVoice,
      service.selectedLanguage,
      service.speechRate,
      service.pitch,
      service.volume,
      service.usesOfflineVoice,
      service.switchingVoice,
      service.errorMessage,
      service.hasInitialized,
    ),
    builder: (context, _, _) => builder(context, context.read<TtsService>()),
  );
}
