import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lazerus_core/lazerus_core.dart';

import 'macro_graph_definition.dart';

typedef MacroConnectionCreate =
    void Function(String fromPortId, String toPortId);
typedef MacroConnectionRemove = void Function(String edgeId);
typedef MacroNodeMove = void Function(String nodeId, MacroNodeLayout layout);
typedef MacroNodeSelectionChanged = void Function(String? nodeId);

/// A stateless-command graph editor surface for desktop and touch input.
///
/// It manages only transient pointer interaction. Graph edits are reported to
/// the owner through callbacks, so validation and persistence remain outside
/// the presentation layer.
class MacroPatcherCanvas extends StatefulWidget {
  const MacroPatcherCanvas({
    super.key,
    required this.graph,
    this.selectedNodeId,
    this.onConnectionCreate,
    this.onConnectionRemove,
    this.onNodeMove,
    this.onSelectionChanged,
    this.outputValueLabels = const <String, String>{},
    this.minCanvasSize = const Size(760, 520),
  });

  final MacroGraphDefinition graph;
  final String? selectedNodeId;
  final MacroConnectionCreate? onConnectionCreate;
  final MacroConnectionRemove? onConnectionRemove;
  final MacroNodeMove? onNodeMove;
  final MacroNodeSelectionChanged? onSelectionChanged;

  /// Presentation-only realtime labels, keyed by output port identifier.
  ///
  /// A label is painted above every cable originating at its output port. The
  /// canvas neither interprets nor stores these values.
  final Map<String, String> outputValueLabels;
  final Size minCanvasSize;

  @override
  State<MacroPatcherCanvas> createState() => _MacroPatcherCanvasState();
}

class _MacroPatcherCanvasState extends State<MacroPatcherCanvas> {
  static const _nodeWidth = 224.0;
  static const _headerHeight = 44.0;
  static const _portHeight = 32.0;
  static const _padding = 16.0;
  String? _connectingOutputId;
  Offset? _connectionPointer;
  String? _draggingNodeId;
  Offset _dragOrigin = Offset.zero;
  Offset _nodeOrigin = Offset.zero;

  MacroNodeLayout _layoutFor(MacroNode node) =>
      widget.graph.layouts[node.id] ??
      MacroNodeLayout(
        position: Offset(48 + widget.graph.nodes.indexOf(node) * 252, 56),
      );

