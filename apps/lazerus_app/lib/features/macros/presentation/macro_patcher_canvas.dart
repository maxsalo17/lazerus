import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:lazerus_core/lazerus_core.dart';

import 'macro_graph_definition.dart';

typedef MacroConnectionCreate = void Function(String fromPortId, String toPortId);
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
    this.nodeBodyBuilder,
    this.nodeBodyHeight,
    this.nodeTitleBuilder,
    this.outputValueLabels = const <String, String>{},
  });

  final MacroGraphDefinition graph;
  final String? selectedNodeId;
  final MacroConnectionCreate? onConnectionCreate;
  final MacroConnectionRemove? onConnectionRemove;
  final MacroNodeMove? onNodeMove;
  final MacroNodeSelectionChanged? onSelectionChanged;

  /// Optional compact, node-specific presentation content. It remains a
  /// callback owned by the editor, so this canvas stays unaware of modifier
  /// configuration and has no persistence responsibilities.
  final Widget? Function(BuildContext context, MacroNode node)? nodeBodyBuilder;

  /// Reserved height for [nodeBodyBuilder] before the input/output rows.
  final double Function(MacroNode node)? nodeBodyHeight;

  /// Optional presentation title supplied by the registered node module.
  /// The canvas adds the graph-local index but never interprets node kinds.
  final String Function(MacroNode node)? nodeTitleBuilder;

  /// Presentation-only realtime labels, keyed by output port identifier.
  ///
  /// A label is painted above every cable originating at its output port. The
  /// canvas neither interprets nor stores these values.
  final Map<String, String> outputValueLabels;

  @override
  State<MacroPatcherCanvas> createState() => _MacroPatcherCanvasState();
}

class _MacroPatcherCanvasState extends State<MacroPatcherCanvas> {
  static const _nodeWidth = 224.0;
  static const _headerHeight = 44.0;
  static const _portHeight = 32.0;
  static const _padding = 16.0;
  static const _canvasSize = Size(8000, 8000);
  static const _canvasBounds = Rect.fromLTWH(0, 0, 8000, 8000);
  static const _minimumScale = 0.3;
  static const _maximumScale = 4.0;
  static const _elementVisualOverflow = 8.0;
  String? _connectingPortId;
  Offset? _connectionPointer;
  Offset? _lastPointerPosition;
  String? _draggingNodeId;
  Offset _dragPointerCanvasOrigin = Offset.zero;
  Offset _nodeOrigin = Offset.zero;
  final TransformationController _viewportController = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  var _isConstrainingViewport = false;
  var _lastLoggedViewportScale = double.nan;
  var _hasPositionedInitialViewport = false;

  bool get _canEditConnections => widget.onConnectionCreate != null && widget.onConnectionRemove != null;

  MacroNodeLayout _layoutFor(MacroNode node) =>
      widget.graph.layouts[node.id] ?? MacroNodeLayout(position: Offset(48 + widget.graph.nodes.indexOf(node) * 252, 56));

  Size _sizeFor(MacroNode node) {
    final layout = _layoutFor(node);
    final portCount = math.max(1, node.ports.length);
    final bodyHeight = _bodyHeightFor(node);
    return Size(
      layout.size.width > 0 ? layout.size.width : _nodeWidth,
      layout.size.height > 0 ? layout.size.height : _headerHeight + bodyHeight + _padding + portCount * _portHeight + _padding,
    );
  }

  double _bodyHeightFor(MacroNode node) => math.max(0, widget.nodeBodyHeight?.call(node) ?? 0);

  @override
  void initState() {
    super.initState();
    _viewportController.addListener(_handleViewportChanged);
    _logViewportScale();
    // The viewport has no size until after the first layout. Keep the graph's
    // persisted positions untouched and move only the camera to its center.
    WidgetsBinding.instance.addPostFrameCallback((_) => _positionInitialViewport());
  }

  @override
  void dispose() {
    _viewportController.removeListener(_handleViewportChanged);
    _viewportController.dispose();
    super.dispose();
  }

