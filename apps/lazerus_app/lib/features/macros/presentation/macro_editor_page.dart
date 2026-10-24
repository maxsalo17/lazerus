import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../application/macro_library_controller.dart';
import '../application/macro_runtime_session_controller.dart';
import 'macro_editor_palette.dart';
import 'macro_graph_definition.dart';
import 'macro_patcher_canvas.dart';
import 'node_modules/macro_editor_node_module.dart';
import 'node_modules/macro_editor_node_registry.dart';

/// Edits one versioned Scene Macro graph.
///
/// This page deliberately owns only generic graph lifecycle, persistence and
/// connection validation. Concrete trigger, modifier and target behaviour is
/// supplied by [MacroEditorNodeModule] implementations through their registry.
class MacroEditorPage extends ConsumerStatefulWidget {
  const MacroEditorPage({super.key, this.macro});

  final MacroGraph? macro;

  @override
  ConsumerState<MacroEditorPage> createState() => _MacroEditorPageState();
}

class _MacroEditorPageState extends ConsumerState<MacroEditorPage> {
  static const _liveUpdateDebounce = Duration(milliseconds: 120);

  late final MacroEditorNodeModuleRegistry _nodeModules;
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

  String _newId() => const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _nodeModules = createMacroEditorNodeModuleRegistry();
    _draft = _nodeModules.migrateLegacyBindings(widget.macro ?? _nodeModules.createStarterGraph(newId: _newId), newId: _newId);
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
    final editorEnabled = !_saving;
    final devicesState = ref.watch(debugDevicesProvider);
    final presentationState = MacroEditorNodePresentationState(
      graph: _draft,
      enabled: editorEnabled,
      devicesById: devicesState.devices,
      devices: devicesState.sortedDevices,
      runtime: status,
    );
    final selectedNode = _nodeById(_selectedNodeId);

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
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16),
              actions: <Widget>[
                _RuntimeControl(status: status, enabled: !_saving, onStart: _start, onStop: _stop),
                const SizedBox(width: 8),
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
                    spacing: 8,
                    children: <Widget>[
                      Flexible(child: Text('Patcher', style: Theme.of(context).textTheme.titleMedium)),
                      const Tooltip(
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
                          child: MacroEditorPalette(
                            entries: _nodeModules.paletteEntries(presentationState),
                            enabled: editorEnabled,
                            onAdd: _addPaletteItem,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DragTarget<MacroEditorPaletteEntry>(
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
                                nodeTitleBuilder: _nodeModules.titleFor,
                                nodeBodyBuilder: (context, node) => _nodeModules
                                    .moduleFor(node)
                                    .buildCardBody(context, _nodeViewContext(node, presentationState)),
                                nodeBodyHeight: (node) => _nodeModules.moduleFor(node).cardBodyHeight(node),
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
                  if (selectedNode == null)
                    const _EditorHint(text: 'Оберіть вузол у patcher, щоб налаштувати його.')
                  else
                    _nodeModules
                        .moduleFor(selectedNode)
                        .buildInspector(context, _nodeViewContext(selectedNode, presentationState)),
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

  MacroEditorNodeViewContext _nodeViewContext(MacroNode node, MacroEditorNodePresentationState presentationState) =>
      MacroEditorNodeViewContext(
        node: node,
        state: presentationState,
        replaceNode: _replaceNode,
        removeNode: () => _removeNode(node.id),
      );

  bool get _hasLiveRuntime {
    final lifecycle = ref.read(macroRuntimeSessionsProvider).statusFor(_draft.id)?.lifecycle;
    return lifecycle == MacroRuntimeSessionLifecycle.running || lifecycle == MacroRuntimeSessionLifecycle.starting;
  }

  /// Coalesces editor changes into one runtime definition replacement. The
  /// macro file stays explicit through Save/⌘S, while a live runtime follows
  /// the latest draft without any node-family-specific branch here.
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

  Offset? _dropPositionFor(Offset globalPosition) {
    final box = _patcherDropKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPosition);
    return Offset((local.dx - 112).clamp(20, 1300).toDouble(), (local.dy - 22).clamp(20, 900).toDouble());
  }

  void _addPaletteItem(MacroEditorPaletteEntry entry, [Offset? position]) {
    final node = _nodeModules.createNode(entry, newId: _newId);
    if (node == null) {
      _showError('Не вдалося створити node. Оновіть дані девайса або перевірте його capabilities.');
      return;
    }
    final fallbackPosition = Offset(56 + ((_draft.nodes.length % 3) * 250), 80 + ((_draft.nodes.length ~/ 3) * 220));
    final nodePosition = position ?? fallbackPosition;
    setState(() {
      _draft = _synchronizeBindings(
        _draft.copyWith(
          nodes: <MacroNode>[..._draft.nodes, node],
          editorPositions: <String, MacroEditorPosition>{
            ..._draft.editorPositions,
            node.id: MacroEditorPosition(x: nodePosition.dx, y: nodePosition.dy),
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

  /// Replaces an individual node supplied by its own presentation module.
  /// Dynamic port changes retain only edges whose old and new endpoints still
  /// exist; this keeps graph integrity without understanding the node kind.
  void _replaceNode(MacroNode replacement) {
    final original = _nodeById(replacement.id);
    if (original == null) return;
    final originalPortIds = original.ports.map((port) => port.id).toSet();
    final nodes = _draft.nodes.map((node) => node.id == replacement.id ? replacement : node).toList(growable: false);
    final currentPortIds = nodes.expand((node) => node.ports).map((port) => port.id).toSet();
    final edges = _draft.edges
        .where(
          (edge) =>
              (!originalPortIds.contains(edge.fromPortId) && !originalPortIds.contains(edge.toPortId)) ||
              (currentPortIds.contains(edge.fromPortId) && currentPortIds.contains(edge.toPortId)),
        )
        .toList(growable: false);
    setState(() {
      _draft = _synchronizeBindings(_draft.copyWith(nodes: nodes, edges: edges));
      _error = null;
    });
    _markRuntimeDefinitionChanged();
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
      _draft = _synchronizeBindings(
        _draft.copyWith(
          edges: <MacroEdge>[
            ..._draft.edges,
            MacroEdge(id: _newId(), fromPortId: fromPortId, toPortId: toPortId),
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
      _draft = _synchronizeBindings(_draft.copyWith(edges: _draft.edges.where((edge) => edge.id != edgeId)));
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
    final node = _nodeById(nodeId);
    if (node == null) return;
    final portIds = node.ports.map((port) => port.id).toSet();
    setState(() {
      final positions = <String, MacroEditorPosition>{..._draft.editorPositions}..remove(nodeId);
      _draft = _synchronizeBindings(
        _draft.copyWith(
          nodes: _draft.nodes.where((item) => item.id != nodeId),
          edges: _draft.edges.where((edge) => !portIds.contains(edge.fromPortId) && !portIds.contains(edge.toPortId)),
          editorPositions: positions,
        ),
      );
      _selectedNodeId = _draft.nodes.firstOrNull?.id;
    });
    _markRuntimeDefinitionChanged();
  }

  MacroGraph _synchronizeBindings(MacroGraph graph) => _nodeModules.synchronizeBindings(graph);

  Future<void> _save() async {
    final saved = await _persistDraft();
    if (saved && _isNew && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Persists exactly the graph currently rendered by the editor. A running
  /// macro is fed separately by the coalesced live-update path above.
  Future<bool> _persistDraft() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Вкажіть назву macro.');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
      _draft = _synchronizeBindings(_draft.copyWith(name: name));
    });
    final saved = await ref.read(macroLibraryProvider.notifier).save(_draft);
    if (!mounted) return false;
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
    if (!await _persistDraft() || !mounted) return;
    await ref.read(macroRuntimeSessionsProvider.notifier).start(_draft.id);
  }

  Future<void> _stop() {
    _runtimeUpdateTimer?.cancel();
    _runtimeUpdateTimer = null;
    _runtimeUpdateQueued = false;
    return ref.read(macroRuntimeSessionsProvider.notifier).stop(_draft.id);
  }

  Future<void> _stopRuntimeThenExit() async {
    if (_stoppingForExit) return;
    setState(() => _stoppingForExit = true);
    try {
      await _stop();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _showError(String error) => setState(() => _error = error);
}

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
      MacroRuntimeSessionLifecycle.starting => 'Starting',
      MacroRuntimeSessionLifecycle.invalid => 'Needs repair',
      MacroRuntimeSessionLifecycle.error => 'Error',
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
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