  Size _sizeFor(MacroNode node) {
    final layout = _layoutFor(node);
    final portCount = math.max(1, node.ports.length);
    return Size(
      layout.size.width > 0 ? layout.size.width : _nodeWidth,
      layout.size.height > 0
          ? layout.size.height
          : _headerHeight + _padding + portCount * _portHeight + _padding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final extent = _canvasExtent();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          math.max(
            widget.minCanvasSize.width,
            math.max(extent.width, constraints.maxWidth),
          ),
          math.max(
            widget.minCanvasSize.height,
            math.max(extent.height, constraints.maxHeight),
          ),
        );
        return ClipRect(
          child: InteractiveViewer(
            boundaryMargin: const EdgeInsets.all(240),
            minScale: 0.55,
            maxScale: 1.8,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PatchCablePainter(
                        edges: widget.graph.edges,
                        portCenters: _portCenters(),
                        outputValueLabels: widget.outputValueLabels,
                        pendingFrom: _connectingOutputId,
                        pendingTo: _connectionPointer,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) =>
                          _handleCanvasTap(details.localPosition),
                      onPanUpdate: _updateConnection,
                      onPanEnd: (_) => _finishConnection(),
                    ),
                  ),
                  for (final node in widget.graph.nodes)
                    _buildNode(context, node),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNode(BuildContext context, MacroNode node) {
    final layout = _layoutFor(node);
    final size = _sizeFor(node);
    final selected = widget.selectedNodeId == node.id;
    final inputs = node.ports.where(
      (port) => port.direction == MacroPortDirection.input,
    );
    final outputs = node.ports.where(
      (port) => port.direction == MacroPortDirection.output,
    );
    return Positioned(
      left: layout.position.dx,
      top: layout.position.dy,
      width: size.width,
      height: size.height,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(blurRadius: 6, color: Color(0x33000000)),
            ],
          ),
          child: Column(
            children: <Widget>[
              GestureDetector(
                onTap: () => widget.onSelectionChanged?.call(node.id),
                onPanStart: (details) => _startNodeDrag(node, details),
                onPanUpdate: _updateNodeDrag,
                onPanEnd: (_) => _endNodeDrag(),
                child: Container(
                  height: _headerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(11),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.drag_indicator, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          node.displayName ?? node.kind,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: _padding / 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: _portList(node, inputs, false)),
                      Expanded(child: _portList(node, outputs, true)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portList(
    MacroNode node,
    Iterable<MacroPortDeclaration> ports,
    bool output,
  ) => Column(
    children: ports
        .map(
          (port) => SizedBox(
            height: _portHeight,
            child: GestureDetector(
              key: Key('macro-port-${port.id}'),
              onTap: () => _handlePortTap(port),
              onPanStart: output
                  ? (details) =>
                        _startConnection(port.id, details.globalPosition)
                  : null,
              onPanUpdate: output
                  ? (details) =>
                        _updateConnectionFromGlobal(details.globalPosition)
                  : null,
              onPanEnd: output ? (_) => _finishConnection() : null,
              child: Row(
                mainAxisAlignment: output
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: <Widget>[
                  if (!output) _PortDot(type: port.type),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        port.displayName ?? port.displayIdentifier,
                        overflow: TextOverflow.ellipsis,
                        textAlign: output ? TextAlign.right : TextAlign.left,
                      ),
                    ),
                  ),
                  if (output) _PortDot(type: port.type),
                ],
              ),
            ),
          ),
        )
        .toList(growable: false),
  );

  void _startNodeDrag(MacroNode node, DragStartDetails details) {
    _draggingNodeId = node.id;
    _dragOrigin = details.globalPosition;
    _nodeOrigin = _layoutFor(node).position;
    widget.onSelectionChanged?.call(node.id);
  }

  void _updateNodeDrag(DragUpdateDetails details) {
    final id = _draggingNodeId;
    if (id == null) return;
    widget.onNodeMove?.call(
      id,
      MacroNodeLayout(
        position: _nodeOrigin + (details.globalPosition - _dragOrigin),
        size: widget.graph.layouts[id]?.size ?? const Size(_nodeWidth, 0),
      ),
    );
  }

  void _endNodeDrag() => _draggingNodeId = null;

  void _handlePortTap(MacroPortDeclaration port) {
    if (port.direction == MacroPortDirection.output) {
      setState(() => _connectingOutputId = port.id);
    } else if (_connectingOutputId != null) {
      _completeConnection(_connectingOutputId!, port.id);
    }
  }

  void _startConnection(String portId, Offset globalPosition) {
    setState(() {
      _connectingOutputId = portId;
      _connectionPointer = _toLocal(globalPosition);
    });
  }

  void _updateConnection(DragUpdateDetails details) {
    if (_connectingOutputId != null) {
      setState(() => _connectionPointer = details.localPosition);
    }
  }

  void _updateConnectionFromGlobal(Offset globalPosition) {
    if (_connectingOutputId != null) {
      setState(() => _connectionPointer = _toLocal(globalPosition));
    }
  }

  Offset _toLocal(Offset globalPosition) {
    final box = context.findRenderObject()! as RenderBox;
    return box.globalToLocal(globalPosition);
  }

  void _finishConnection() {
    final from = _connectingOutputId;
    final point = _connectionPointer;
    if (from != null && point != null) {
      final target = _portCenters().entries
          .where(
            (entry) =>
                _isInputPort(entry.key) && (entry.value - point).distance <= 20,
          )
          .map((entry) => entry.key)
          .firstOrNull;
      if (target != null) {
        _completeConnection(from, target);
      }
    }
    if (mounted) {
      setState(() {
        _connectingOutputId = null;
        _connectionPointer = null;
      });
    }
  }

  void _completeConnection(String from, String to) {
    widget.onConnectionCreate?.call(from, to);
    setState(() {
      _connectingOutputId = null;
      _connectionPointer = null;
    });
  }

  bool _isInputPort(String id) => widget.graph.nodes
      .expand((node) => node.ports)
      .any(
        (port) => port.id == id && port.direction == MacroPortDirection.input,
      );
  void _handleCanvasTap(Offset point) {
    final hit = widget.graph.edges.where((edge) {
      final a = _portCenters()[edge.fromPortId];
      final b = _portCenters()[edge.toPortId];
      return a != null && b != null && _distanceToSegment(point, a, b) < 10;
    }).firstOrNull;
    if (hit != null) {
      widget.onConnectionRemove?.call(hit.id);
      return;
    }
    if (_connectingOutputId == null) widget.onSelectionChanged?.call(null);
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  Map<String, Offset> _portCenters() {
    final result = <String, Offset>{};
    for (final node in widget.graph.nodes) {
      final layout = _layoutFor(node);
      final size = _sizeFor(node);
      var input = 0;
      var output = 0;
      for (final port in node.ports) {
        final y =
            layout.position.dy +
            _headerHeight +
            _padding +
            ((port.direction == MacroPortDirection.input ? input++ : output++) *
                _portHeight) +
            _portHeight / 2;
        result[port.id] = Offset(
          port.direction == MacroPortDirection.input
              ? layout.position.dx
              : layout.position.dx + size.width,
          y,
        );
      }
    }
    return result;
  }

  Size _canvasExtent() {
    var width = widget.minCanvasSize.width;
    var height = widget.minCanvasSize.height;
    for (final node in widget.graph.nodes) {
      final layout = _layoutFor(node);
      final size = _sizeFor(node);
      width = math.max(width, layout.position.dx + size.width + 80);
      height = math.max(height, layout.position.dy + size.height + 80);
    }
    return Size(width, height);
  }
}

class _PortDot extends StatelessWidget {
  const _PortDot({required this.type});
  final MacroPortType type;
  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (type) {
        MacroPortType.triggerMonoAudio => Colors.orange,
        MacroPortType.triggerArray => Colors.purple,
        MacroPortType.triggerGate => Colors.teal,
        MacroPortType.triggerLevel => Colors.blue,
      },
    ),
  );
}

class _PatchCablePainter extends CustomPainter {
  const _PatchCablePainter({
    required this.edges,
    required this.portCenters,
    required this.outputValueLabels,
    this.pendingFrom,
    this.pendingTo,
  });
  final List<MacroEdge> edges;
  final Map<String, Offset> portCenters;
  final Map<String, String> outputValueLabels;
  final String? pendingFrom;
  final Offset? pendingTo;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF74C7EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final edge in edges) {
      final from = portCenters[edge.fromPortId];
      final to = portCenters[edge.toPortId];
      if (from != null && to != null) {
        _curve(canvas, paint, from, to);
        final label = outputValueLabels[edge.fromPortId];
        if (label != null && label.isNotEmpty) {
          _label(canvas, label, _curveMidpoint(from, to));
        }
      }
    }
    final from = pendingFrom == null ? null : portCenters[pendingFrom!];
    if (from != null && pendingTo != null) {
      paint.color = const Color(0xFF89B4FA);
      paint.strokeWidth = 2;
      _curve(canvas, paint, from, pendingTo!);
    }
  }

  void _curve(Canvas canvas, Paint paint, Offset from, Offset to) {
    final distance = (to.dx - from.dx).abs();
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + math.max(48, distance / 2),
        from.dy,
        to.dx - math.max(48, distance / 2),
        to.dy,
        to.dx,
        to.dy,
      );
    canvas.drawPath(path, paint);
  }

  Offset _curveMidpoint(Offset from, Offset to) {
    final distance = (to.dx - from.dx).abs();
    final controlOffset = math.max(48, distance / 2);
    final controlA = Offset(from.dx + controlOffset, from.dy);
    final controlB = Offset(to.dx - controlOffset, to.dy);
    const t = 0.5;
    final inverseT = 1 - t;
    return from * (inverseT * inverseT * inverseT) +
        controlA * (3 * inverseT * inverseT * t) +
        controlB * (3 * inverseT * t * t) +
        to * (t * t * t);
  }

  void _label(Canvas canvas, String value, Offset cableMidpoint) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(
          color: Color(0xFFE6E9EF),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      ellipsis: '…',
    )..layout(maxWidth: 112);
    const horizontalPadding = 6.0;
    const verticalPadding = 3.0;
    final labelSize = Size(
      textPainter.width + horizontalPadding * 2,
      textPainter.height + verticalPadding * 2,
    );
    final origin = Offset(
      cableMidpoint.dx - labelSize.width / 2,
      cableMidpoint.dy - labelSize.height - 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(origin & labelSize, const Radius.circular(5)),
      Paint()..color = const Color(0xEE1E1E2E),
    );
    textPainter.paint(
      canvas,
      origin + const Offset(horizontalPadding, verticalPadding),
    );
  }

  @override
  bool shouldRepaint(covariant _PatchCablePainter old) =>
      old.edges != edges ||
      old.portCenters != portCenters ||
      old.outputValueLabels != outputValueLabels ||
      old.pendingFrom != pendingFrom ||
      old.pendingTo != pendingTo;
}