  void _handleViewportChanged() {
    if (!_isConstrainingViewport) {
      final constrained = _constrainedViewportMatrix(_viewportController.value);
      if (!_matricesMatch(_viewportController.value, constrained)) {
        _isConstrainingViewport = true;
        _viewportController.value = constrained;
        _isConstrainingViewport = false;
      }
    }
    _logViewportScale();
  }

  void _logViewportScale() {
    final scale = _viewportController.value.getMaxScaleOnAxis();
    if ((scale - _lastLoggedViewportScale).abs() < 0.0001) return;
    _lastLoggedViewportScale = scale;
  }

  bool _matricesMatch(Matrix4 first, Matrix4 second) {
    for (var index = 0; index < first.storage.length; index++) {
      if ((first.storage[index] - second.storage[index]).abs() > 0.0001) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    key: _viewportKey,
    child: InteractiveViewer(
      transformationController: _viewportController,
      // This removes InteractiveViewer's own scale boundary entirely. The
      // fixed 8000x8000 canvas is instead enforced after every camera update
      // by [_constrainedViewportMatrix]. A finite margin can still make
      // InteractiveViewer reject a zoom below 1.0 for a bounded child.
      boundaryMargin: EdgeInsets.all(double.infinity),
      constrained: false,
      minScale: _minimumScale,
      maxScale: _maximumScale,
      // This is the sole owner of camera gestures across both the background
      // and cards. Child controls and the node header drag still win their
      // own gesture arenas before a canvas pan can start.
      panEnabled: true,
      scaleEnabled: true,
      child: MouseRegion(
        cursor: _connectingPortId == null ? MouseCursor.defer : SystemMouseCursors.precise,
        onHover: _handlePointerHover,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: ColorScheme.of(context).outlineVariant)),
          child: SizedBox(
            width: _canvasSize.width,
            height: _canvasSize.height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PatchCablePainter(
                      edges: widget.graph.edges,
                      portCenters: _portCenters(),
                      cableGeometries: _cableGeometries(),
                      outputValueLabels: widget.outputValueLabels,
                      pendingFrom: _connectingPortId,
                      pendingTo: _connectionPointer,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) => _handleCanvasTap(details.localPosition),
                  ),
                ),
                for (final node in widget.graph.nodes) _buildNode(context, node),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildNode(BuildContext context, MacroNode node) {
    final layout = _layoutFor(node);
    final size = _sizeFor(node);
    final position = _clampNodePosition(node, layout.position);
    final selected = widget.selectedNodeId == node.id;
    final inputs = node.ports.where((port) => port.direction == MacroPortDirection.input);
    final outputs = node.ports.where((port) => port.direction == MacroPortDirection.output);
    final nodeBody = widget.nodeBodyBuilder?.call(context, node);
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleNodeTap(node.id),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                width: selected ? 2 : 1,
              ),
              boxShadow: const <BoxShadow>[BoxShadow(blurRadius: 6, color: Color(0x33000000))],
            ),
            child: Column(
              children: <Widget>[
                GestureDetector(
                  onTap: () => _handleNodeTap(node.id),
                  onPanStart: (details) => _startNodeDrag(node, details),
                  onPanUpdate: _updateNodeDrag,
                  onPanEnd: (_) => _endNodeDrag(),
                  child: Container(
                    height: _headerHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.drag_indicator, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_nodeTitle(node), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
                if (nodeBody != null)
                  SizedBox(
                    height: _bodyHeightFor(node),
                    child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 0), child: nodeBody),
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
      ),
    );
  }

  Widget _portList(MacroNode node, Iterable<MacroPortDeclaration> ports, bool output) => Column(
    children: ports
        .map(
          (port) => SizedBox(
            height: _portHeight,
            child: GestureDetector(
              key: Key('macro-port-${port.id}'),
              onTapUp: _canEditConnections ? (details) => unawaited(_handlePortTap(port, details.globalPosition)) : null,
              child: Row(
                mainAxisAlignment: output ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: <Widget>[
                  if (!output) _PortDot(type: port.type, selected: _connectingPortId == port.id),
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
                  if (output) _PortDot(type: port.type, selected: _connectingPortId == port.id),
                ],
              ),
            ),
          ),
        )
        .toList(growable: false),
  );

