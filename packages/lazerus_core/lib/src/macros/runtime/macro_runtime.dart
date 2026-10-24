import 'dart:async';

import '../contracts/macro_graph.dart';
import '../contracts/macro_port.dart';
import '../triggers/contracts/trigger.dart';
import '../validation/macro_graph_validator.dart';

/// Lifecycle of one in-memory [MacroRuntime].
///
/// A runtime is deliberately transport-neutral. A running runtime emits typed
/// intents; a lighting scheduler outside this package decides whether and when
/// a protocol write is attempted.
enum MacroRuntimeLifecycle {
  created,
  validated,
  ready,
  running,
  stopped,
  error,
}

/// Static contract and factory for one independently implemented macro module.
///
/// A trigger or modifier implements this interface without importing any
/// sibling implementation. Modules communicate only through [TriggerEvent]
/// and the graph ports declared here.
abstract interface class MacroModuleFactory {
  String get kind;
  List<MacroPortDeclaration> get ports;

  MacroModuleInstance create(MacroNode node);
}

/// Optional node-aware port contract for a [MacroModuleFactory].
///
/// Implement this alongside [MacroModuleFactory] when a module's configured
/// node determines its ports, such as an equalizer with one output per band.
/// Factories that do not implement this interface continue to use their static
/// [MacroModuleFactory.ports] declaration.
abstract interface class MacroNodePortContractProvider {
  List<MacroPortDeclaration> portsFor(MacroNode node);
}

/// One configured module instance owned by a [MacroRuntime].
abstract interface class MacroModuleInstance {
  /// Called once when its graph enters the running state.
  void start(MacroRuntimeEventEmitter emitter);

  /// Receives a routed event on one of this node's input ports.
  ///
  /// [inputPortId] is explicit because a modifier may expose more than one
  /// compatible input type.
  void onInput(String inputPortId, TriggerEvent event);

  /// Releases transient resources when the graph stops.
  void stop();
}

/// Emitter supplied to a module while its graph is running.
///
/// The event's [TriggerEvent.sourcePortId] must identify an output declared on
/// the emitting node. Invalid events are rejected by the runtime and do not
/// reach other modules or targets.
abstract interface class MacroRuntimeEventEmitter {
  void emit(TriggerEvent event);
}

/// Registry of module factories available to a macro runtime.
///
/// Registration is explicit at the composition root. Replacing or removing a
/// module changes only this registry; persisted graphs retain their node data
/// and are reported as repairable invalid graphs until a compatible module is
/// registered again.
final class MacroModuleRegistry {
  final Map<String, MacroModuleFactory> _factories =
      <String, MacroModuleFactory>{};

  Set<String> get kinds => Set<String>.unmodifiable(_factories.keys);

  Map<String, List<MacroPortDeclaration>> get portContracts =>
      Map<String, List<MacroPortDeclaration>>.unmodifiable(
        _factories.map(
          (kind, factory) => MapEntry<String, List<MacroPortDeclaration>>(
            kind,
            List<MacroPortDeclaration>.unmodifiable(factory.ports),
          ),
        ),
      );

  /// Resolves the registered port contract for one persisted [node].
  ///
  /// Returns null when its kind is not registered. A node-aware provider takes
  /// precedence over the factory's static contract.
  List<MacroPortDeclaration>? portsFor(MacroNode node) {
    final factory = _factories[node.kind];
    if (factory == null) return null;
    final ports = factory is MacroNodePortContractProvider
        ? (factory as MacroNodePortContractProvider).portsFor(node)
        : factory.ports;
    return List<MacroPortDeclaration>.unmodifiable(ports);
  }

  bool contains(String kind) => _factories.containsKey(kind);

  MacroModuleFactory? operator [](String kind) => _factories[kind];

