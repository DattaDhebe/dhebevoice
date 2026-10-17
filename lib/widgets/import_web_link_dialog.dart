import 'package:flutter/material.dart';

class ImportWebLinkDialog extends StatefulWidget {
  const ImportWebLinkDialog({super.key, this.initialUrl = ''});

  final String initialUrl;

  @override
  State<ImportWebLinkDialog> createState() => _ImportWebLinkDialogState();
}

class _ImportWebLinkDialogState extends State<ImportWebLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    // The route stays mounted during its closing animation.
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted || _formKey.currentState?.validate() != true) return;
    _submitted = true;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('Import web link'),
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: widget.initialUrl.isEmpty,
              keyboardType: TextInputType.url,
              minLines: 1,
              maxLines: 3,
              autocorrect: false,
              validator: (value) {
                final uri = Uri.tryParse(value?.trim() ?? '');
                return uri != null &&
                        (uri.scheme == 'https' || uri.scheme == 'http') &&
                        uri.host.isNotEmpty
                    ? null
                    : 'Enter a complete http or https web link.';
              },
              decoration: const InputDecoration(
                labelText: 'Web page URL',
                hintText: 'https://example.com/page',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Import only text you own, are licensed to access, or that is in the public domain.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start import')),
      ],
    );
  }
}
