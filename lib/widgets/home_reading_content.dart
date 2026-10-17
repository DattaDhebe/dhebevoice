import 'package:flutter/material.dart';

class HomeReadingContent extends StatelessWidget {
  const HomeReadingContent({
    super.key,
    required this.controller,
    required this.editorHeight,
    required this.onViewFull,
    required this.onPaste,
    required this.onNewText,
    required this.onChanged,
    required this.onPlaySelection,
    this.showBookEditingHint = false,
  });

  final TextEditingController controller;
  final double editorHeight;
  final bool showBookEditingHint;
  final VoidCallback onViewFull;
  final VoidCallback onPaste;
  final VoidCallback onNewText;
  final ValueChanged<String> onChanged;
  final ValueChanged<TextSelection> onPlaySelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const ValueKey('reading-content-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reading content',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: TextButton(
                    key: const ValueKey('content-full-view'),
                    onPressed: onViewFull,
                    child: const Text(
                      'View full',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 14),
            SizedBox(
              height: editorHeight,
              child: TextField(
                key: const ValueKey('reading-editor'),
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                contextMenuBuilder: (context, editableTextState) {
                  final selection =
                      editableTextState.textEditingValue.selection;
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: [
                      ...editableTextState.contextMenuButtonItems,
                      if (selection.isValid && !selection.isCollapsed)
                        ContextMenuButtonItem(
                          label: 'Play selection',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            onPlaySelection(selection);
                          },
                        ),
                    ],
                  );
                },
                decoration: const InputDecoration(
                  hintText: 'Paste or type something you would like to hear...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste text'),
                ),
                if (controller.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: onNewText,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('New text'),
                  ),
              ],
            ),
            if (showBookEditingHint) ...[
              const SizedBox(height: 4),
              Text(
                'Editing starts a new text session. Your saved book stays in the Book List.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