  String _nodeTitle(MacroNode node) {
    final index = widget.graph.nodes.indexWhere((item) => item.id == node.id) + 1;
    final title = widget.nodeTitleBuilder?.call(node) ?? node.displayName ?? node.kind;
    return '[$index] $title';
  }

  void _startNodeDrag(MacroNode node, DragStartDetails details) {
    _cancelConnection();
    _draggingNodeId = node.id;
    _dragPointerCanvasOrigin = _canvasPositionForGlobal(details.globalPosition);
    _nodeOrigin = _clampNodePosition(node, _layoutFor(node).position);
    widget.onSelectionChanged?.call(node.id);
  }

  void _handleNodeTap(String nodeId) {
    if (_connectingPortId != null) {
      _cancelConnection();
      return;
    }
    widget.onSelectionChanged?.call(nodeId);
  }

  void _updateNodeDrag(DragUpdateDetails details) {
    final id = _draggingNodeId;
    if (id == null) return;
    final node = _nodeById(id);
    if (node == null) return;
    final pointerCanvas = _canvasPositionForGlobal(details.globalPosition);
    final position = _clampNodePosition(node, _nodeOrigin + (pointerCanvas - _dragPointerCanvasOrigin));
    widget.onNodeMove?.call(
      id,
      MacroNodeLayout(position: position, size: widget.graph.layouts[id]?.size ?? const Size(_nodeWidth, 0)),
    );
  }

  void _endNodeDrag() => _draggingNodeId = null;

  void _handlePointerHover(PointerHoverEvent event) {
    _lastPointerPosition = event.localPosition;
    if (_connectingPortId != null) {
      setState(() => _connectionPointer = _lastPointerPosition);
    }
  }

  Future<void> _handlePortTap(MacroPortDeclaration port, Offset globalPosition) async {
    final startPortId = _connectingPortId;
    if (startPortId != null) {
      _attemptConnection(startPortId, port.id);
      return;
    }
    final connections = _incidentEdges(port.id);
    if (connections.isEmpty) {
      _beginConnection(port.id);
      return;
    }
    if (connections.length == 1) {
      _detachAndBegin(connections.single, port.id);
      return;
    }
    final selectedEdgeId = await _selectConnectionToDetach(port: port, edges: connections, globalPosition: globalPosition);
    if (!mounted || selectedEdgeId == null) return;
    MacroEdge? selectedEdge;
    for (final edge in widget.graph.edges) {
      if (edge.id == selectedEdgeId) {
        selectedEdge = edge;
        break;
      }
    }
    if (selectedEdge != null) {
      _detachAndBegin(selectedEdge, port.id);
    }
  }

  void _beginConnection(String portId) {
    final portCenter = _portCenters()[portId];
    setState(() {
      _connectingPortId = portId;
      _connectionPointer = _lastPointerPosition ?? portCenter;
    });
  }

  void _detachAndBegin(MacroEdge edge, String clickedPortId) {
    final remainingPortId = edge.fromPortId == clickedPortId ? edge.toPortId : edge.fromPortId;
    widget.onConnectionRemove?.call(edge.id);
    _beginConnection(remainingPortId);
  }

  void _attemptConnection(String startPortId, String endPortId) {
    final connection = _normaliseConnection(startPortId, endPortId);
    if (connection != null && _canCreateConnection(connection)) {
      widget.onConnectionCreate?.call(connection.from, connection.to);
    }
    // An invalid endpoint is deliberately silent and simply drops the cable,
    // matching the patcher flow rather than leaving a stale selection behind.
    _cancelConnection();
  }

  ({String from, String to})? _normaliseConnection(String firstPortId, String secondPortId) {
    if (firstPortId == secondPortId) return null;
    final first = _portById(firstPortId);
    final second = _portById(secondPortId);
    if (first == null || second == null || first.type != second.type) {
      return null;
    }
    if (first.direction == MacroPortDirection.output && second.direction == MacroPortDirection.input) {
      return (from: first.id, to: second.id);
    }
    if (second.direction == MacroPortDirection.output && first.direction == MacroPortDirection.input) {
      return (from: second.id, to: first.id);
    }
    return null;
  }

