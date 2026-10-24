import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../devices/application/device_controls_controller.dart';
import '../../devices/presentation/color_utils.dart';
import '../../devices/presentation/device_display.dart';
import '../application/device_calibration_controller.dart';
import '../domain/hue_calibration.dart';

class CalibrationPage extends ConsumerStatefulWidget {
  const CalibrationPage({
    super.key,
    required this.deviceIds,
    required this.protocolId,
    required this.deviceNames,
  });

  final Set<String> deviceIds;
  final String protocolId;
  final List<String> deviceNames;

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage> {
  final TextEditingController _nameController = TextEditingController();
  late final String _previewOperationId;
  List<HueCalibrationAnchor> _anchors = const <HueCalibrationAnchor>[];
  String? _selectedProfileId;
  double? _activeInput;
  bool _initialized = false;
  bool _saving = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final sortedIds = widget.deviceIds.toList()..sort();
    _previewOperationId = 'calibration-preview:${sortedIds.join(',')}';
  }

  @override
  void dispose() {
    ref
        .read(deviceControlsProvider.notifier)
        .cancelReplaceable(_previewOperationId);
    ref.read(deviceCalibrationProvider.notifier).clearPreview(widget.deviceIds);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calibrationState = ref.watch(deviceCalibrationProvider);
    final calibrationController = ref.read(deviceCalibrationProvider.notifier);
    final devices = ref.watch(debugDevicesProvider).devices;
    final profiles = calibrationController.profilesAssignedTo(
      widget.deviceIds,
      protocolId: widget.protocolId,
    );
    if (calibrationState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_initialized) {
      _initialize(profiles.length == 1 ? profiles.single : null);
    }
    final draft = _draft();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Калібрування кольору'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _reset,
            child: const Text('Скинути'),
          ),
          IconButton(
            tooltip: 'Зберегти калібрування',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              '${widget.deviceIds.length} ${_pluralDevice(widget.deviceIds.length)} · ${protocolDisplayName(widget.protocolId)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              widget.deviceNames.join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String?>(
              key: const Key('calibration-profile-dropdown'),
              initialValue: _selectedProfileId,
              decoration: const InputDecoration(
                labelText: 'Почати з калібрування',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Нове калібрування'),
                ),
                ...profiles.map(
                  (profile) => DropdownMenuItem<String?>(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
                ),
              ],
              onChanged: _saving ? null : (id) => _selectProfile(id, profiles),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('calibration-name'),
              controller: _nameController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Назва калібрування',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Бажаний колір → команда стрічці',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Видалити вибрану точку',
                          onPressed:
                              _activeInput == null ||
                                  _activeInput == 0 ||
                                  _activeInput == 1 ||
                                  _saving
                              ? null
                              : _removeActiveAnchor,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Подвійний тап додає точку. Тягніть точку вертикально; під час руху стрічки показують результат.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    CalibrationCurveEditor(
                      key: const Key('calibration-curve'),
                      profile: draft,
                      activeInput: _activeInput,
                      enabled: !_saving,
                      onAnchorsChanged: _setAnchors,
                      onPreviewInput: _previewInput,
                      onActiveInputChanged: (input) {
                        setState(() => _activeInput = input);
                      },
                    ),
                    const SizedBox(height: 8),
                    const _CurveLegend(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PreviewStatus(devices: devices, deviceIds: widget.deviceIds),
            if (_localError != null ||
                calibrationState.error != null) ...<Widget>[
              const SizedBox(height: 12),
              _CalibrationError(
                message: _localError ?? calibrationState.error!,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Зберігається локально на цьому пристрої. Команди BLE та попередній перегляд не підтверджують, що стрічка фізично застосувала значення.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _initialize(HueCalibrationProfile? profile) {
    _initialized = true;
    _selectedProfileId = profile?.id;
    _anchors = (profile ?? _identityDraft()).anchors;
    _nameController.text = profile == null
        ? 'Нове калібрування'
        : 'Копія · ${profile.name}';
    ref
        .read(deviceCalibrationProvider.notifier)
        .preview(appDeviceIds: widget.deviceIds, profile: _draft());
  }

  HueCalibrationProfile _identityDraft() => HueCalibrationProfile.identity(
    id: 'draft',
    name: 'Нове калібрування',
    protocolId: widget.protocolId,
    hueStartDegrees: lotusHueStart,
    hueEndDegrees: lotusHueEnd,
  );

  HueCalibrationProfile _draft() => HueCalibrationProfile(
    id: _selectedProfileId ?? 'draft',
    name: _nameController.text.trim().isEmpty
        ? 'Нове калібрування'
        : _nameController.text.trim(),
    protocolId: widget.protocolId,
    hueStartDegrees: lotusHueStart,
    hueEndDegrees: lotusHueEnd,
    anchors: _anchors,
  );

  void _replaceDraft(HueCalibrationProfile? profile) {
    setState(() {
      _selectedProfileId = profile?.id;
      _anchors = (profile ?? _identityDraft()).anchors;
      _activeInput = null;
      _localError = null;
      _nameController.text = profile == null
          ? 'Нове калібрування'
          : 'Копія · ${profile.name}';
    });
    _previewInput(0.5);
  }

  void _selectProfile(String? id, List<HueCalibrationProfile> profiles) {
    HueCalibrationProfile? profile;
    for (final candidate in profiles) {
      if (candidate.id == id) {
        profile = candidate;
        break;
      }
    }
    _replaceDraft(profile);
  }

  void _setAnchors(List<HueCalibrationAnchor> anchors) {
    setState(() {
      _anchors = anchors;
      _localError = null;
    });
  }

  void _previewInput(double input, {bool commit = false}) {
    final profile = _draft();
    ref
        .read(deviceCalibrationProvider.notifier)
        .preview(appDeviceIds: widget.deviceIds, profile: profile);
    final controls = ref.read(deviceControlsProvider.notifier);
    controls.queueReplaceable(
      operationId: _previewOperationId,
      appDeviceIds: widget.deviceIds,
      command: SetColor(lotusHueColor(input)),
    );
    if (commit) {
      unawaited(controls.flushReplaceable(_previewOperationId));
    }
  }

  void _removeActiveAnchor() {
    final input = _activeInput;
    if (input == null || input == 0 || input == 1) {
      return;
    }
    _setAnchors(
      _anchors.where((anchor) => anchor.input != input).toList(growable: false),
    );
    setState(() => _activeInput = null);
    _previewInput(input, commit: true);
  }

  void _reset() {
    setState(() {
      _selectedProfileId = null;
      _anchors = _identityDraft().anchors;
      _activeInput = null;
      _nameController.text = 'Нове калібрування';
      _localError = null;
    });
    _previewInput(0.5, commit: true);
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _localError = 'Вкажіть назву калібрування.');
      return;
    }
    setState(() {
      _saving = true;
      _localError = null;
    });
    final saved = await ref
        .read(deviceCalibrationProvider.notifier)
        .saveForDevices(appDeviceIds: widget.deviceIds, draft: _draft());
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = false);
  }

  static String _pluralDevice(int value) => switch (value) {
    1 => 'девайс',
    >= 2 && <= 4 => 'девайси',
    _ => 'девайсів',
  };
}

class CalibrationCurveEditor extends StatefulWidget {
  const CalibrationCurveEditor({
    super.key,
    required this.profile,
    required this.activeInput,
    required this.enabled,
    required this.onAnchorsChanged,
    required this.onPreviewInput,
    required this.onActiveInputChanged,
  });