  void register(MacroModuleFactory factory) {
    if (factory.kind.trim().isEmpty) {
      throw ArgumentError.value(
        factory.kind,
        'factory.kind',
        'Must not be blank.',
      );
    }
    if (_factories.containsKey(factory.kind)) {
      throw StateError(
        'A module factory is already registered for "${factory.kind}".',
      );
    }
    final portIds = factory.ports
        .map((port) => port.id)
        .toList(growable: false);
    if (portIds.toSet().length != portIds.length) {
      throw ArgumentError.value(
        factory.ports,
        'factory.ports',
        'Port IDs must be unique.',
      );
    }
    _factories[factory.kind] = factory;
  }

  bool unregister(String kind) => _factories.remove(kind) != null;
}

/// A typed, transport-free desired lighting update emitted by a macro graph.
final class MacroLightingIntent {
  MacroLightingIntent({
    required this.macroId,
    required this.bindingId,
    required this.targetId,
    required this.parameter,
    required this.value,
    required this.timestamp,
    required this.sequence,
  });

  final String macroId;
  final String bindingId;
  final String targetId;
  final MacroTargetParameter parameter;
  final TriggerValue value;
  final Duration timestamp;
  final int sequence;
}

/// Executes a validated macro graph with deterministic in-memory routing.
final class MacroRuntime {
  MacroRuntime({
    required this.graph,
    required this.registry,
    this.targetValidator,
  }) : _intentController = StreamController<MacroLightingIntent>.broadcast(
         sync: true,
       ),
       _eventController = StreamController<TriggerEvent>.broadcast(sync: true);

  final MacroGraph graph;
  final MacroModuleRegistry registry;
  final MacroTargetValidator? targetValidator;
  final StreamController<MacroLightingIntent> _intentController;
  // Runtime events are transient operational data. In particular, a
  // `triggerMonoAudio` event may contain microphone samples and must never be
  // persisted or forwarded to diagnostics/export code as raw audio.
  final StreamController<TriggerEvent> _eventController;
  final Map<String, MacroModuleInstance> _instances =
      <String, MacroModuleInstance>{};

  MacroRuntimeLifecycle _lifecycle = MacroRuntimeLifecycle.created;
  List<MacroGraphValidationIssue> _validationIssues =
      const <MacroGraphValidationIssue>[];

  MacroRuntimeLifecycle get lifecycle => _lifecycle;
  List<MacroGraphValidationIssue> get validationIssues => _validationIssues;
  Stream<MacroLightingIntent> get lightingIntents => _intentController.stream;

  /// Validated trigger events emitted while this runtime is running.
  ///
  /// Consumers may derive ephemeral UI telemetry (for example an EQ spectrum)
  /// but must not persist or export microphone sample arrays.
  Stream<TriggerEvent> get events => _eventController.stream;

  /// Validates registered module kinds and contracts alongside graph topology.
  /// Invalid configuration transitions to [MacroRuntimeLifecycle.error] and is
  /// left intact for caller-directed repair.
  List<MacroGraphValidationIssue> validate() {
    _requireLifecycle(<MacroRuntimeLifecycle>{MacroRuntimeLifecycle.created});
    final issues = MacroGraphValidator(
      knownNodeKinds: registry.kinds,
      nodePortContractResolver: registry.portsFor,
      targetValidator: targetValidator,
    ).validate(graph);
    _validationIssues = List<MacroGraphValidationIssue>.unmodifiable(issues);
    _lifecycle = issues.isEmpty
        ? MacroRuntimeLifecycle.validated
        : MacroRuntimeLifecycle.error;
    return _validationIssues;
  }

  /// Creates isolated module instances after successful [validate].
  void prepare() {
    _requireLifecycle(<MacroRuntimeLifecycle>{MacroRuntimeLifecycle.validated});
    try {
      for (final node in graph.nodes) {
        final factory = registry[node.kind];
        if (factory == null) {
          throw StateError('No factory is registered for "${node.kind}".');
        }
        _instances[node.id] = factory.create(node);
      }
      _lifecycle = MacroRuntimeLifecycle.ready;
    } catch (error) {
      _stopInstances();
      _lifecycle = MacroRuntimeLifecycle.error;
      rethrow;
    }
  }