  bool _canCreateConnection(({String from, String to}) connection) {
    final destination = _portById(connection.to);
    if (destination == null) return false;
    if (widget.graph.edges.any((edge) => edge.fromPortId == connection.from && edge.toPortId == connection.to)) {
      return false;
    }
    return destination.acceptsMultipleInputs || !widget.graph.edges.any((edge) => edge.toPortId == connection.to);
  }

  MacroPortDeclaration? _portById(String portId) {
    for (final port in widget.graph.nodes.expand((node) => node.ports)) {
      if (port.id == portId) return port;
    }
    return null;
  }

  MacroNode? _nodeById(String nodeId) {
    for (final node in widget.graph.nodes) {
      if (node.id == nodeId) return node;
    }
    return null;
  }

  List<MacroEdge> _incidentEdges(String portId) =>
      widget.graph.edges.where((edge) => edge.fromPortId == portId || edge.toPortId == portId).toList(growable: false);

  Future<String?> _selectConnectionToDetach({
    required MacroPortDeclaration port,
    required List<MacroEdge> edges,
    required Offset globalPosition,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx, position.dy, 1, 1), Offset.zero & overlay.size),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(enabled: false, child: Text('Відʼєднати connection')),
        ...edges.map((edge) => PopupMenuItem<String>(value: edge.id, child: Text(_connectionMenuLabel(edge, port.id)))),
      ],
    );
  }

  String _connectionMenuLabel(MacroEdge edge, String clickedPortId) {
    final otherPortId = edge.fromPortId == clickedPortId ? edge.toPortId : edge.fromPortId;
    final otherPort = _portById(otherPortId);
    MacroNode? otherNode;
    for (final node in widget.graph.nodes) {
      if (node.ports.any((port) => port.id == otherPortId)) {
        otherNode = node;
        break;
      }
    }
    if (otherPort == null || otherNode == null) return otherPortId;
    final sameDirectionPorts = otherNode.ports.where((port) => port.direction == otherPort.direction).toList(growable: false);
    final portIndex = sameDirectionPorts.indexWhere((port) => port.id == otherPortId) + 1;
    final direction = otherPort.direction == MacroPortDirection.input ? 'Вхід' : 'Вихід';
    return '${_nodeTitle(otherNode)} · $direction $portIndex: '
        '${otherPort.displayName ?? otherPort.displayIdentifier}';
  }

  void _cancelConnection() {
    if (_connectingPortId == null && _connectionPointer == null) return;
    setState(() {
      _connectingPortId = null;
      _connectionPointer = null;
    });
  }

  void _handleCanvasTap(Offset _) {
    if (_connectingPortId != null) {
      _cancelConnection();
      return;
    }
    widget.onSelectionChanged?.call(null);
  }

  Map<String, _CableGeometry> _cableGeometries() => _buildCableGeometries(edges: widget.graph.edges, portCenters: _portCenters());

  Map<String, Offset> _portCenters() {
    final result = <String, Offset>{};
    for (final node in widget.graph.nodes) {
      final layout = _layoutFor(node);
      final size = _sizeFor(node);
      final position = _clampNodePosition(node, layout.position);
      var input = 0;
      var output = 0;
      for (final port in node.ports) {
        final y =
            position.dy +
            _headerHeight +
            _bodyHeightFor(node) +
            _padding +
            ((port.direction == MacroPortDirection.input ? input++ : output++) * _portHeight) +
            _portHeight / 2;
        result[port.id] = Offset(port.direction == MacroPortDirection.input ? position.dx : position.dx + size.width, y);
      }
    }
    return result;
  }

  Offset _clampNodePosition(MacroNode node, Offset proposedPosition) {
    final nodeSize = _sizeFor(node);
    final bounds = _canvasBounds.deflate(_elementVisualOverflow);
    return Offset(
      proposedPosition.dx.clamp(bounds.left, bounds.right - nodeSize.width).toDouble(),
      proposedPosition.dy.clamp(bounds.top, bounds.bottom - nodeSize.height).toDouble(),
    );
  }

  RenderBox? get _viewportRenderBox {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  Offset _viewportLocalPosition(Offset globalPosition) => _viewportRenderBox?.globalToLocal(globalPosition) ?? globalPosition;

  Offset _canvasPositionForGlobal(Offset globalPosition) => _viewportController.toScene(_viewportLocalPosition(globalPosition));

  void _positionInitialViewport() {
    if (!mounted || _hasPositionedInitialViewport) return;
    _hasPositionedInitialViewport = true;

    final viewportSize = _viewportRenderBox?.size;
    final contentBounds = _nodeBounds();
    if (viewportSize == null || viewportSize.isEmpty || contentBounds == null) {
      return;
    }

    final center = contentBounds.center;
    _setViewportMatrix(
      Matrix4.identity()..setTranslationRaw(viewportSize.width / 2 - center.dx, viewportSize.height / 2 - center.dy, 0),
    );
  }

  Rect? _nodeBounds() {
    Rect? bounds;
    for (final node in widget.graph.nodes) {
      final position = _clampNodePosition(node, _layoutFor(node).position);
      final nodeBounds = position & _sizeFor(node);
      bounds = bounds == null ? nodeBounds : bounds.expandToInclude(nodeBounds);
    }
    return bounds;
  }

  void _setViewportMatrix(Matrix4 candidate) => _viewportController.value = _constrainedViewportMatrix(candidate);

  Matrix4 _constrainedViewportMatrix(Matrix4 candidate) {
    final viewportSize = _viewportRenderBox?.size;
    if (viewportSize == null || viewportSize.isEmpty) return candidate;
    final scale = candidate.getMaxScaleOnAxis();
    final translation = candidate.getTranslation();
    final x = _constrainedTranslation(translation.x, viewportSize.width, _canvasSize.width * scale);
    final y = _constrainedTranslation(translation.y, viewportSize.height, _canvasSize.height * scale);
    return candidate.clone()..setTranslationRaw(x, y, translation.z);
  }

  double _constrainedTranslation(double translation, double viewportExtent, double canvasExtent) {
    if (canvasExtent <= viewportExtent) {
      // 8000 logical pixels remain larger than ordinary editor viewports even
      // at the minimum zoom. This branch only protects unusual huge windows.
      return 0;
    }
    return translation.clamp(viewportExtent - canvasExtent, 0).toDouble();
  }
}