  final HueCalibrationProfile profile;
  final double? activeInput;
  final bool enabled;
  final ValueChanged<List<HueCalibrationAnchor>> onAnchorsChanged;
  final void Function(double input, {bool commit}) onPreviewInput;
  final ValueChanged<double?> onActiveInputChanged;

  @override
  State<CalibrationCurveEditor> createState() => _CalibrationCurveEditorState();
}

class _CalibrationCurveEditorState extends State<CalibrationCurveEditor> {
  Offset? _doubleTapPosition;
  double? _draggingInput;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const height = 246.0;
        final size = Size(constraints.maxWidth, height);
        return SizedBox(
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: widget.enabled
                ? (details) => _doubleTapPosition = details.localPosition
                : null,
            onDoubleTap: widget.enabled ? () => _addAnchor(size) : null,
            onPanStart: widget.enabled
                ? (details) => _startDrag(details.localPosition, size)
                : null,
            onPanUpdate: widget.enabled
                ? (details) => _updateDrag(details.localPosition, size)
                : null,
            onPanEnd: widget.enabled ? (_) => _endDrag() : null,
            onPanCancel: widget.enabled ? _endDrag : null,
            child: CustomPaint(
              painter: _CalibrationCurvePainter(
                anchors: widget.profile.anchors,
                activeInput: widget.activeInput,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }

  void _addAnchor(Size size) {
    final position = _doubleTapPosition;
    if (position == null) {
      return;
    }
    final graph = _graphRect(size);
    final input = _inputAt(position, graph);
    if (widget.profile.anchors.any(
      (anchor) => (anchor.input - input).abs() < .04,
    )) {
      return;
    }
    final anchor = HueCalibrationAnchor(
      input: input,
      output: widget.profile.mapNormalizedHue(input),
    );
    final anchors = <HueCalibrationAnchor>[...widget.profile.anchors, anchor]
      ..sort((left, right) => left.input.compareTo(right.input));
    widget.onAnchorsChanged(anchors);
    widget.onActiveInputChanged(input);
    widget.onPreviewInput(input, commit: true);
  }

  void _startDrag(Offset position, Size size) {
    final graph = _graphRect(size);
    HueCalibrationAnchor? closest;
    var closestDistance = 22.0;
    for (final anchor in widget.profile.anchors) {
      if (anchor.input == 0 || anchor.input == 1) {
        continue;
      }
      final point = _pointFor(anchor, graph);
      final distance = (point - position).distance;
      if (distance <= closestDistance) {
        closest = anchor;
        closestDistance = distance;
      }
    }
    _draggingInput = closest?.input;
    widget.onActiveInputChanged(_draggingInput);
  }

  void _updateDrag(Offset position, Size size) {
    final input = _draggingInput;
    if (input == null) {
      return;
    }
    final index = widget.profile.anchors.indexWhere(
      (anchor) => anchor.input == input,
    );
    if (index < 1 || index >= widget.profile.anchors.length - 1) {
      return;
    }
    final graph = _graphRect(size);
    final lower = widget.profile.anchors[index - 1].output;
    final upper = widget.profile.anchors[index + 1].output;
    final output = _outputAt(position, graph).clamp(lower, upper).toDouble();
    final anchors = List<HueCalibrationAnchor>.of(widget.profile.anchors)
      ..[index] = HueCalibrationAnchor(input: input, output: output);
    widget.onAnchorsChanged(anchors);
    widget.onPreviewInput(input);
  }

  void _endDrag() {
    final input = _draggingInput;
    _draggingInput = null;
    if (input != null) {
      widget.onPreviewInput(input, commit: true);
    }
  }

  static Rect _graphRect(Size size) => Rect.fromLTWH(
    34,
    12,
    math.max(1, size.width - 48),
    math.max(1, size.height - 44),
  );

  static double _inputAt(Offset point, Rect graph) =>
      ((point.dx - graph.left) / graph.width).clamp(0.0, 1.0).toDouble();

  static double _outputAt(Offset point, Rect graph) =>
      (1 - (point.dy - graph.top) / graph.height).clamp(0.0, 1.0).toDouble();

  static Offset _pointFor(HueCalibrationAnchor anchor, Rect graph) => Offset(
    graph.left + graph.width * anchor.input,
    graph.bottom - graph.height * anchor.output,
  );
}

class _CalibrationCurvePainter extends CustomPainter {
  const _CalibrationCurvePainter({required this.anchors, this.activeInput});

  final List<HueCalibrationAnchor> anchors;
  final double? activeInput;

  @override
  void paint(Canvas canvas, Size size) {
    final graph = _CalibrationCurveEditorState._graphRect(size);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..strokeWidth = 1;
    final background = Paint()
      ..color = const Color(0xFF121212)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(graph.inflate(1), const Radius.circular(12)),
      background,
    );
    for (var step = 0; step <= 4; step++) {
      final x = graph.left + graph.width * step / 4;
      final y = graph.top + graph.height * step / 4;
      canvas.drawLine(Offset(x, graph.top), Offset(x, graph.bottom), grid);
      canvas.drawLine(Offset(graph.left, y), Offset(graph.right, y), grid);
    }
    final xPalette = Paint()
      ..shader = LinearGradient(colors: lotusHueGradient).createShader(
        Rect.fromLTWH(graph.left, graph.bottom + 10, graph.width, 8),
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(graph.left, graph.bottom + 10, graph.width, 8),
        const Radius.circular(99),
      ),
      xPalette,
    );
    final yPalette = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: lotusHueGradient,
          ).createShader(
            Rect.fromLTWH(graph.left - 20, graph.top, 8, graph.height),
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(graph.left - 20, graph.top, 8, graph.height),
        const Radius.circular(99),
      ),
      yPalette,
    );

