import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../../../core/macros/triggers/microphone/microphone_mono_audio_trigger.dart';
import '../../../core/macros/triggers/microphone/microphone_pcm_session.dart';
import '../../../core/macros/triggers/multiband_eq/multiband_eq_trigger.dart';
import '../../../core/macros/registry/macro_module_registry.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import '../../groups/domain/lighting_group.dart';
import '../application/macro_library_controller.dart';
import '../application/macro_runtime_session_controller.dart';
import 'macro_graph_definition.dart';
import 'macro_patcher_canvas.dart';
import 'multiband_eq_editor.dart';

/// Edits one versioned Scene Macro graph. It owns only an unsaved draft;
/// persistence, microphone capture and device writes stay in their controllers.
class MacroEditorPage extends ConsumerStatefulWidget {
  const MacroEditorPage({super.key, this.macro});

  final MacroGraph? macro;

  @override
  ConsumerState<MacroEditorPage> createState() => _MacroEditorPageState();
}

class _MacroEditorPageState extends ConsumerState<MacroEditorPage> {
  late MacroGraph _draft;
  late TextEditingController _nameController;
  String? _selectedNodeId;
  String? _error;
  var _saving = false;

  bool get _isNew => widget.macro == null;

  @override
  void initState() {
    super.initState();
    _draft = widget.macro ?? _initialMacro();
    _nameController = TextEditingController(text: _draft.name);
    _selectedNodeId = _draft.nodes.firstOrNull?.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtimeState = ref.watch(macroRuntimeSessionsProvider);
    final status = runtimeState.statusFor(_draft.id);
    final running =
        status?.lifecycle == MacroRuntimeSessionLifecycle.running ||
        status?.lifecycle == MacroRuntimeSessionLifecycle.starting;
    final selectedNode = _nodeById(_selectedNodeId);
    final editorEnabled = !_saving && !running;
    final telemetry = status?.lastTelemetry;
    final devicesState = ref.watch(debugDevicesProvider);
    final groupsState = ref.watch(customGroupsProvider);
    final targetOptions = _targetOptions(
      devices: devicesState.devices.values,
      customGroups: groupsState.groups,
    );
    final microphoneStatus = ref
        .watch(microphoneCaptureStatusProvider)
        .asData
        ?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новий macro' : 'Macro editor'),
        actions: <Widget>[
          IconButton(
            key: const Key('add-macro-node'),
            tooltip: 'Додати вузол',
            onPressed: editorEnabled ? _showNodeMenu : null,
            icon: const Icon(Icons.add_box_outlined),
          ),
          TextButton(
            key: const Key('save-macro'),
            onPressed: editorEnabled ? _save : null,
            child: const Text('Зберегти'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_saving) const LinearProgressIndicator(),
            TextField(
              key: const Key('macro-name'),
              controller: _nameController,
              enabled: editorEnabled,
              decoration: const InputDecoration(
                labelText: 'Назва macro',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            _RuntimeToolbar(
              status: status,
              enabled: !_saving,
              onStart: () => _start(),
              onStop: () => _stop(),
            ),
            if (microphoneStatus != null) ...<Widget>[
              const SizedBox(height: 8),
              _MicrophoneCaptureStatusCard(status: microphoneStatus),
            ],
            if (running) ...<Widget>[
              const SizedBox(height: 8),
              const _EditorHint(
                text:
                    'Зупиніть macro перед редагуванням. Поточний runtime працює з останньою збереженою конфігурацією.',
              ),
            ],
            const SizedBox(height: 20),
            Text('Patcher', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Потягніть з output до input. На touch: торкніться output, потім input. Натисніть cable, щоб прибрати connection.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 460,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: MacroPatcherCanvas(
                  graph: _graphDefinition,
                  selectedNodeId: _selectedNodeId,
                  outputValueLabels: _outputValueLabels(status),
                  onSelectionChanged: (nodeId) =>
                      setState(() => _selectedNodeId = nodeId),
                  onNodeMove: editorEnabled ? _moveNode : null,
                  onConnectionCreate: editorEnabled ? _connectPorts : null,
                  onConnectionRemove: editorEnabled ? _removeEdge : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SelectedNodeInspector(
              node: selectedNode,
              enabled: editorEnabled,
              inputLevelDbfs: telemetry?.inputLevelDbfs,
              spectrumValues: telemetry?.spectrum?.levels ?? const <double>[],
              spectrumFrequenciesHz:
                  telemetry?.spectrum?.frequenciesHz ?? const <double>[],
              onEqChanged: _updateEqConfiguration,
              onRemove: selectedNode == null
                  ? null
                  : () => _removeNode(selectedNode.id),
            ),
            const SizedBox(height: 20),
            _TargetBindingsSection(
              bindings: _draft.targetBindings,
              outputPorts: _targetOutputPorts,
              targetOptions: targetOptions,
              enabled: editorEnabled,
              onAdd: _addBinding,
              onRemove: _removeBinding,
            ),
            const SizedBox(height: 20),
            _MacroDiagnostics(
              status: status,
              recentEvents: runtimeState.recentEvents
                  .where((event) => event.macroId == _draft.id)
                  .toList(growable: false),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              _EditorError(message: _error!),
            ],
            const SizedBox(height: 24),
            const Text(
              'Мікрофонні дані не зберігаються. Spectrum — коротке похідне відображення в пам’яті. “Transmitted” означає лише прийнятий transport write, а не фізичне підтвердження стрічки.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  MacroGraphDefinition get _graphDefinition => MacroGraphDefinition(
    nodes: _draft.nodes,
    edges: _draft.edges,
    layouts: <String, MacroNodeLayout>{
      for (final entry in _draft.editorPositions.entries)
        entry.key: MacroNodeLayout(
          position: Offset(entry.value.x, entry.value.y),
        ),
    },
  );

  Map<String, String> _outputValueLabels(MacroRuntimeSessionStatus? status) {
    final values = status?.outputValues;
    if (values == null || values.isEmpty) return const <String, String>{};
    return Map<String, String>.unmodifiable(
      values.map(
        (portId, value) => MapEntry<String, String>(portId, switch (value) {
          TriggerGateValue(:final value) => value ? 'ON' : 'OFF',
          TriggerLevelValue(:final value) => value.toStringAsFixed(2),
          _ => '',
        }),
      ),
    );
  }

  List<MacroPortDeclaration> get _targetOutputPorts => _draft.nodes
      .expand((node) => node.ports)
      .where(
        (port) =>
            port.direction == MacroPortDirection.output &&
            (port.type == MacroPortType.triggerGate ||
                port.type == MacroPortType.triggerLevel),
      )
      .toList(growable: false);

  List<_MacroTargetOption> _targetOptions({
    required Iterable<DebugDevice> devices,
    required Iterable<CustomLightingGroup> customGroups,
  }) {
    final groups = <LightingTarget>[
      ...protocolGroupTargets(devices),
      ...customGroupTargets(customGroups, devices),
    ];
    return <_MacroTargetOption>[
      ...groups.map(
        (group) => _MacroTargetOption(
          kind: MacroTargetKind.group,
          id: group.id,
          name: group.name,
          detail: '${group.memberDeviceIds.length} девайсів',
        ),
      ),
      ...devices.map(
        (device) => _MacroTargetOption(
          kind: MacroTargetKind.device,
          id: device.appDeviceId,
          name: device.endpoint.displayName ?? device.appDeviceId,
          detail: device.status.name,
        ),
      ),
    ];
  }

  MacroNode? _nodeById(String? id) {
    if (id == null) return null;
    for (final node in _draft.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Future<void> _showNodeMenu() async {
    final kind = await showModalBottomSheet<_NewNodeKind>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.mic_none_outlined),
              title: const Text('Microphone mono audio'),
              subtitle: const Text('Live PCM mono source'),
              onTap: () => Navigator.of(context).pop(_NewNodeKind.microphone),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Multiband EQ'),
              subtitle: const Text('Mono audio → gate or normalized levels'),
              onTap: () => Navigator.of(context).pop(_NewNodeKind.multibandEq),
            ),
          ],
        ),
      ),
    );
    if (!mounted || kind == null) return;
    setState(() {
      final node = switch (kind) {
        _NewNodeKind.microphone => _newMicrophoneNode(),
        _NewNodeKind.multibandEq => _newEqNode(),
      };
      _draft = _draft.copyWith(
        nodes: <MacroNode>[..._draft.nodes, node],
        editorPositions: <String, MacroEditorPosition>{
          ..._draft.editorPositions,
          node.id: MacroEditorPosition(
            x: 56 + ((_draft.nodes.length % 3) * 250),
            y: 80 + ((_draft.nodes.length ~/ 3) * 220),
          ),
        },
      );
      _selectedNodeId = node.id;
      _error = null;
    });
  }

  void _connectPorts(String fromPortId, String toPortId) {
    final source = _portById(fromPortId);
    final destination = _portById(toPortId);
    if (source == null || destination == null) {
      _showError('Один із port-ів більше не існує.');
      return;
    }
    if (source.direction != MacroPortDirection.output ||
        destination.direction != MacroPortDirection.input) {
      _showError('Connection має йти з output до input.');
      return;
    }
    if (source.type != destination.type) {
      _showError('Типи port-ів не сумісні.');
      return;
    }
    if (_draft.edges.any(
      (edge) => edge.fromPortId == fromPortId && edge.toPortId == toPortId,
    )) {
      return;
    }
    if (!destination.acceptsMultipleInputs &&
        _draft.edges.any((edge) => edge.toPortId == toPortId)) {
      _showError('Цей input вже має connection.');
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        edges: <MacroEdge>[
          ..._draft.edges,
          MacroEdge(
            id: const Uuid().v4(),
            fromPortId: fromPortId,
            toPortId: toPortId,
          ),
        ],
      );
      _error = null;
    });
  }

  MacroPortDeclaration? _portById(String portId) {
    for (final port in _draft.nodes.expand((node) => node.ports)) {
      if (port.id == portId) return port;
    }
    return null;
  }

  void _removeEdge(String edgeId) => setState(() {
    _draft = _draft.copyWith(
      edges: _draft.edges.where((edge) => edge.id != edgeId),
    );
  });

  void _moveNode(String nodeId, MacroNodeLayout layout) => setState(() {
    _draft = _draft.copyWith(
      editorPositions: <String, MacroEditorPosition>{
        ..._draft.editorPositions,
        nodeId: MacroEditorPosition(
          x: layout.position.dx,
          y: layout.position.dy,
        ),
      },
    );
  });

  void _removeNode(String nodeId) => setState(() {
    final portIds =
        _nodeById(nodeId)?.ports.map((port) => port.id).toSet() ??
        const <String>{};
    final positions = <String, MacroEditorPosition>{..._draft.editorPositions}
      ..remove(nodeId);
    _draft = _draft.copyWith(
      nodes: _draft.nodes.where((node) => node.id != nodeId),
      edges: _draft.edges.where(
        (edge) =>
            !portIds.contains(edge.fromPortId) &&
            !portIds.contains(edge.toPortId),
      ),
      targetBindings: _draft.targetBindings.where(
        (binding) => !portIds.contains(binding.sourcePortId),
      ),
      editorPositions: positions,
    );
    _selectedNodeId = _draft.nodes.firstOrNull?.id;
  });

  void _updateEqConfiguration(MultibandEqTriggerConfiguration configuration) {
    final selected = _nodeById(_selectedNodeId);
    if (selected == null || selected.kind != multibandEqTriggerKind) return;
    final updated = selected.copyWith(
      parameters: configuration.toNodeParameters(),
      ports: _eqPorts(selected.id, configuration),
    );
    final replacedPortIds = selected.ports.map((port) => port.id).toSet();
    final updatedNodes = _draft.nodes
        .map((node) => node.id == selected.id ? updated : node)
        .toList(growable: false);
    final allPortIds = updatedNodes
        .expand((node) => node.ports)
        .map((port) => port.id)
        .toSet();
    setState(() {
      _draft = _draft.copyWith(
        nodes: updatedNodes,
        edges: _draft.edges.where(
          (edge) =>
              (!replacedPortIds.contains(edge.fromPortId) &&
                  !replacedPortIds.contains(edge.toPortId)) ||
              (allPortIds.contains(edge.fromPortId) &&
                  allPortIds.contains(edge.toPortId)),
        ),
        targetBindings: _draft.targetBindings
            .where(
              (binding) =>
                  !replacedPortIds.contains(binding.sourcePortId) ||
                  allPortIds.contains(binding.sourcePortId),
            )
            .toList(growable: false),
      );
      _error = null;
    });
  }

  Future<void> _addBinding() async {
    final devices = ref.read(debugDevicesProvider).devices.values;
    final customGroups = ref.read(customGroupsProvider).groups;
    final binding = await showDialog<MacroTargetBinding>(
      context: context,
      builder: (_) => _MacroBindingDialog(
        ports: _targetOutputPorts,
        targets: _targetOptions(devices: devices, customGroups: customGroups),
      ),
    );
    if (!mounted || binding == null) return;
    if (_draft.targetBindings.any(
      (current) =>
          current.sourcePortId == binding.sourcePortId &&
          current.targetKind == binding.targetKind &&
          current.targetId == binding.targetId &&
          current.parameter == binding.parameter,
    )) {
      _showError('Такий binding уже є.');
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        targetBindings: <MacroTargetBinding>[..._draft.targetBindings, binding],
      );
      _error = null;
    });
  }

  void _removeBinding(String bindingId) => setState(() {
    _draft = _draft.copyWith(
      targetBindings: _draft.targetBindings.where(
        (binding) => binding.id != bindingId,
      ),
    );
  });

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Вкажіть назву macro.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _draft = _draft.copyWith(name: name);
    });
    final saved = await ref.read(macroLibraryProvider.notifier).save(_draft);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (!saved) {
        _error =
            ref.read(macroLibraryProvider).error ??
            'Не вдалося зберегти macro.';
      }
    });
    if (saved && _isNew && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _start() async {
    if (_isNew) {
      _showError('Спершу збережіть macro.');
      return;
    }
    await ref.read(macroRuntimeSessionsProvider.notifier).start(_draft.id);
  }

  Future<void> _stop() =>
      ref.read(macroRuntimeSessionsProvider.notifier).stop(_draft.id);

  void _showError(String error) => setState(() => _error = error);
}