class _PortDot extends StatelessWidget {
  const _PortDot({required this.type, required this.selected});
  final MacroPortType type;
  final bool selected;
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
        MacroPortType.triggerHsv => Colors.pinkAccent,
      },
      border: selected ? Border.all(color: Colors.white, width: 2) : null,
      boxShadow: selected ? const <BoxShadow>[BoxShadow(color: Color(0xCC89B4FA), blurRadius: 8)] : null,
    ),
  );
}

class _PatchCablePainter extends CustomPainter {
  const _PatchCablePainter({
    required this.edges,
    required this.portCenters,
    required this.cableGeometries,
    required this.outputValueLabels,
    this.pendingFrom,
    this.pendingTo,
  });
  final List<MacroEdge> edges;
  final Map<String, Offset> portCenters;
  final Map<String, _CableGeometry> cableGeometries;
  final Map<String, String> outputValueLabels;
  final String? pendingFrom;
  final Offset? pendingTo;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = const Color(0xFF74C7EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final edge in edges) {
      final geometry = cableGeometries[edge.id];
      if (geometry != null) {
        _curve(canvas, paint, geometry);
        final label = outputValueLabels[edge.fromPortId];
        if (label != null && label.isNotEmpty) {
          _label(canvas, label, geometry.pointAt(0.5));
        }
      }
    }
    final from = pendingFrom == null ? null : portCenters[pendingFrom!];
    if (from != null && pendingTo != null) {
      paint.color = const Color(0xFF89B4FA);
      paint.strokeWidth = 2;
      _curve(canvas, paint, _CableGeometry.single(from: from, to: pendingTo!));
    }
  }

  void _curve(Canvas canvas, Paint paint, _CableGeometry geometry) {
    final path = geometry.toPath();
    canvas.drawPath(path, paint);
  }

  void _label(Canvas canvas, String value, Offset cableMidpoint) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(color: Color(0xFFE6E9EF), fontSize: 10, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      ellipsis: '…',
    )..layout(maxWidth: 112);
    const horizontalPadding = 6.0;
    const verticalPadding = 3.0;
    final labelSize = Size(textPainter.width + horizontalPadding * 2, textPainter.height + verticalPadding * 2);
    final origin = Offset(cableMidpoint.dx - labelSize.width / 2, cableMidpoint.dy - labelSize.height - 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(origin & labelSize, const Radius.circular(5)),
      Paint()..color = const Color(0xEE1E1E2E),
    );
    textPainter.paint(canvas, origin + const Offset(horizontalPadding, verticalPadding));
  }

  @override
  bool shouldRepaint(covariant _PatchCablePainter old) =>
      old.edges != edges ||
      old.portCenters != portCenters ||
      old.cableGeometries != cableGeometries ||
      old.outputValueLabels != outputValueLabels ||
      old.pendingFrom != pendingFrom ||
      old.pendingTo != pendingTo;
}

