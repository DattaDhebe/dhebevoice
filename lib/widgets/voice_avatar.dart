import 'package:flutter/material.dart';

import '../models/voice_model.dart';

class VoiceAvatar extends StatelessWidget {
  const VoiceAvatar({super.key, required this.voice, this.size = 44});

  final VoiceModel voice;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = [
      (colors.primaryContainer, colors.onPrimaryContainer),
      (colors.secondaryContainer, colors.onSecondaryContainer),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
    ];
    final index = voice.name.codeUnits.fold(0, (sum, unit) => sum + unit);
    final (background, foreground) = palette[index % palette.length];
    final icon = switch (voice.personaLabel) {
      'Female' => Icons.face_3_rounded,
      'Male' => Icons.face_6_rounded,
      'Child' => Icons.child_care_rounded,
      _ => Icons.record_voice_over_rounded,
    };
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: background,
        foregroundColor: foreground,
        child: Icon(icon, size: size * .62),
      ),
    );
  }
}
