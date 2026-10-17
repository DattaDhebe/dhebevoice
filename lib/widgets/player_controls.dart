import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.isPlaying,
    required this.canResume,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    this.compactIconsOnly = false,
    this.wrapInSafeArea = true,
    this.enabled = true,
  });

  final bool isPlaying;
  final bool canResume;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final bool compactIconsOnly;
  final bool wrapInSafeArea;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    Widget button(
      String label,
      IconData icon,
      VoidCallback? onPressed, {
      bool primary = false,
    }) {
      final child = compactIconsOnly
          ? Icon(icon, size: 28)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1),
                ),
              ],
            );
      final style = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
      );
      return Expanded(
        child: Tooltip(
          message: label,
          child: primary
              ? FilledButton(style: style, onPressed: onPressed, child: child)
              : OutlinedButton(
                  style: style,
                  onPressed: onPressed,
                  child: child,
                ),
        ),
      );
    }

    final controls = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.outlineVariant),
      ),
      child: Row(
        children: [
          button(
            canResume ? 'Resume' : 'Play',
            Icons.play_arrow_rounded,
            enabled && !isPlaying ? onPlay : null,
            primary: true,
          ),
          const SizedBox(width: 8),
          button(
            'Pause',
            Icons.pause_rounded,
            enabled && isPlaying ? onPause : null,
          ),
          const SizedBox(width: 8),
          button('Stop', Icons.stop_rounded, enabled ? onStop : null),
        ],
      ),
    );
    return wrapInSafeArea ? SafeArea(top: false, child: controls) : controls;
  }
}