enum _NewNodeKind { microphone, multibandEq }

MacroGraph _initialMacro() {
  final microphone = _newMicrophoneNode();
  final equalizer = _newEqNode();
  return MacroGraph(
    id: const Uuid().v4(),
    name: 'Microphone lights',
    nodes: <MacroNode>[microphone, equalizer],
    edges: <MacroEdge>[
      MacroEdge(
        id: const Uuid().v4(),
        fromPortId: microphone.ports.single.id,
        toPortId: equalizer.ports.first.id,
      ),
    ],
    editorPositions: <String, MacroEditorPosition>{
      microphone.id: MacroEditorPosition(x: 48, y: 110),
      equalizer.id: MacroEditorPosition(x: 340, y: 110),
    },
  );
}

MacroNode _newMicrophoneNode() {
  final id = const Uuid().v4();
  return MacroNode(
    id: id,
    kind: MicrophoneMonoAudioTriggerFactory.moduleKind,
    displayName: 'Microphone',
    ports: <MacroPortDeclaration>[
      MacroPortDeclaration(
        id: '$id.audio',
        direction: MacroPortDirection.output,
        type: MacroPortType.triggerMonoAudio,
        displayIdentifier: 'microphone.audio',
        displayName: 'Microphone audio',
      ),
    ],
  );
}

