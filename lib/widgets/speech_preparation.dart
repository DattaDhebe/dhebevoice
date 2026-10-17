import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_handler_controller.dart';
import '../services/tts_service.dart';
import 'playback_status.dart';

/// Lives on the home route, so buffering in Settings can use the same navigator.
class SpeechPreparationCoordinator extends StatefulWidget {
  const SpeechPreparationCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<SpeechPreparationCoordinator> createState() =>
      _SpeechPreparationCoordinatorState();
}

class _SpeechPreparationCoordinatorState
    extends State<SpeechPreparationCoordinator>
    with WidgetsBindingObserver {
  TtsService? _service;
  Timer? _timer;
  DialogRoute<void>? _route;
  (int, int, bool)? _pending;
  (int, int, bool)? _dismissed;
  bool _resumed = true;

  (int, int, bool) get _attempt => (
    _service!.playbackSessionId,
    _service!.preparationSequence,
    _service!.isAdvancingChapter,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<TtsService>();
    if (!identical(service, _service)) {
      _service?.removeListener(_synchronize);
      _service = service..addListener(_synchronize);
      _synchronize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _synchronize();
  }

  void _afterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _synchronize() {
    if (!mounted) return;
    if (!_resumed || !_service!.isBuffering) {
      _timer?.cancel();
      _pending = null;
      if (_route != null) _afterFrame(_close);
      return;
    }
    final attempt = _attempt;
    if (_route != null ||
        _dismissed == attempt ||
        (_pending == attempt && _timer?.isActive == true)) {
      return;
    }
    _timer?.cancel();
    _pending = attempt;
    // Cached/quick segment handoffs should not flash a modal on every paragraph.
    _timer = Timer(
      const Duration(milliseconds: 700),
      () => _afterFrame(() {
        if (_resumed &&
            _service!.isBuffering &&
            _attempt == attempt &&
            _dismissed != attempt &&
            _route == null) {
          _show(attempt);
        }
      }),
    );
  }

  void _show((int, int, bool) attempt) {
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => SpeechPreparationDialog(
        service: _service!,
        onHide: _hide,
        onStop: () {
          final handler = context.read<AudioHandlerController>().audioHandler;
          unawaited(handler == null ? _service!.stop() : handler.stop());
        },
      ),
    );
    _route = route;
    Navigator.of(context, rootNavigator: true).push(route).then((_) {
      if (!mounted || !identical(_route, route)) return;
      _route = null;
      if (_service!.isBuffering) _dismissed = _attempt;
    });
  }

  void _hide() {
    _dismissed = _attempt;
    _close();
  }

  void _close() {
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      route.navigator?.pop();
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _service?.removeListener(_synchronize);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SpeechPreparationDialog extends StatelessWidget {
  const SpeechPreparationDialog({
    super.key,
    required this.service,
    required this.onHide,
    required this.onStop,
  });

  final TtsService service;
  final VoidCallback onHide;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          Expanded(child: Text(service.preparationTitle)),
          IconButton(
            tooltip: 'Hide preparation',
            onPressed: onHide,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectedVoiceLabel(service: service),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: service.preparationProgress,
              semanticsLabel: service.preparationStages ?? 'Speech preparation',
            ),
            const SizedBox(height: 14),
            Text(
              service.preparationMessage,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (service.preparationStages != null) ...[
              const SizedBox(height: 6),
              Text(
                service.preparationStages!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Playback starts automatically when audio is ready. Hide keeps preparing; Stop cancels it. Progress stays visible in the player.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onHide, child: const Text('Hide')),
        FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Stop'),
        ),
      ],
    ),
  );
}