/// Geometry for painting a cable. Fan lanes make concurrent cables visibly
/// distinct beside a shared port.
final class _CableGeometry {
  const _CableGeometry({required this.from, required this.controlA, required this.controlB, required this.to});

  factory _CableGeometry.single({required Offset from, required Offset to}) {
    final horizontalDirection = to.dx >= from.dx ? 1.0 : -1.0;
    final controlDistance = math.max(48.0, (to.dx - from.dx).abs() / 2);
    return _CableGeometry(
      from: from,
      controlA: from + Offset(horizontalDirection * controlDistance, 0),
      controlB: to - Offset(horizontalDirection * controlDistance, 0),
      to: to,
    );
  }

  final Offset from;
  final Offset controlA;
  final Offset controlB;
  final Offset to;

  Path toPath() => Path()
    ..moveTo(from.dx, from.dy)
    ..cubicTo(controlA.dx, controlA.dy, controlB.dx, controlB.dy, to.dx, to.dy);

  Offset pointAt(double t) {
    final inverseT = 1 - t;
    return from * (inverseT * inverseT * inverseT) +
        controlA * (3 * inverseT * inverseT * t) +
        controlB * (3 * inverseT * t * t) +
        to * (t * t * t);
  }
}

Map<String, _CableGeometry> _buildCableGeometries({
  required Iterable<MacroEdge> edges,
  required Map<String, Offset> portCenters,
}) {
  final edgeList = edges.toList(growable: false);
  final result = <String, _CableGeometry>{};
  for (final edge in edgeList) {
    final from = portCenters[edge.fromPortId];
    final to = portCenters[edge.toPortId];
    if (from == null || to == null) continue;
    final sourceEdges = edgeList.where((candidate) => candidate.fromPortId == edge.fromPortId).toList(growable: false);
    final targetEdges = edgeList.where((candidate) => candidate.toPortId == edge.toPortId).toList(growable: false);
    final sourceLane = _fanLane(sourceEdges.indexWhere((candidate) => candidate.id == edge.id), sourceEdges.length);
    final targetLane = _fanLane(targetEdges.indexWhere((candidate) => candidate.id == edge.id), targetEdges.length);
    final horizontalDirection = to.dx >= from.dx ? 1.0 : -1.0;
    final controlDistance = math.max(48.0, (to.dx - from.dx).abs() / 2);
    result[edge.id] = _CableGeometry(
      from: from,
      controlA: from + Offset(horizontalDirection * controlDistance, sourceLane),
      controlB: to - Offset(horizontalDirection * controlDistance, targetLane),
      to: to,
    );
  }
  return result;
}

double _fanLane(int index, int count) => (index - ((count - 1) / 2)) * 18;
