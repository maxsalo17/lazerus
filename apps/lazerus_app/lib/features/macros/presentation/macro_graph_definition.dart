import 'dart:ui';

import 'package:lazerus_core/lazerus_core.dart';

/// Immutable display input for [MacroPatcherCanvas].
///
/// This is deliberately presentation-only: callers translate persisted graph
/// state into this definition and handle the canvas callbacks themselves.
final class MacroGraphDefinition {
  MacroGraphDefinition({
    required Iterable<MacroNode> nodes,
    Iterable<MacroEdge> edges = const <MacroEdge>[],
    Map<String, MacroNodeLayout> layouts = const <String, MacroNodeLayout>{},
  }) : nodes = List<MacroNode>.unmodifiable(nodes),
       edges = List<MacroEdge>.unmodifiable(edges),
       layouts = Map<String, MacroNodeLayout>.unmodifiable(layouts);

  final List<MacroNode> nodes;
  final List<MacroEdge> edges;
  final Map<String, MacroNodeLayout> layouts;
}

/// Editor-only placement for one macro node.
///
/// [position] is in canvas coordinates, not screen coordinates. [size] lets a
/// caller reserve space for a node whose presentation differs from the default.
final class MacroNodeLayout {
  const MacroNodeLayout({
    required this.position,
    this.size = const Size(224, 0),
  });

  final Offset position;
  final Size size;

  MacroNodeLayout copyWith({Offset? position, Size? size}) => MacroNodeLayout(
    position: position ?? this.position,
    size: size ?? this.size,
  );
}