    final path = Path();
    for (var index = 0; index < anchors.length; index++) {
      final point = _CalibrationCurveEditorState._pointFor(
        anchors[index],
        graph,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final anchor in anchors) {
      final selected = anchor.input == activeInput;
      final point = _CalibrationCurveEditorState._pointFor(anchor, graph);
      canvas.drawCircle(
        point,
        selected ? 9 : 7,
        Paint()..color = selected ? Colors.white : const Color(0xFF90CAF9),
      );
      canvas.drawCircle(
        point,
        selected ? 4 : 3,
        Paint()..color = const Color(0xFF121212),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CalibrationCurvePainter oldDelegate) =>
      oldDelegate.anchors != anchors || oldDelegate.activeInput != activeInput;
}

class _CurveLegend extends StatelessWidget {
  const _CurveLegend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Icon(Icons.arrow_right_alt, size: 18),
        SizedBox(width: 4),
        Expanded(
          child: Text('X — обраний в апці від червоного до фіолетового'),
        ),
        Icon(Icons.arrow_upward, size: 18),
        SizedBox(width: 4),
        Expanded(child: Text('Y — колір, що надсилається стрічці')),
      ],
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.devices, required this.deviceIds});

  final Map<String, DebugDevice> devices;
  final Set<String> deviceIds;

  @override
  Widget build(BuildContext context) {
    var connected = 0;
    for (final deviceId in deviceIds) {
      if (devices[deviceId]?.status == DebugDeviceConnectionStatus.connected) {
        connected++;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          connected == 0
              ? 'Підключіть хоча б одну вибрану стрічку для live preview.'
              : 'Live preview: $connected з ${deviceIds.length} підключено.',
        ),
      ),
    );
  }
}

class _CalibrationError extends StatelessWidget {
  const _CalibrationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}
