import 'package:lazerus_core/lazerus_core.dart';

/// Replaces one node and retains only still-valid connections touching it.
///
/// Configuration can change a node's port types without changing its port IDs.
/// This operation therefore checks the updated direction and type contracts,
/// rather than retaining edges based on IDs alone.
MacroGraph replaceMacroGraphNode(MacroGraph graph, MacroNode replacement) {
  MacroNode? original;
  for (final node in graph.nodes) {
    if (node.id == replacement.id) {
      original = node;
      break;
    }
  }
  if (original == null) return graph;

  final originalPortIds = original.ports.map((port) => port.id).toSet();
  final nodes = graph.nodes
      .map((node) => node.id == replacement.id ? replacement : node)
      .toList(growable: false);
  final portsById = <String, MacroPortDeclaration>{
    for (final node in nodes)
      for (final port in node.ports) port.id: port,
  };
  final edges = graph.edges
      .where((edge) {
        final touchesReplacement =
            originalPortIds.contains(edge.fromPortId) ||
            originalPortIds.contains(edge.toPortId);
        if (!touchesReplacement) return true;
        final source = portsById[edge.fromPortId];
        final destination = portsById[edge.toPortId];
        return source != null &&
            destination != null &&
            source.direction == MacroPortDirection.output &&
            destination.direction == MacroPortDirection.input &&
            source.type == destination.type;
      })
      .toList(growable: false);
  return graph.copyWith(nodes: nodes, edges: edges);
}