MacroNode _newEqNode() {
  final id = const Uuid().v4();
  final configuration = MultibandEqTriggerConfiguration(
    bands: <MultibandEqBandDefinition>[
      MultibandEqBandDefinition(
        id: 'low',
        lowerFrequencyHz: 20,
        upperFrequencyHz: 250,
        mode: MultibandEqBandMode.level,
        normalizationMinimum: multibandEqMinimumDbfs,
        normalizationMaximum: multibandEqMaximumDbfs,
        outputBuffer: const Duration(milliseconds: 50),
      ),
      MultibandEqBandDefinition(
        id: 'mid',
        lowerFrequencyHz: 250,
        upperFrequencyHz: 2000,
        mode: MultibandEqBandMode.level,
        normalizationMinimum: multibandEqMinimumDbfs,
        normalizationMaximum: multibandEqMaximumDbfs,
        outputBuffer: const Duration(milliseconds: 50),
      ),
      MultibandEqBandDefinition(
        id: 'high',
        lowerFrequencyHz: 2000,
        upperFrequencyHz: 8000,
        mode: MultibandEqBandMode.level,
        normalizationMinimum: multibandEqMinimumDbfs,
        normalizationMaximum: multibandEqMaximumDbfs,
        outputBuffer: const Duration(milliseconds: 50),
      ),
    ],
  );
  return MacroNode(
    id: id,
    kind: multibandEqTriggerKind,
    displayName: 'Multiband EQ',
    ports: _eqPorts(id, configuration),
    parameters: configuration.toNodeParameters(),
  );
}

