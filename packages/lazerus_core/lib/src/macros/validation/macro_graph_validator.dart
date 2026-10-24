import '../contracts/macro_graph.dart';
import '../contracts/macro_port.dart';

/// Resolves a registered module's port contract for one configured node.
///
/// Returns null when the node kind is not registered. The callback keeps this
/// validator independent of runtime registry and module implementations.
typedef MacroNodePortContractResolver =
    List<MacroPortDeclaration>? Function(MacroNode node);

/// The category of a non-runnable macro graph condition.
enum MacroGraphValidationCode {
  unknownNodeKind,
  nodePortsDoNotMatchContract,
  duplicatePortId,
  missingPort,
  invalidEdgeDirection,
  incompatiblePortTypes,
  duplicateInputConnection,
  missingRequiredInput,
  invalidTargetBinding,
  invalidTargetParameterType,
  cycle,
}

/// One actionable validation result. Persisted graphs are not rewritten by
/// validation, so unavailable modules and broken references remain repairable.
final class MacroGraphValidationIssue {
  const MacroGraphValidationIssue({
    required this.code,
    required this.message,
    this.nodeId,
    this.edgeId,
    this.bindingId,
  });

  final MacroGraphValidationCode code;
  final String message;
  final String? nodeId;
  final String? edgeId;
  final String? bindingId;
}

/// Optional external checks supplied by the future persistence/runtime layer.
abstract interface class MacroTargetValidator {
  /// Returns null when a saved device/group target is currently valid.
  String? validate(MacroTargetBinding binding);
}

/// Validates static macro graph structure without loading UI, streams or BLE.
final class MacroGraphValidator {
  const MacroGraphValidator({
    this.knownNodeKinds = const <String>{},
    this.knownNodePorts = const <String, List<MacroPortDeclaration>>{},
    this.nodePortContractResolver,
    this.targetValidator,
  });

  /// Empty means module availability is intentionally not checked.
  final Set<String> knownNodeKinds;

  /// Static module-port contracts keyed by registered node kind.
  ///
  /// A graph persists a node's ports so it remains editable when a module is
  /// absent. When a module is present, the runtime supplies this map and the
  /// persisted declaration must match the registered contract exactly.
  final Map<String, List<MacroPortDeclaration>> knownNodePorts;

  /// Optional node-aware registered module contracts.
  ///
  /// When supplied, this takes precedence over [knownNodePorts] for a node so
  /// configured modules can expose a variable number of ports. The static map
  /// remains supported for callers that only have kind-level contracts.
  final MacroNodePortContractResolver? nodePortContractResolver;
  final MacroTargetValidator? targetValidator;

