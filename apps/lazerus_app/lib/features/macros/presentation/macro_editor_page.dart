import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../../../core/macros/modifiers/color/color_modifier.dart';
import '../../../core/macros/modifiers/color_brightness_combine/color_brightness_combine_modifier.dart';
import '../../../core/macros/triggers/microphone/microphone_mono_audio_trigger.dart';
import '../../../core/macros/triggers/multiband_eq/multiband_eq_trigger.dart';
import '../../../core/macros/sinks/lighting_target_sink.dart';
import '../../control/presentation/compact_control_card.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/group_targets.dart';
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
  static const _liveUpdateDebounce = Duration(milliseconds: 120);

  late MacroGraph _draft;
  late TextEditingController _nameController;
  String? _selectedNodeId;
  String? _error;
  var _saving = false;
  Timer? _runtimeUpdateTimer;
  var _runtimeUpdateInFlight = false;
  var _runtimeUpdateQueued = false;
  var _draftRevision = 0;
  var _stoppingForExit = false;
  final GlobalKey _patcherDropKey = GlobalKey();

  bool get _isNew => widget.macro == null;

  @override
  void initState() {
    super.initState();
    _draft = _migrateLegacyBindings(widget.macro ?? _initialMacro());
    _nameController = TextEditingController(text: _draft.name);
    _selectedNodeId = _draft.nodes.firstOrNull?.id;
  }

  @override
  void dispose() {
    _runtimeUpdateTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtimeState = ref.watch(macroRuntimeSessionsProvider);
    final status = runtimeState.statusFor(_draft.id);
    final running =
        status?.lifecycle == MacroRuntimeSessionLifecycle.running || status?.lifecycle == MacroRuntimeSessionLifecycle.starting;
    final selectedNode = _nodeById(_selectedNodeId);
    final editorEnabled = !_saving;
    final telemetry = status?.lastTelemetry;
    final devicesState = ref.watch(debugDevicesProvider);

    return PopScope<void>(
      canPop: !running && !_stoppingForExit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _stoppingForExit) return;
        unawaited(_stopRuntimeThenExit());
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (!_saving) unawaited(_save());
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_isNew ? 'Новий macro' : 'Macro editor'),
              actionsPadding: EdgeInsets.symmetric(horizontal: 16.0),
              actions: <Widget>[
                _RuntimeControl(status: status, enabled: !_saving, onStart: () => _start(), onStop: () => _stop()),
                const SizedBox(width: 8.0),
                IconButton.filledTonal(
                  key: const Key('save-macro'),
                  onPressed: editorEnabled ? _save : null,
                  icon: const Icon(Icons.save),
                  tooltip: 'Save',
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
                    decoration: const InputDecoration(labelText: 'Назва macro', border: OutlineInputBorder()),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8.0,
                    children: [
                      Flexible(child: Text('Patcher', style: Theme.of(context).textTheme.titleMedium)),
                      Tooltip(
                        message:
                            'Клікніть port, перемістіть курсор і клікніть інший port, щоб створити connection. Клік по підʼєднаному port відʼєднує wire для перепідключення.',
                        child: Icon(Icons.info_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 500,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: 228,
                          child: _MacroPalette(
                            devices: devicesState.sortedDevices,
                            enabled: editorEnabled,
                            onAdd: _addPaletteItem,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DragTarget<_MacroPaletteItem>(
                            key: _patcherDropKey,
                            onWillAcceptWithDetails: (_) => editorEnabled,
                            onAcceptWithDetails: (details) => _addPaletteItem(details.data, _dropPositionFor(details.offset)),
                            builder: (context, candidate, rejected) => Card(
                              clipBehavior: Clip.antiAlias,
                              color: candidate.isNotEmpty ? Theme.of(context).colorScheme.primaryContainer : null,
                              child: MacroPatcherCanvas(
                                graph: _graphDefinition,
                                selectedNodeId: _selectedNodeId,
                                outputValueLabels: _outputValueLabels(status),
                                nodeBodyBuilder: _nodeBodyBuilder(editorEnabled),
                                nodeBodyHeight: (node) => node.kind == colorModifierKind ? 54 : 0,
                                onSelectionChanged: (nodeId) => setState(() => _selectedNodeId = nodeId),
                                onNodeMove: editorEnabled ? _moveNode : null,
                                onConnectionCreate: editorEnabled ? _connectPorts : null,
                                onConnectionRemove: editorEnabled ? _removeEdge : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SelectedNodeInspector(
                    node: selectedNode,
                    enabled: editorEnabled,
                    devices: devicesState.devices,
                    inputDrivenFeatures: _inputDrivenFeatures(selectedNode, status),
                    inputLevelDbfs: telemetry?.inputLevelDbfs,
                    spectrumValues: telemetry?.spectrum?.levels ?? const <double>[],
                    spectrumFrequenciesHz: telemetry?.spectrum?.frequenciesHz ?? const <double>[],
                    onEqChanged: _updateEqConfiguration,
                    onRemove: selectedNode == null ? null : () => _removeNode(selectedNode.id),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...<Widget>[const SizedBox(height: 16), _EditorError(message: _error!)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  MacroGraphDefinition get _graphDefinition => MacroGraphDefinition(
    nodes: _draft.nodes,
    edges: _draft.edges,
    layouts: <String, MacroNodeLayout>{
      for (final entry in _draft.editorPositions.entries)
        entry.key: MacroNodeLayout(position: Offset(entry.value.x, entry.value.y)),
    },
  );

  bool get _hasLiveRuntime {
    final lifecycle = ref.read(macroRuntimeSessionsProvider).statusFor(_draft.id)?.lifecycle;
    return lifecycle == MacroRuntimeSessionLifecycle.running || lifecycle == MacroRuntimeSessionLifecycle.starting;
  }

  /// Coalesces high-frequency editor updates (notably the colour picker) into
  /// one runtime replacement. The macro file is deliberately not written here:
  /// runtime state follows the current draft, while Save/⌘S remains explicit.
  void _markRuntimeDefinitionChanged() {
    _draftRevision++;
    if (!_hasLiveRuntime) return;
    _runtimeUpdateTimer?.cancel();
    _runtimeUpdateTimer = Timer(_liveUpdateDebounce, () => unawaited(_applyLiveRuntimeUpdate()));
  }

  Future<void> _applyLiveRuntimeUpdate() async {
    if (!mounted || !_hasLiveRuntime) return;
    if (_runtimeUpdateInFlight) {
      _runtimeUpdateQueued = true;
      return;
    }
    _runtimeUpdateInFlight = true;
    final appliedRevision = _draftRevision;
    await ref.read(macroRuntimeSessionsProvider.notifier).updateRunning(_draft);
    if (!mounted) return;
    _runtimeUpdateInFlight = false;
    if (_runtimeUpdateQueued || _draftRevision != appliedRevision) {
      _runtimeUpdateQueued = false;
      unawaited(_applyLiveRuntimeUpdate());
    }
  }

  Map<String, String> _outputValueLabels(MacroRuntimeSessionStatus? status) {
    final values = status?.outputValues;
    if (values == null || values.isEmpty) return const <String, String>{};
    return Map<String, String>.unmodifiable(
      values.map(
        (portId, value) => MapEntry<String, String>(portId, switch (value) {
          TriggerGateValue(:final value) => value ? 'ON' : 'OFF',
          TriggerLevelValue(:final value) => value.toStringAsFixed(2),
          TriggerHsvValue(:final hue) => 'H ${hue.round()}°',
          _ => '',
        }),
      ),
    );
  }

  /// A device card remains manually controllable until a connected input has
  /// emitted an actual runtime value. From that point the incoming signal owns
  /// that parameter for this macro run, rather than merely reserving a port.
  Set<LightingFeature> _inputDrivenFeatures(MacroNode? node, MacroRuntimeSessionStatus? status) {
    if (node == null || node.kind != lightingTargetSinkKind) {
      return const <LightingFeature>{};
    }
    final outputValues = status?.outputValues ?? const <String, TriggerValue>{};
    if (outputValues.isEmpty) return const <LightingFeature>{};
    try {
      final configuration = LightingTargetNodeConfiguration.fromNode(node);
      if (configuration.targetKind != MacroTargetKind.device) {
        return const <LightingFeature>{};
      }
      final features = <LightingFeature>{};
      for (final parameter in configuration.parameters) {
        final inputPortId = '${node.id}.${parameter.name}';
        final hasValue = _draft.edges.any((edge) => edge.toPortId == inputPortId && outputValues.containsKey(edge.fromPortId));
        if (!hasValue) continue;
        features.add(switch (parameter) {
          MacroTargetParameter.power => LightingFeature.power,
          MacroTargetParameter.brightness => LightingFeature.brightness,
          MacroTargetParameter.color => LightingFeature.rgb,
        });
      }
      return Set<LightingFeature>.unmodifiable(features);
    } on FormatException {
      return const <LightingFeature>{};
    }
  }

  Widget? Function(BuildContext, MacroNode) _nodeBodyBuilder(bool enabled) => (context, node) {
    if (node.kind != colorModifierKind) return null;
    try {
      final configuration = ColorModifierConfiguration.fromNodeParameters(node.parameters);
      return _CompactHuePicker(
        hue: configuration.hue,
        enabled: enabled,
        onChanged: (hue) => _updateColorConfiguration(
          node.id,
          ColorModifierConfiguration(hue: hue, saturation: configuration.saturation, value: configuration.value),
        ),
      );
    } on FormatException {
      return const Text('Color configuration needs repair.');
    }
  };

  Offset? _dropPositionFor(Offset globalPosition) {
    final box = _patcherDropKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPosition);
    return Offset((local.dx - 112).clamp(20, 1300).toDouble(), (local.dy - 22).clamp(20, 900).toDouble());
  }

  void _addPaletteItem(_MacroPaletteItem item, [Offset? position]) {
    final node = switch (item.kind) {
      _NewNodeKind.microphone => _newMicrophoneNode(),
      _NewNodeKind.multibandEq => _newEqNode(),
      _NewNodeKind.color => _newColorNode(),
      _NewNodeKind.colorBrightnessCombine => _newColorBrightnessCombineNode(),
      null => _newDeviceTargetNode(item.device!),
    };
    if (node == null) {
      _showError('У девайса ще немає відомих macro-capabilities. Підключіть його та повторіть.');
      return;
    }
    final fallbackPosition = Offset(56 + ((_draft.nodes.length % 3) * 250), 80 + ((_draft.nodes.length ~/ 3) * 220));
    setState(() {
      _draft = _withDerivedBindings(
        _draft.copyWith(
          nodes: <MacroNode>[..._draft.nodes, node],
          editorPositions: <String, MacroEditorPosition>{
            ..._draft.editorPositions,
            node.id: MacroEditorPosition(x: (position ?? fallbackPosition).dx, y: (position ?? fallbackPosition).dy),
          },
        ),
      );
      _selectedNodeId = node.id;
      _error = null;
    });
    _markRuntimeDefinitionChanged();
  }

  MacroNode? _nodeById(String? id) {
    if (id == null) return null;
    for (final node in _draft.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  void _connectPorts(String fromPortId, String toPortId) {
    final source = _portById(fromPortId);
    final destination = _portById(toPortId);
    if (source == null || destination == null) {
      _showError('Один із port-ів більше не існує.');
      return;
    }
    if (source.direction != MacroPortDirection.output || destination.direction != MacroPortDirection.input) {
      _showError('Connection має йти з output до input.');
      return;
    }
    if (source.type != destination.type) {
      _showError('Типи port-ів не сумісні.');
      return;
    }
    if (_draft.edges.any((edge) => edge.fromPortId == fromPortId && edge.toPortId == toPortId)) {
      return;
    }
    if (!destination.acceptsMultipleInputs && _draft.edges.any((edge) => edge.toPortId == toPortId)) {
      _showError('Цей input вже має connection.');
      return;
    }
    setState(() {
      _draft = _withDerivedBindings(
        _draft.copyWith(
          edges: <MacroEdge>[
            ..._draft.edges,
            MacroEdge(id: const Uuid().v4(), fromPortId: fromPortId, toPortId: toPortId),
          ],
        ),
      );
      _error = null;
    });
    _markRuntimeDefinitionChanged();
  }

  MacroPortDeclaration? _portById(String portId) {
    for (final port in _draft.nodes.expand((node) => node.ports)) {
      if (port.id == portId) return port;
    }
    return null;
  }

  void _removeEdge(String edgeId) {
    setState(() {
      _draft = _withDerivedBindings(_draft.copyWith(edges: _draft.edges.where((edge) => edge.id != edgeId)));
    });
    _markRuntimeDefinitionChanged();
  }

  void _moveNode(String nodeId, MacroNodeLayout layout) => setState(() {
    _draft = _draft.copyWith(
      editorPositions: <String, MacroEditorPosition>{
        ..._draft.editorPositions,
        nodeId: MacroEditorPosition(x: layout.position.dx, y: layout.position.dy),
      },
    );
  });

  void _removeNode(String nodeId) {
    setState(() {
      final portIds = _nodeById(nodeId)?.ports.map((port) => port.id).toSet() ?? const <String>{};
      final positions = <String, MacroEditorPosition>{..._draft.editorPositions}..remove(nodeId);
      _draft = _withDerivedBindings(
        _draft.copyWith(
          nodes: _draft.nodes.where((node) => node.id != nodeId),
          edges: _draft.edges.where((edge) => !portIds.contains(edge.fromPortId) && !portIds.contains(edge.toPortId)),
          editorPositions: positions,
        ),
      );
      _selectedNodeId = _draft.nodes.firstOrNull?.id;
    });
    _markRuntimeDefinitionChanged();
  }

  void _updateEqConfiguration(MultibandEqTriggerConfiguration configuration) {
    final selected = _nodeById(_selectedNodeId);
    if (selected == null || selected.kind != multibandEqTriggerKind) return;
    final updated = selected.copyWith(parameters: configuration.toNodeParameters(), ports: _eqPorts(selected.id, configuration));
    final replacedPortIds = selected.ports.map((port) => port.id).toSet();
    final updatedNodes = _draft.nodes.map((node) => node.id == selected.id ? updated : node).toList(growable: false);
    final allPortIds = updatedNodes.expand((node) => node.ports).map((port) => port.id).toSet();
    setState(() {
      _draft = _withDerivedBindings(
        _draft.copyWith(
          nodes: updatedNodes,
          edges: _draft.edges.where(
            (edge) =>
                (!replacedPortIds.contains(edge.fromPortId) && !replacedPortIds.contains(edge.toPortId)) ||
                (allPortIds.contains(edge.fromPortId) && allPortIds.contains(edge.toPortId)),
          ),
        ),
      );
      _error = null;
    });
    _markRuntimeDefinitionChanged();
  }

  void _updateColorConfiguration(String nodeId, ColorModifierConfiguration configuration) {
    setState(() {
      _draft = _withDerivedBindings(
        _draft.copyWith(
          nodes: _draft.nodes
              .map(
                (node) => node.id == nodeId
                    ? node.copyWith(
                        parameters: configuration.toNodeParameters(),
                        ports: ColorModifierFactory.portsForNode(node.id),
                      )
                    : node,
              )
              .toList(growable: false),
        ),
      );
      _error = null;
    });
    _markRuntimeDefinitionChanged();
  }

  /// Derives portable lighting intents from graph edges that terminate at an
  /// input-only target node. The persisted binding is still the runtime
  /// delivery contract, while the editor exposes it only through the patcher.
  MacroGraph _withDerivedBindings(MacroGraph graph) => graph.copyWith(targetBindings: _deriveTargetBindings(graph));

  List<MacroTargetBinding> _deriveTargetBindings(MacroGraph graph) {
    final nodesByInputPort = <String, _TargetInput>{};
    for (final node in graph.nodes) {
      if (node.kind != lightingTargetSinkKind) continue;
      try {
        final configuration = LightingTargetNodeConfiguration.fromNode(node);
        for (final parameter in configuration.parameters) {
          nodesByInputPort['${node.id}.${parameter.name}'] = _TargetInput(
            targetKind: configuration.targetKind,
            targetId: configuration.targetId,
            parameter: parameter,
          );
        }
      } on FormatException {
        // The graph validator reports malformed sink configuration as a
        // repairable node-contract issue. Do not manufacture a runtime target.
      }
    }
    return graph.edges
        .map((edge) {
          final target = nodesByInputPort[edge.toPortId];
          if (target == null) return null;
          return MacroTargetBinding(
            id: 'target-edge-${edge.id}',
            sourcePortId: edge.fromPortId,
            targetKind: target.targetKind,
            targetId: target.targetId,
            parameter: target.parameter,
          );
        })
        .whereType<MacroTargetBinding>()
        .toList(growable: false);
  }

  /// Keeps older macro JSON editable after the binding form was replaced by
  /// physical target nodes. Existing target edges are left intact; only legacy
  /// bindings with no corresponding edge gain a sink node and connection.
  MacroGraph _migrateLegacyBindings(MacroGraph graph) {
    final existingKeys = _deriveTargetBindings(graph).map(_bindingKey).toSet();
    final legacy = graph.targetBindings.where((binding) => !existingKeys.contains(_bindingKey(binding))).toList(growable: false);
    if (legacy.isEmpty) return _withDerivedBindings(graph);

    final nodes = <MacroNode>[...graph.nodes];
    final edges = <MacroEdge>[...graph.edges];
    final positions = <String, MacroEditorPosition>{...graph.editorPositions};
    for (final binding in legacy) {
      MacroNode? targetNode;
      for (final candidate in nodes) {
        if (candidate.kind != lightingTargetSinkKind) continue;
        try {
          final configuration = LightingTargetNodeConfiguration.fromNode(candidate);
          final inputId = '${candidate.id}.${binding.parameter.name}';
          if (configuration.targetKind == binding.targetKind &&
              configuration.targetId == binding.targetId &&
              configuration.parameters.contains(binding.parameter) &&
              !edges.any((edge) => edge.toPortId == inputId)) {
            targetNode = candidate;
            break;
          }
        } on FormatException {
          // Invalid persisted nodes remain untouched and visibly repairable.
        }
      }
      targetNode ??= _newTargetNode(
        targetKind: binding.targetKind,
        targetId: binding.targetId,
        displayName: binding.targetKind == MacroTargetKind.device ? 'Device ${binding.targetId}' : 'Group ${binding.targetId}',
        parameters: <MacroTargetParameter>[binding.parameter],
      );
      if (!nodes.any((node) => node.id == targetNode!.id)) {
        nodes.add(targetNode);
        positions[targetNode.id] = MacroEditorPosition(x: 600 + ((nodes.length % 2) * 250), y: 80 + ((nodes.length ~/ 2) * 180));
      }
      edges.add(
        MacroEdge(
          id: const Uuid().v4(),
          fromPortId: binding.sourcePortId,
          toPortId: '${targetNode.id}.${binding.parameter.name}',
        ),
      );
    }
    return _withDerivedBindings(graph.copyWith(nodes: nodes, edges: edges, editorPositions: positions));
  }

  String _bindingKey(MacroTargetBinding binding) =>
      '${binding.sourcePortId}|${binding.targetKind.name}|${binding.targetId}|${binding.parameter.name}';

  Future<void> _save() async {
    final saved = await _persistDraft();
    if (saved && _isNew && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Persists exactly the graph currently rendered by the editor.
  ///
  /// A runtime deliberately reads its definition from the macro library rather
  /// than from this widget's mutable draft. Keeping this boundary avoids a
  /// running graph changing below the runtime, but it also means Start must
  /// synchronise the draft first (notably for source settings such as hue).
  Future<bool> _persistDraft() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Вкажіть назву macro.');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
      _draft = _withDerivedBindings(_draft.copyWith(name: name));
    });
    final saved = await ref.read(macroLibraryProvider.notifier).save(_draft);
    if (!mounted) {
      return false;
    }
    setState(() {
      _saving = false;
      if (!saved) {
        _error = ref.read(macroLibraryProvider).error ?? 'Не вдалося зберегти macro.';
      }
    });
    return saved;
  }

  Future<void> _start() async {
    if (_isNew) {
      _showError('Спершу збережіть macro.');
      return;
    }
    // The runtime is intentionally constructed from persisted data. Make a
    // Start action include the visible draft so the selected Color modifier
    // hue cannot be replaced by an older (often default H 0) saved value.
    if (!await _persistDraft()) {
      return;
    }
    if (!mounted) {
      return;
    }
    await ref.read(macroRuntimeSessionsProvider.notifier).start(_draft.id);
  }

  Future<void> _stop() {
    // A debounced edit may already be waiting to replace the runtime. Stop is
    // a lifecycle boundary, so do not let this page request another update.
    _runtimeUpdateTimer?.cancel();
    _runtimeUpdateTimer = null;
    _runtimeUpdateQueued = false;
    return ref.read(macroRuntimeSessionsProvider.notifier).stop(_draft.id);
  }

  /// Back navigation is a macro lifecycle boundary. Do not leave a microphone
  /// source and its device delivery session active behind an invisible editor.
  Future<void> _stopRuntimeThenExit() async {
    if (_stoppingForExit) return;
    setState(() => _stoppingForExit = true);
    try {
      await _stop();
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showError(String error) => setState(() => _error = error);
}

enum _NewNodeKind { microphone, multibandEq, color, colorBrightnessCombine }

final class _TargetInput {
  const _TargetInput({required this.targetKind, required this.targetId, required this.parameter});

  final MacroTargetKind targetKind;
  final String targetId;
  final MacroTargetParameter parameter;
}

MacroGraph _initialMacro() {
  final microphone = _newMicrophoneNode();
  final equalizer = _newEqNode();
  return MacroGraph(
    id: const Uuid().v4(),
    name: 'Microphone lights',
    nodes: <MacroNode>[microphone, equalizer],
    edges: <MacroEdge>[
      MacroEdge(id: const Uuid().v4(), fromPortId: microphone.ports.single.id, toPortId: equalizer.ports.first.id),
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

MacroNode _newColorNode() {
  final id = const Uuid().v4();
  final configuration = ColorModifierConfiguration();
  return MacroNode(
    id: id,
    kind: colorModifierKind,
    displayName: 'Color',
    ports: ColorModifierFactory.portsForNode(id),
    parameters: configuration.toNodeParameters(),
  );
}

MacroNode _newColorBrightnessCombineNode() {
  final id = const Uuid().v4();
  return MacroNode(
    id: id,
    kind: colorBrightnessCombineModifierKind,
    displayName: 'Color + brightness',
    ports: ColorBrightnessCombineModifierFactory.portsForNode(id),
  );
}

MacroNode? _newDeviceTargetNode(DebugDevice device) {
  final capabilities = device.capabilities;
  if (capabilities == null) return null;
  final parameters = <MacroTargetParameter>[
    if (capabilities.supports(LightingFeature.power, allowInferred: true)) MacroTargetParameter.power,
    if (capabilities.supports(LightingFeature.brightness, allowInferred: true)) MacroTargetParameter.brightness,
    if (capabilities.supports(LightingFeature.rgb, allowInferred: true) ||
        capabilities.supports(LightingFeature.rgbw, allowInferred: true))
      MacroTargetParameter.color,
  ];
  if (parameters.isEmpty) return null;
  return _newTargetNode(
    targetKind: MacroTargetKind.device,
    targetId: device.appDeviceId,
    displayName: device.endpoint.displayName ?? device.appDeviceId,
    parameters: parameters,
  );
}

MacroNode _newTargetNode({
  required MacroTargetKind targetKind,
  required String targetId,
  required String displayName,
  required List<MacroTargetParameter> parameters,
}) {
  final id = const Uuid().v4();
  final configuration = LightingTargetNodeConfiguration(targetKind: targetKind, targetId: targetId, parameters: parameters);
  return MacroNode(
    id: id,
    kind: lightingTargetSinkKind,
    displayName: displayName,
    ports: configuration.portsForNode(id),
    parameters: configuration.toNodeParameters(),
  );
}

List<MacroPortDeclaration> _eqPorts(String nodeId, MultibandEqTriggerConfiguration configuration) => <MacroPortDeclaration>[
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
      type: band.mode == MultibandEqBandMode.gate ? MacroPortType.triggerGate : MacroPortType.triggerLevel,
      displayIdentifier: 'band.${band.id}',
      displayName: band.id,
    ),
];

class _RuntimeControl extends StatelessWidget {
  const _RuntimeControl({required this.status, required this.enabled, required this.onStart, required this.onStop});
  final MacroRuntimeSessionStatus? status;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final lifecycle = status?.lifecycle;
    final running = lifecycle == MacroRuntimeSessionLifecycle.running || lifecycle == MacroRuntimeSessionLifecycle.starting;
    final label = switch (lifecycle) {
      MacroRuntimeSessionLifecycle.running => null,
      MacroRuntimeSessionLifecycle.starting => 'Starting',
      MacroRuntimeSessionLifecycle.invalid => 'Needs repair',
      MacroRuntimeSessionLifecycle.error => 'Error',
      MacroRuntimeSessionLifecycle.stopped => null,
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8.0,
      children: <Widget>[
        if (label != null) Flexible(child: Text(label)),
        if (running)
          IconButton.filledTonal(
            key: const Key('stop-macro-runtime'),
            onPressed: enabled ? onStop : null,
            icon: const Icon(Icons.stop),
            tooltip: 'Stop',
          )
        else
          IconButton.filledTonal(
            key: const Key('start-macro-runtime'),
            onPressed: enabled ? onStart : null,
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Start',
          ),
      ],
    );
  }
}

class _SelectedNodeInspector extends StatelessWidget {
  const _SelectedNodeInspector({
    required this.node,
    required this.enabled,
    required this.devices,
    required this.inputDrivenFeatures,
    required this.inputLevelDbfs,
    required this.spectrumValues,
    required this.spectrumFrequenciesHz,
    required this.onEqChanged,
    required this.onRemove,
  });
  final MacroNode? node;
  final bool enabled;
  final Map<String, DebugDevice> devices;
  final Set<LightingFeature> inputDrivenFeatures;
  final double? inputLevelDbfs;
  final List<double> spectrumValues;
  final List<double> spectrumFrequenciesHz;
  final ValueChanged<MultibandEqTriggerConfiguration> onEqChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final current = node;
    if (current == null) {
      return const _EditorHint(text: 'Оберіть вузол у patcher, щоб налаштувати його.');
    }
    if (current.kind == multibandEqTriggerKind) {
      try {
        final configuration = MultibandEqTriggerConfiguration.fromNodeParameters(current.parameters);
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
              const Text('Microphone input is transient and is not written to files.'),
              const SizedBox(height: 12),
              _MicrophoneDbMeter(dbfs: inputLevelDbfs),
            ],
          ),
        ),
      );
    }
    if (current.kind == lightingTargetSinkKind) {
      try {
        final configuration = LightingTargetNodeConfiguration.fromNode(current);
        if (configuration.targetKind != MacroTargetKind.device) {
          return _targetInspectorFallback(current, 'Групові target-контроли ще не представлені в patcher.');
        }
        final device = devices[configuration.targetId];
        if (device == null) {
          return _targetInspectorFallback(current, 'Девайс більше не доступний. Повторіть scan або видаліть target node.');
        }
        final target = LightingTarget(
          id: device.appDeviceId,
          name: device.endpoint.displayName ?? device.appDeviceId,
          kind: LightingTargetKind.device,
          memberDeviceIds: <String>{device.appDeviceId},
          protocolId: device.protocolId,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Device controls'),
                subtitle: const Text('Ручні значення застосовуються, доки відповідний input не надіслав значення.'),
                trailing: IconButton(
                  tooltip: 'Видалити вузол',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
            const SizedBox(height: 8),
            CompactControlCard(
              key: ValueKey<String>('macro-device-control-${current.id}'),
              target: target,
              inputDrivenFeatures: inputDrivenFeatures,
              inputDrivenMessage: _inputDrivenMessage(inputDrivenFeatures),
            ),
          ],
        );
      } on FormatException catch (error) {
        return _EditorError(message: 'Device target configuration needs repair: $error');
      }
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

  Widget _targetInspectorFallback(MacroNode node, String detail) => Card(
    child: ListTile(
      title: Text(node.displayName ?? node.kind),
      subtitle: Text(detail),
      trailing: IconButton(
        tooltip: 'Видалити вузол',
        onPressed: enabled ? onRemove : null,
        icon: const Icon(Icons.delete_outline),
      ),
    ),
  );

  static String? _inputDrivenMessage(Set<LightingFeature> features) {
    if (features.isEmpty) return null;
    final labels = <String>[
      if (features.contains(LightingFeature.power)) 'живлення',
      if (features.contains(LightingFeature.rgb) || features.contains(LightingFeature.rgbw)) 'колір',
      if (features.contains(LightingFeature.brightness)) 'яскравість',
    ];
    return 'Вхід macro зараз має пріоритет: ${labels.join(', ')}.';
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
    final label = value == null ? 'Очікування аудіо' : '${value.toStringAsFixed(1)} dBFS';
    return Semantics(
      label: 'Microphone input level: $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Input level', style: Theme.of(context).textTheme.labelLarge),
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
    final meter = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height - labelSpace), const Radius.circular(8));
    canvas.drawRRect(meter, Paint()..color = const Color(0xFF181825));
    final active = dbfs?.clamp(_minimumDbfs, 0.0).toDouble();
    if (active != null) {
      final width = size.width * ((active - _minimumDbfs) / -_minimumDbfs);
      final activeMeter = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, size.height - labelSpace), const Radius.circular(8));
      canvas.drawRRect(
        activeMeter,
        Paint()
          ..shader = const LinearGradient(
            colors: <Color>[Color(0xFF89B4FA), Color(0xFFA6E3A1), Color(0xFFF9E2AF), Color(0xFFF38BA8)],
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
      canvas.drawLine(Offset(x, size.height - labelSpace), Offset(x, size.height - labelSpace + 4), tickPaint);
      final text = TextPainter(
        text: TextSpan(
          text: '$tick',
          style: const TextStyle(color: Color(0xFFBAC2DE), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset((x - text.width / 2).clamp(0.0, size.width - text.width), size.height - 12));
    }
  }

  @override
  bool shouldRepaint(covariant _MicrophoneDbMeterPainter oldDelegate) => oldDelegate.dbfs != dbfs;
}

class _MacroPaletteItem {
  const _MacroPaletteItem.module(this.kind) : device = null;
  const _MacroPaletteItem.device(this.device) : kind = null;

  final _NewNodeKind? kind;
  final DebugDevice? device;
}

/// The palette is intentionally presentation-only. A drop or tap delegates
/// graph mutation to the editor; it never creates runtime instances itself.
class _MacroPalette extends StatelessWidget {
  const _MacroPalette({required this.devices, required this.enabled, required this.onAdd});

  final List<DebugDevice> devices;
  final bool enabled;
  final ValueChanged<_MacroPaletteItem> onAdd;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text('Modules', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        _MacroPaletteEntry(
          item: const _MacroPaletteItem.module(_NewNodeKind.microphone),
          icon: Icons.mic_none_outlined,
          title: 'Microphone',
          subtitle: 'Mono audio input',
          enabled: enabled,
          onAdd: onAdd,
        ),
        _MacroPaletteEntry(
          item: const _MacroPaletteItem.module(_NewNodeKind.multibandEq),
          icon: Icons.graphic_eq,
          title: 'Multiband EQ',
          subtitle: 'Audio analysis trigger',
          enabled: enabled,
          onAdd: onAdd,
        ),
        _MacroPaletteEntry(
          item: const _MacroPaletteItem.module(_NewNodeKind.color),
          icon: Icons.palette_outlined,
          title: 'Color',
          subtitle: 'HSV source',
          enabled: enabled,
          onAdd: onAdd,
        ),
        _MacroPaletteEntry(
          item: const _MacroPaletteItem.module(_NewNodeKind.colorBrightnessCombine),
          icon: Icons.merge_type_outlined,
          title: 'Color + brightness',
          subtitle: 'HSV Value combiner',
          enabled: enabled,
          onAdd: onAdd,
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text('Devices', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (devices.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('No discovered devices.'))
        else
          ...devices.map((device) {
            final available = device.capabilities != null && enabled;
            return _MacroPaletteEntry(
              item: _MacroPaletteItem.device(device),
              icon: Icons.lightbulb_outline,
              title: device.endpoint.displayName ?? device.appDeviceId,
              subtitle: available ? '${device.status.name} · drag to add inputs' : 'Connect to load capabilities',
              enabled: available,
              onAdd: onAdd,
            );
          }),
      ],
    ),
  );
}

class _MacroPaletteEntry extends StatelessWidget {
  const _MacroPaletteEntry({
    required this.item,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onAdd,
  });

  final _MacroPaletteItem item;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<_MacroPaletteItem> onAdd;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      dense: true,
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: enabled ? () => onAdd(item) : null,
    );
    if (!enabled) return tile;
    return Draggable<_MacroPaletteItem>(
      data: item,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 220,
          child: ListTile(dense: true, leading: Icon(icon), title: Text(title)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: tile),
      child: tile,
    );
  }
}

/// A small direct-manipulation hue control for the colour source node.
///
/// Saturation and value intentionally remain 1 in this first source modifier;
/// a downstream Color + brightness node owns animated HSV Value.
class _CompactHuePicker extends StatelessWidget {
  const _CompactHuePicker({required this.hue, required this.enabled, required this.onChanged});

  final double hue;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      void update(Offset localPosition) {
        if (!enabled || constraints.maxWidth <= 0) return;
        onChanged((localPosition.dx.clamp(0, constraints.maxWidth) / constraints.maxWidth * 360).toDouble());
      }

      final thumbAlignment = (hue / 180 - 1).clamp(-1.0, 1.0).toDouble();
      return Semantics(
        label: 'Color hue ${hue.round()} degrees',
        slider: true,
        child: GestureDetector(
          onTapDown: enabled ? (details) => update(details.localPosition) : null,
          onHorizontalDragUpdate: enabled ? (details) => update(details.localPosition) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: const LinearGradient(
                colors: <Color>[Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red],
              ),
            ),
            child: Stack(
              alignment: Alignment(thumbAlignment, 0),
              children: <Widget>[
                const SizedBox.expand(),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 2, color: Color(0x99000000))],
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 1),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      'H ${hue.round()}°',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
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