  /// Starts downstream modules before their sources so an event emitted during
  /// source startup still reaches an initialized input.
  void start() {
    _requireLifecycle(<MacroRuntimeLifecycle>{MacroRuntimeLifecycle.ready});
    try {
      _lifecycle = MacroRuntimeLifecycle.running;
      for (final node in _nodesInSinkFirstOrder()) {
        _instances[node.id]!.start(_NodeEmitter(this, node));
      }
    } catch (error) {
      _stopInstances();
      _lifecycle = MacroRuntimeLifecycle.error;
      rethrow;
    }
  }

  /// Stops all created module instances and releases their runtime resources.
  void stop() {
    _requireLifecycle(<MacroRuntimeLifecycle>{
      MacroRuntimeLifecycle.ready,
      MacroRuntimeLifecycle.running,
    });
    _stopInstances();
    _lifecycle = MacroRuntimeLifecycle.stopped;
  }

  /// Releases runtime-owned streams. A closed runtime cannot be restarted.
  Future<void> dispose() async {
    if (_lifecycle == MacroRuntimeLifecycle.ready ||
        _lifecycle == MacroRuntimeLifecycle.running) {
      stop();
    }
    await _intentController.close();
    await _eventController.close();
  }

  void _emitFromNode(MacroNode node, TriggerEvent event) {
    if (_lifecycle != MacroRuntimeLifecycle.running) return;
    final output = node.ports.where(
      (port) =>
          port.id == event.sourcePortId &&
          port.direction == MacroPortDirection.output &&
          port.type == event.primaryValue.portType,
    );
    if (output.isEmpty) return;

    _eventController.add(event);

    for (final edge in graph.edges) {
      if (edge.fromPortId != event.sourcePortId) continue;
      final destinationNode = _nodeForPort(edge.toPortId);
      final instance = destinationNode == null
          ? null
          : _instances[destinationNode.id];
      if (instance != null) instance.onInput(edge.toPortId, event);
    }
    for (final binding in graph.targetBindings) {
      if (binding.sourcePortId != event.sourcePortId) continue;
      _intentController.add(
        MacroLightingIntent(
          macroId: graph.id,
          bindingId: binding.id,
          targetId: binding.targetId,
          parameter: binding.parameter,
          value: event.primaryValue,
          timestamp: event.timestamp,
          sequence: event.sequence,
        ),
      );
    }
  }

  MacroNode? _nodeForPort(String portId) {
    for (final node in graph.nodes) {
      if (node.ports.any((port) => port.id == portId)) return node;
    }
    return null;
  }

  void _stopInstances() {
    for (final node in graph.nodes) {
      final instance = _instances[node.id];
      if (instance != null) instance.stop();
    }
    _instances.clear();
  }

  Iterable<MacroNode> _nodesInSinkFirstOrder() sync* {
    final nodeByPort = <String, MacroNode>{
      for (final node in graph.nodes)
        for (final port in node.ports) port.id: node,
    };
    final visited = <String>{};

    Iterable<MacroNode> visit(MacroNode node) sync* {
      if (!visited.add(node.id)) return;
      for (final edge in graph.edges) {
        if (!node.ports.any((port) => port.id == edge.fromPortId)) continue;
        final destination = nodeByPort[edge.toPortId];
        if (destination != null) yield* visit(destination);
      }
      yield node;
    }

    for (final node in graph.nodes) {
      yield* visit(node);
    }
  }

  void _requireLifecycle(Set<MacroRuntimeLifecycle> expected) {
    if (!expected.contains(_lifecycle)) {
      throw StateError(
        'Operation is not allowed while runtime is ${_lifecycle.name}.',
      );
    }
  }
}

final class _NodeEmitter implements MacroRuntimeEventEmitter {
  const _NodeEmitter(this.runtime, this.node);

  final MacroRuntime runtime;
  final MacroNode node;

  @override
  void emit(TriggerEvent event) => runtime._emitFromNode(node, event);
}