  List<MacroGraphValidationIssue> validate(MacroGraph graph) {
    final issues = <MacroGraphValidationIssue>[];
    final ports = <String, _NodePort>{};
    final nodeIds = graph.nodes.map((node) => node.id).toSet();

    for (final node in graph.nodes) {
      if (knownNodeKinds.isNotEmpty && !knownNodeKinds.contains(node.kind)) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.unknownNodeKind,
            nodeId: node.id,
            message:
                'No registered module exists for node kind "${node.kind}".',
          ),
        );
      }
      List<MacroPortDeclaration>? registeredPorts;
      try {
        registeredPorts =
            nodePortContractResolver?.call(node) ?? knownNodePorts[node.kind];
      } on Object catch (error) {
        // Node parameters are persisted user configuration. A module must not
        // make malformed configuration crash validation or erase the graph;
        // retain it as a repairable contract issue instead.
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.nodePortsDoNotMatchContract,
            nodeId: node.id,
            message:
                'The registered contract for "${node.kind}" could not be '
                'resolved: $error',
          ),
        );
      }
      if (registeredPorts != null && !_samePorts(node.ports, registeredPorts)) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.nodePortsDoNotMatchContract,
            nodeId: node.id,
            message:
                'Node ports do not match the registered contract for "${node.kind}".',
          ),
        );
      }
      for (final port in node.ports) {
        if (ports.containsKey(port.id)) {
          issues.add(
            MacroGraphValidationIssue(
              code: MacroGraphValidationCode.duplicatePortId,
              nodeId: node.id,
              message: 'Port ID "${port.id}" is used by more than one node.',
            ),
          );
        } else {
          ports[port.id] = _NodePort(node, port);
        }
      }
    }

    final connectedInputIds = <String>{};
    final adjacency = <String, Set<String>>{
      for (final nodeId in nodeIds) nodeId: <String>{},
    };
    for (final edge in graph.edges) {
      final source = ports[edge.fromPortId];
      final destination = ports[edge.toPortId];
      if (source == null || destination == null) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.missingPort,
            edgeId: edge.id,
            message: 'Edge refers to a port that is not present in this graph.',
          ),
        );
        continue;
      }
      if (source.port.direction != MacroPortDirection.output ||
          destination.port.direction != MacroPortDirection.input) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.invalidEdgeDirection,
            edgeId: edge.id,
            message: 'Edges must connect an output port to an input port.',
          ),
        );
      }
      if (source.port.type != destination.port.type) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.incompatiblePortTypes,
            edgeId: edge.id,
            message: 'Connected ports must have the same declared type.',
          ),
        );
      }
      if (!destination.port.acceptsMultipleInputs &&
          !connectedInputIds.add(destination.port.id)) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.duplicateInputConnection,
            edgeId: edge.id,
            message:
                'Input port "${destination.port.id}" accepts one connection.',
          ),
        );
      }
      if (source.node.id != destination.node.id) {
        adjacency[source.node.id]?.add(destination.node.id);
      }
    }

    for (final entry in ports.entries) {
      final nodePort = entry.value;
      if (nodePort.port.direction == MacroPortDirection.input &&
          nodePort.port.required &&
          !connectedInputIds.contains(entry.key)) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.missingRequiredInput,
            nodeId: nodePort.node.id,
            message: 'Required input port "${entry.key}" is not connected.',
          ),
        );
      }
    }

    for (final binding in graph.targetBindings) {
      final source = ports[binding.sourcePortId];
      if (source == null ||
          source.port.direction != MacroPortDirection.output) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.invalidTargetBinding,
            bindingId: binding.id,
            message: 'Binding source must identify an existing output port.',
          ),
        );
        continue;
      }
      if (!_acceptsParameter(source.port.type, binding.parameter)) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.invalidTargetParameterType,
            bindingId: binding.id,
            message: 'The bound port type cannot drive this target parameter.',
          ),
        );
      }
      final targetError = targetValidator?.validate(binding);
      if (targetError != null) {
        issues.add(
          MacroGraphValidationIssue(
            code: MacroGraphValidationCode.invalidTargetBinding,
            bindingId: binding.id,
            message: targetError,
          ),
        );
      }
    }

    if (_hasCycle(adjacency)) {
      issues.add(
        const MacroGraphValidationIssue(
          code: MacroGraphValidationCode.cycle,
          message: 'A macro graph must not contain a directed cycle.',
        ),
      );
    }
    return List<MacroGraphValidationIssue>.unmodifiable(issues);
  }

  static bool _acceptsParameter(
    MacroPortType type,
    MacroTargetParameter parameter,
  ) => switch (parameter) {
    MacroTargetParameter.brightness => type == MacroPortType.triggerLevel,
    MacroTargetParameter.power => type == MacroPortType.triggerGate,
    MacroTargetParameter.color => type == MacroPortType.triggerHsv,
  };

  static bool _hasCycle(Map<String, Set<String>> adjacency) {
    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String nodeId) {
      if (visiting.contains(nodeId)) return true;
      if (!visited.add(nodeId)) return false;
      visiting.add(nodeId);
      for (final next in adjacency[nodeId] ?? const <String>{}) {
        if (visit(next)) return true;
      }
      visiting.remove(nodeId);
      return false;
    }

    return adjacency.keys.any(visit);
  }

  static bool _samePorts(
    List<MacroPortDeclaration> actual,
    List<MacroPortDeclaration> expected,
  ) {
    if (actual.length != expected.length) return false;
    final expectedById = <String, MacroPortDeclaration>{
      for (final port in expected) port.id: port,
    };
    if (expectedById.length != expected.length) return false;
    for (final port in actual) {
      final registered = expectedById[port.id];
      if (registered == null ||
          registered.direction != port.direction ||
          registered.type != port.type ||
          registered.displayIdentifier != port.displayIdentifier ||
          registered.required != port.required ||
          registered.acceptsMultipleInputs != port.acceptsMultipleInputs) {
        return false;
      }
    }
    return true;
  }
}

final class _NodePort {
  const _NodePort(this.node, this.port);

  final MacroNode node;
  final MacroPortDeclaration port;
}
