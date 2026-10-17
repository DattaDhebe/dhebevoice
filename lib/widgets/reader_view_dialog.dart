import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/novel_import_controller.dart';
import 'player_controls.dart';
import 'reader_consumer.dart';

class ReaderViewDialog extends StatelessWidget {
  const ReaderViewDialog({
    super.key,
    required this.fullContent,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
  });

  final bool fullContent;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final expandedLayout =
        fullContent ||
        media.textScaler.scale(1) > 1.4 ||
        media.size.height < 600;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: 760,
        height: math.min(
          (media.size.height -
                  media.viewInsets.bottom -
                  media.padding.vertical) *
              (expandedLayout ? 0.84 : 0.7),
          expandedLayout ? 760 : 600,
        ),
        child: ReaderConsumer(
          builder: (context, service) {
            final chapter = context.select<NovelImportController, String?>(
              (importer) => importer.activeChapter?.title,
            );
            final theme = Theme.of(context);
            final color = theme.colorScheme;
            final count = service.paragraphCount;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fullContent ? 'Reading content' : 'Now reading',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      key: ValueKey((
                        fullContent,
                        service.text,
                        fullContent ? 0 : service.currentParagraphIndex,
                      )),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        Text(
                          chapter ?? 'Your text',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (count > 0) ...[
                          Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: 'Play previous paragraph',
                                onPressed: service.currentParagraphIndex > 0
                                    ? () => unawaited(
                                        service.playPreviousParagraph(),
                                      )
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Text(
                                  'Paragraph ${service.currentParagraphIndex + 1} of $count',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: color.primary,
                                  ),
                                ),
                              ),
                              IconButton.filledTonal(
                                tooltip: 'Play next paragraph',
                                onPressed:
                                    service.currentParagraphIndex < count - 1
                                    ? () =>
                                          unawaited(service.playNextParagraph())
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        SelectableText(
                          fullContent
                              ? (service.text.isEmpty
                                    ? service.currentParagraph
                                    : service.text)
                              : service.currentParagraph,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.65,
                            fontSize: 18,
                            color: fullContent
                                ? color.onSurface
                                : color.primary,
                          ),
                          contextMenuBuilder: (context, editable) =>
                              AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: editable.contextMenuAnchors,
                                buttonItems: [
                                  ...editable.contextMenuButtonItems,
                                  if (fullContent &&
                                      editable
                                          .textEditingValue
                                          .selection
                                          .isValid &&
                                      !editable
                                          .textEditingValue
                                          .selection
                                          .isCollapsed)
                                    ContextMenuButtonItem(
                                      label: 'Play selection',
                                      onPressed: () {
                                        final selection =
                                            editable.textEditingValue.selection;
                                        ContextMenuController.removeAny();
                                        unawaited(
                                          service.playSelection(selection),
                                        );
                                      },
                                    ),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PlayerControls(
                    isPlaying: service.isPlaying,
                    canResume: service.isPaused || service.currentCharIndex > 0,
                    enabled:
                        service.hasInitialized &&
                        !service.switchingVoice &&
                        count > 0,
                    onPlay: onPlay,
                    onPause: onPause,
                    onStop: onStop,
                    wrapInSafeArea: false,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