List<MacroPortDeclaration> _eqPorts(
  String nodeId,
  MultibandEqTriggerConfiguration configuration,
) => <MacroPortDeclaration>[
  MacroPortDeclaration(
    id: '$nodeId.audio',
    direction: MacroPortDirection.input,
    type: MacroPortType.triggerMonoAudio,
    displayIdentifier: 'audio',
    displayName: 'Mono audio',
  ),
  for (final band in configuration.bands)
    MacroPortDeclaration(
      id: '$nodeId.band.${band.id}',
      direction: MacroPortDirection.output,
      type: band.mode == MultibandEqBandMode.gate
          ? MacroPortType.triggerGate
          : MacroPortType.triggerLevel,
      displayIdentifier: 'band.${band.id}',
      displayName: band.id,
    ),
];

class _RuntimeToolbar extends StatelessWidget {
  const _RuntimeToolbar({
    required this.status,
    required this.enabled,
    required this.onStart,
    required this.onStop,
  });
  final MacroRuntimeSessionStatus? status;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final lifecycle = status?.lifecycle;
    final running =
        lifecycle == MacroRuntimeSessionLifecycle.running ||
        lifecycle == MacroRuntimeSessionLifecycle.starting;
    final label = switch (lifecycle) {
      MacroRuntimeSessionLifecycle.running => 'Running',
      MacroRuntimeSessionLifecycle.starting => 'Starting',
      MacroRuntimeSessionLifecycle.invalid => 'Needs repair',
      MacroRuntimeSessionLifecycle.error => 'Error',
      MacroRuntimeSessionLifecycle.stopped => 'Stopped',
      _ => 'Not running',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(running ? Icons.play_circle_fill : Icons.pause_circle_outline),
            const SizedBox(width: 8),
            Expanded(child: Text('Runtime: $label')),
            if (running)
              OutlinedButton.icon(
                key: const Key('stop-macro-runtime'),
                onPressed: enabled ? onStop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              )
            else
              FilledButton.icon(
                key: const Key('start-macro-runtime'),
                onPressed: enabled ? onStart : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MicrophoneCaptureStatusCard extends StatelessWidget {
  const _MicrophoneCaptureStatusCard({required this.status});

  final MicrophoneCaptureStatus status;

  @override
  Widget build(BuildContext context) {
    final isError =
        status.state == MicrophoneCaptureState.permissionDenied ||
        status.state == MicrophoneCaptureState.error;
    final label = switch (status.state) {
      MicrophoneCaptureState.requestingPermission =>
        'Запит дозволу до мікрофона',
      MicrophoneCaptureState.starting => 'Запуск мікрофона',
      MicrophoneCaptureState.streaming => 'Мікрофон передає mono PCM',
      MicrophoneCaptureState.stopping => 'Зупинка мікрофона',
      MicrophoneCaptureState.stopped => 'Мікрофон зупинено',
      MicrophoneCaptureState.permissionDenied =>
        'Доступ до мікрофона відхилено',
      MicrophoneCaptureState.error => 'Помилка мікрофона',
      MicrophoneCaptureState.disposed => 'Мікрофонний сеанс завершено',
      MicrophoneCaptureState.idle => 'Мікрофон очікує запуску',
    };
    return Card(
      color: isError ? Theme.of(context).colorScheme.errorContainer : null,
      child: ListTile(
        leading: Icon(
          isError ? Icons.mic_off_outlined : Icons.mic_none_outlined,
        ),
        title: Text(label),
        subtitle: status.error == null ? null : Text('${status.error}'),
      ),
    );
  }
}

class _SelectedNodeInspector extends StatelessWidget {
  const _SelectedNodeInspector({
    required this.node,
    required this.enabled,
    required this.inputLevelDbfs,
    required this.spectrumValues,
    required this.spectrumFrequenciesHz,
    required this.onEqChanged,
    required this.onRemove,
  });
  final MacroNode? node;
  final bool enabled;
  final double? inputLevelDbfs;
  final List<double> spectrumValues;
  final List<double> spectrumFrequenciesHz;
  final ValueChanged<MultibandEqTriggerConfiguration> onEqChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final current = node;
    if (current == null) {
      return const _EditorHint(
        text: 'Оберіть вузол у patcher, щоб налаштувати його.',
      );
    }
    if (current.kind == multibandEqTriggerKind) {
      try {
        final configuration =
            MultibandEqTriggerConfiguration.fromNodeParameters(
              current.parameters,
            );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(child: Text('Node inspector')),
                    IconButton(
                      tooltip: 'Видалити вузол',
                      onPressed: enabled ? onRemove : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                MultibandEqEditor(
                  configuration: configuration,
                  spectrumValues: spectrumValues,
                  spectrumFrequenciesHz: spectrumFrequenciesHz,
                  enabled: enabled,
                  onChanged: onEqChanged,
                ),
              ],
            ),
          ),
        );
      } on FormatException catch (error) {
        return _EditorError(message: 'EQ configuration needs repair: $error');
      }
    }
    if (current.kind == MicrophoneMonoAudioTriggerFactory.moduleKind) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.mic_none_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text(current.displayName ?? current.kind)),
                  IconButton(
                    tooltip: 'Видалити вузол',
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Microphone input is transient and is not written to files.',
              ),
              const SizedBox(height: 12),
              _MicrophoneDbMeter(dbfs: inputLevelDbfs),
            ],
          ),
        ),
      );
    }
    return Card(
      child: ListTile(
        title: Text(current.displayName ?? current.kind),
        trailing: IconButton(
          tooltip: 'Видалити вузол',
          onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

/// A UI-only dBFS meter. The runtime reports a bounded RMS snapshot and this
/// widget only maps it to pixels; it never receives or retains audio samples.
class _MicrophoneDbMeter extends StatelessWidget {
  const _MicrophoneDbMeter({required this.dbfs});

  final double? dbfs;

  @override
  Widget build(BuildContext context) {
    final value = dbfs;
    final label = value == null
        ? 'Очікування аудіо'
        : '${value.toStringAsFixed(1)} dBFS';
    return Semantics(
      label: 'Microphone input level: $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Input level',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 6),
          RepaintBoundary(
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: CustomPaint(painter: _MicrophoneDbMeterPainter(value)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicrophoneDbMeterPainter extends CustomPainter {
  const _MicrophoneDbMeterPainter(this.dbfs);

  final double? dbfs;

  static const _minimumDbfs = -72.0;

  @override
  void paint(Canvas canvas, Size size) {
    const labelSpace = 17.0;
    final meter = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - labelSpace),
      const Radius.circular(8),
    );
    canvas.drawRRect(meter, Paint()..color = const Color(0xFF181825));
    final active = dbfs?.clamp(_minimumDbfs, 0.0).toDouble();
    if (active != null) {
      final width = size.width * ((active - _minimumDbfs) / -_minimumDbfs);
      final activeMeter = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, size.height - labelSpace),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        activeMeter,
        Paint()
          ..shader = const LinearGradient(
            colors: <Color>[
              Color(0xFF89B4FA),
              Color(0xFFA6E3A1),
              Color(0xFFF9E2AF),
              Color(0xFFF38BA8),
            ],
          ).createShader(meter.outerRect),
      );
      final x = width.clamp(1.0, size.width - 1.0).toDouble();
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height - labelSpace),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }
    final tickPaint = Paint()
      ..color = const Color(0xFFBAC2DE)
      ..strokeWidth = 1;
    for (final tick in <int>[-72, -60, -48, -36, -24, -12, 0]) {
      final x = size.width * ((tick - _minimumDbfs) / -_minimumDbfs);
      canvas.drawLine(
        Offset(x, size.height - labelSpace),
        Offset(x, size.height - labelSpace + 4),
        tickPaint,
      );
      final text = TextPainter(
        text: TextSpan(
          text: '$tick',
          style: const TextStyle(color: Color(0xFFBAC2DE), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(
          (x - text.width / 2).clamp(0.0, size.width - text.width),
          size.height - 12,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MicrophoneDbMeterPainter oldDelegate) =>
      oldDelegate.dbfs != dbfs;
}

class _TargetBindingsSection extends StatelessWidget {
  const _TargetBindingsSection({
    required this.bindings,
    required this.outputPorts,
    required this.targetOptions,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });
  final List<MacroTargetBinding> bindings;
  final List<MacroPortDeclaration> outputPorts;
  final List<_MacroTargetOption> targetOptions;
  final bool enabled;
  final Future<void> Function() onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Target bindings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            key: const Key('add-macro-binding'),
            onPressed:
                enabled && outputPorts.isNotEmpty && targetOptions.isNotEmpty
                ? () => unawaited(onAdd())
                : null,
            icon: const Icon(Icons.add_link),
            label: const Text('Binding'),
          ),
        ],
      ),
      const Text('Gate керує power; normalized level керує brightness.'),
      const SizedBox(height: 8),
      if (bindings.isEmpty)
        const _EditorHint(
          text: 'Ще немає bindings. Підключіть EQ band до групи або девайса.',
        )
      else
        ...bindings.map((binding) {
          final port = outputPorts
              .where((port) => port.id == binding.sourcePortId)
              .firstOrNull;
          final target = targetOptions
              .where(
                (option) =>
                    option.kind == binding.targetKind &&
                    option.id == binding.targetId,
              )
              .firstOrNull;
          return Card(
            child: ListTile(
              key: ValueKey<String>('macro-binding-${binding.id}'),
              leading: Icon(
                binding.targetKind == MacroTargetKind.group
                    ? Icons.group_outlined
                    : Icons.devices_outlined,
              ),
              title: Text(
                target?.name ?? 'Missing target: ${binding.targetId}',
              ),
              subtitle: Text(
                '${port?.displayName ?? 'Missing port'} → ${binding.parameter.name}'
                '${target == null ? ' · needs repair' : ''}',
              ),
              trailing: IconButton(
                tooltip: 'Прибрати binding',
                onPressed: enabled ? () => onRemove(binding.id) : null,
                icon: const Icon(Icons.link_off),
              ),
            ),
          );
        }),
    ],
  );
}

class _MacroBindingDialog extends StatefulWidget {
  const _MacroBindingDialog({required this.ports, required this.targets});
  final List<MacroPortDeclaration> ports;
  final List<_MacroTargetOption> targets;

  @override
  State<_MacroBindingDialog> createState() => _MacroBindingDialogState();
}

class _MacroBindingDialogState extends State<_MacroBindingDialog> {
  late MacroPortDeclaration _port;
  late _MacroTargetOption _target;

  @override
  void initState() {
    super.initState();
    _port = widget.ports.first;
    _target = widget.targets.first;
  }

  @override
  Widget build(BuildContext context) {
    final parameter = _port.type == MacroPortType.triggerGate
        ? MacroTargetParameter.power
        : MacroTargetParameter.brightness;
    return AlertDialog(
      title: const Text('Новий target binding'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<MacroPortDeclaration>(
            initialValue: _port,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Output',
              border: OutlineInputBorder(),
            ),
            items: widget.ports
                .map(
                  (port) => DropdownMenuItem(
                    value: port,
                    child: Text(
                      '${port.displayName ?? port.displayIdentifier} · ${port.type.name}',
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (port) => setState(() => _port = port!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_MacroTargetOption>(
            initialValue: _target,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Group or device',
              border: OutlineInputBorder(),
            ),
            items: widget.targets
                .map(
                  (target) => DropdownMenuItem(
                    value: target,
                    child: Text('${target.name} · ${target.detail}'),
                  ),
                )
                .toList(growable: false),
            onChanged: (target) => setState(() => _target = target!),
          ),
          const SizedBox(height: 10),
          Text('Parameter: ${parameter.name}'),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            MacroTargetBinding(
              id: const Uuid().v4(),
              sourcePortId: _port.id,
              targetKind: _target.kind,
              targetId: _target.id,
              parameter: parameter,
            ),
          ),
          child: const Text('Додати'),
        ),
      ],
    );
  }
}

class _MacroTargetOption {
  const _MacroTargetOption({
    required this.kind,
    required this.id,
    required this.name,
    required this.detail,
  });
  final MacroTargetKind kind;
  final String id;
  final String name;
  final String detail;
}

class _MacroDiagnostics extends StatelessWidget {
  const _MacroDiagnostics({required this.status, required this.recentEvents});
  final MacroRuntimeSessionStatus? status;
  final List<MacroRuntimeSessionEvent> recentEvents;

  @override
  Widget build(BuildContext context) {
    final issues =
        status?.validationIssues ?? const <MacroGraphValidationIssue>[];
    final delivery = status?.lastDelivery;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Runtime diagnostics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (issues.isNotEmpty)
              ...issues.map((issue) => Text('• ${issue.message}'))
            else if (delivery != null)
              Text(
                '${delivery.outcome.name}: ${delivery.detail ?? delivery.appDeviceId}',
              )
            else
              const Text('Ще немає runtime events.'),
            if (status?.error != null) ...<Widget>[
              const SizedBox(height: 6),
              Text('Error: ${status!.error}'),
            ],
            if (recentEvents.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Останні події: ${recentEvents.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditorHint extends StatelessWidget {
  const _EditorHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
  );
}

class _EditorError extends StatelessWidget {
  const _EditorError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
  );
}
