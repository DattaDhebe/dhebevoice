import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/speech_locale.dart';
import '../models/voice_model.dart';
import 'voice_avatar.dart';

class VoicePickerSheet extends StatefulWidget {
  const VoicePickerSheet({
    super.key,
    required this.voices,
    this.selectedVoice,
    this.onlineOnly = false,
    this.onVoiceTypeChanged,
  });

  final List<VoiceModel> voices;
  final VoiceModel? selectedVoice;
  final bool onlineOnly;
  final Future<void> Function(VoiceModel voice, String? type)?
  onVoiceTypeChanged;

  @override
  State<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<VoicePickerSheet> {
  final _searchController = TextEditingController();
  VoiceModel? _pendingVoice;
  String _query = '';
  late String _connection;
  late List<VoiceModel> _voices;
  bool _savingVoiceType = false;

  @override
  void initState() {
    super.initState();
    _connection = widget.onlineOnly ? 'Online' : 'All';
    _voices = List.of(widget.voices);
    _pendingVoice = _voices
        .where(
          (voice) =>
              voice.isInstalled &&
              voice.matchesIdentity(
                widget.selectedVoice?.name,
                widget.selectedVoice?.locale,
              ),
        )
        .firstOrNull;
  }

  Future<void> _labelSelectedVoice() async {
    final voice = _pendingVoice;
    if (voice == null || widget.onVoiceTypeChanged == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Voice type for ${voice.label}'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Some Android engines do not report gender. Choose a label after listening. It is saved only on this device and does not change the voice audio.',
            ),
          ),
          for (final type in VoiceModel.personaTypes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, type),
              child: Text(type),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'provider'),
            child: const Text('Use provider label'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final label = choice == 'provider' ? null : choice;
    setState(() => _savingVoiceType = true);
    try {
      await widget.onVoiceTypeChanged!(voice, label);
      if (!mounted) return;
      setState(() {
        _voices = [
          for (final item in _voices)
            if (item.matchesIdentity(voice.name, voice.locale))
              item.withUserPersonaLabel(label)
            else
              item,
        ];
        if (_pendingVoice?.matchesIdentity(voice.name, voice.locale) == true) {
          _pendingVoice = _voices.firstWhere(
            (item) => item.matchesIdentity(voice.name, voice.locale),
          );
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the voice type. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingVoiceType = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _voices.where((voice) {
      if (!voice.isInstalled) return false;
      if (_connection == 'Online' && voice.requiresNetwork != true) {
        return false;
      }
      if (_connection == 'Offline' && voice.requiresNetwork != false) {
        return false;
      }
      final searchable = [
        voice.label,
        voice.name,
        voice.locale,
        voice.detailsLabel,
        if (voice.personaLabel == null) 'unknown',
        ...voice.metadataLabels,
        SpeechLocale.label(voice.locale),
      ].join(' ').toLowerCase();
      return _query.split(RegExp(r'\s+')).every((word) {
        if (const {'male', 'female', 'child'}.contains(word)) {
          return voice.personaLabel?.toLowerCase() == word;
        }
        return searchable.contains(word);
      });
    }).toList();
    final canSubmit = filtered.any(
      (voice) =>
          voice.matchesIdentity(_pendingVoice?.name, _pendingVoice?.locale),
    );
    final showFilters =
        widget.onlineOnly ||
        _voices.any((voice) => voice.requiresNetwork != false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.onlineOnly ? 'Online voices' : 'Choose voice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (widget.onVoiceTypeChanged != null)
                IconButton(
                  tooltip: 'Label selected voice type',
                  onPressed: canSubmit && !_savingVoiceType
                      ? _labelSelectedVoice
                      : null,
                  icon: const Icon(Icons.badge_outlined),
                ),
              IconButton(
                tooltip: 'Close voice picker',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final columns = math.max(
                1,
                math.min(
                  3,
                  ((constraints.maxWidth - 40) / (160 * scale)).floor(),
                ),
              );
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${filtered.length} available ${filtered.length == 1 ? 'voice' : 'voices'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(
                              () => _query = value.trim().toLowerCase(),
                            ),
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Search voices',
                              hintText: 'Name, language, or voice type',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear voice search',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.clear),
                                    ),
                            ),
                          ),
                          if (showFilters) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final label
                                    in widget.onlineOnly
                                        ? ['Online']
                                        : ['All', 'Offline', 'Online'])
                                  ChoiceChip(
                                    label: Text(label),
                                    selected: _connection == label,
                                    onSelected: (_) =>
                                        setState(() => _connection = label),
                                  ),
                              ],
                            ),
                          ],
                          if (_connection == 'Online') ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Online voices are provided by your installed Android TTS engine. You will be asked to confirm before text can be sent to the provider.',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.onlineOnly && widget.voices.isEmpty
                              ? 'No online voices are exposed by your current Android TTS engine. Check device TTS settings, update the engine, then reopen DhebeVoice and refresh voices.'
                              : 'No installed voices match that search.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      sliver: SliverList.builder(
                        itemCount: (filtered.length / columns).ceil(),
                        itemBuilder: (context, row) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (
                                  var column = 0;
                                  column < columns;
                                  column++
                                ) ...[
                                  if (column > 0) const SizedBox(width: 10),
                                  Expanded(
                                    child:
                                        row * columns + column < filtered.length
                                        ? _VoiceCard(
                                            voice:
                                                filtered[row * columns +
                                                    column],
                                            selected:
                                                filtered[row * columns + column]
                                                    .matchesIdentity(
                                                      _pendingVoice?.name,
                                                      _pendingVoice?.locale,
                                                    ),
                                            onTap: () => setState(
                                              () => _pendingVoice =
                                                  filtered[row * columns +
                                                      column],
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: !canSubmit || _savingVoiceType
                        ? null
                        : () => Navigator.pop(context, _pendingVoice),
                    child: const Text('Use voice', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.selected,
    required this.onTap,
  });

  final VoiceModel voice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details = [
      SpeechLocale.label(voice.locale),
      voice.personaDisplayLabel,
      if (voice.userPersonaLabel != null) 'Your label',
      ...voice.metadataLabels.where(
        (label) => !VoiceModel.personaTypes.contains(label),
      ),
    ];
    final title = voice.label;
    return Semantics(
      key: ValueKey('voice_${voice.locale}_${voice.name}'),
      button: true,
      selected: selected,
      label: '${voice.label}, ${details.join(', ')}',
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: [
          'Display name: ${voice.label}',
          'Original voice: ${voice.detailsLabel}',
          ...voice.metadataLabels.where(
            (label) => !VoiceModel.personaTypes.contains(label),
          ),
        ].join('\n'),
        child: Material(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      VoiceAvatar(voice: voice, size: 36),
                      if (selected)
                        Positioned(
                          right: -3,
                          bottom: -3,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: colors.primary,
                            foregroundColor: colors.onPrimary,
                            child: const Icon(Icons.check, size: 13),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          SpeechLocale.label(voice.locale),
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          voice.personaDisplayLabel,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (voice.userPersonaLabel != null)
                          Text('Your label', style: theme.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              voice.requiresNetwork == true
                                  ? Icons.cloud_outlined
                                  : voice.requiresNetwork == false
                                  ? Icons.offline_bolt_outlined
                                  : Icons.graphic_eq,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                voice.requiresNetwork == true
                                    ? 'Online'
                                    : voice.requiresNetwork == false
                                    ? 'Offline'
                                    : 'Device voice',
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
