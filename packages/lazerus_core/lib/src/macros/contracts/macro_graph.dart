import 'macro_port.dart';

/// Current version of the persisted Scene Macro graph document schema.
const int currentMacroGraphSchemaVersion = 1;

/// A persisted, reusable graph configuration. Runtime streams and values are
/// deliberately excluded.
final class MacroGraph {
  MacroGraph({
    required this.id,
    required this.name,
    required Iterable<MacroNode> nodes,
    required Iterable<MacroEdge> edges,
    Iterable<MacroTargetBinding> targetBindings = const <MacroTargetBinding>[],
    this.schemaVersion = currentMacroGraphSchemaVersion,
    Map<String, MacroEditorPosition> editorPositions =
        const <String, MacroEditorPosition>{},
  }) : nodes = List<MacroNode>.unmodifiable(nodes),
       edges = List<MacroEdge>.unmodifiable(edges),
       targetBindings = List<MacroTargetBinding>.unmodifiable(targetBindings),
       editorPositions = Map<String, MacroEditorPosition>.unmodifiable(
         editorPositions,
       ) {
    _requireId(id, 'id');
    _requireId(name, 'name');
    if (schemaVersion <= 0) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Must be greater than zero.',
      );
    }
    _requireUnique(this.nodes.map((node) => node.id), 'node IDs');
    _requireUnique(this.edges.map((edge) => edge.id), 'edge IDs');
    _requireUnique(
      this.targetBindings.map((binding) => binding.id),
      'binding IDs',
    );
    for (final nodeId in this.editorPositions.keys) {
      _requireId(nodeId, 'editorPositions key');
    }
  }

  final String id;
  final String name;
  final int schemaVersion;
  final List<MacroNode> nodes;
  final List<MacroEdge> edges;
  final List<MacroTargetBinding> targetBindings;
  final Map<String, MacroEditorPosition> editorPositions;

  /// Produces another immutable graph definition for editor operations.
  ///
  /// Runtime state is deliberately absent: callers persist the returned graph
  /// and construct a fresh runtime only after it has passed validation.
  MacroGraph copyWith({
    String? id,
    String? name,
    int? schemaVersion,
    Iterable<MacroNode>? nodes,
    Iterable<MacroEdge>? edges,
    Iterable<MacroTargetBinding>? targetBindings,
    Map<String, MacroEditorPosition>? editorPositions,
  }) => MacroGraph(
    id: id ?? this.id,
    name: name ?? this.name,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    nodes: nodes ?? this.nodes,
    edges: edges ?? this.edges,
    targetBindings: targetBindings ?? this.targetBindings,
    editorPositions: editorPositions ?? this.editorPositions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
    'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
    'targetBindings': targetBindings
        .map((binding) => binding.toJson())
        .toList(growable: false),
    'editorPositions': editorPositions.map(
      (nodeId, position) =>
          MapEntry<String, Object?>(nodeId, position.toJson()),
    ),
  };

  factory MacroGraph.fromJson(Map<String, Object?> json) {
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion > currentMacroGraphSchemaVersion) {
      throw FormatException(
        'Unsupported future macro schema version: $schemaVersion.',
      );
    }
    return MacroGraph(
      schemaVersion: schemaVersion,
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      nodes: _requiredMapList(json, 'nodes').map(MacroNode.fromJson),
      edges: _requiredMapList(json, 'edges').map(MacroEdge.fromJson),
      targetBindings: _optionalMapList(
        json,
        'targetBindings',
      ).map(MacroTargetBinding.fromJson),
      editorPositions: _optionalMap(json, 'editorPositions').map(
        (nodeId, value) => MapEntry<String, MacroEditorPosition>(
          nodeId,
          MacroEditorPosition.fromJson(
            _asMap(value, 'editorPositions.$nodeId'),
          ),
        ),
      ),
    );
  }
}

/// One configured module instance in a [MacroGraph].
final class MacroNode {
  MacroNode({
    required this.id,
    required this.kind,
    required Iterable<MacroPortDeclaration> ports,
    this.displayName,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) : ports = List<MacroPortDeclaration>.unmodifiable(ports),
       parameters = _freezeJsonObjectMap(parameters, 'parameters') {
    _requireId(id, 'id');
    _requireId(kind, 'kind');
    _requireUnique(this.ports.map((port) => port.id), 'port IDs on node $id');
  }

  final String id;
  final String kind;
  final String? displayName;
  final List<MacroPortDeclaration> ports;
  final Map<String, Object?> parameters;

  /// Produces another immutable configured module node for editor operations.
  MacroNode copyWith({
    String? id,
    String? kind,
    String? displayName,
    bool clearDisplayName = false,
    Iterable<MacroPortDeclaration>? ports,
    Map<String, Object?>? parameters,
  }) => MacroNode(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    displayName: clearDisplayName ? null : displayName ?? this.displayName,
    ports: ports ?? this.ports,
    parameters: parameters ?? this.parameters,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    if (displayName != null) 'displayName': displayName,
    'ports': ports.map(_portToJson).toList(growable: false),
    'parameters': parameters,
  };

  factory MacroNode.fromJson(Map<String, Object?> json) => MacroNode(
    id: _requiredString(json, 'id'),
    kind: _requiredString(json, 'kind'),
    displayName: _optionalString(json, 'displayName'),
    ports: _requiredMapList(json, 'ports').map(_portFromJson),
    parameters: _optionalMap(json, 'parameters'),
  );
}

/// A directed connection between two graph port IDs.
final class MacroEdge {
  MacroEdge({
    required this.id,
    required this.fromPortId,
    required this.toPortId,
  }) {
    _requireId(id, 'id');
    _requireId(fromPortId, 'fromPortId');
    _requireId(toPortId, 'toPortId');
  }

  final String id;
  final String fromPortId;
  final String toPortId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fromPortId': fromPortId,
    'toPortId': toPortId,
  };

  factory MacroEdge.fromJson(Map<String, Object?> json) => MacroEdge(
    id: _requiredString(json, 'id'),
    fromPortId: _requiredString(json, 'fromPortId'),
    toPortId: _requiredString(json, 'toPortId'),
  );
}

enum MacroTargetKind { device, group }

/// A capability-neutral target parameter that can receive a trigger value.
enum MacroTargetParameter { brightness, power, color }

/// A graph output mapping to one saved device or group reference.
final class MacroTargetBinding {
  MacroTargetBinding({
    required this.id,
    required this.sourcePortId,
    required this.targetKind,
    required this.targetId,
    required this.parameter,
  }) {
    _requireId(id, 'id');
    _requireId(sourcePortId, 'sourcePortId');
    _requireId(targetId, 'targetId');
  }

  final String id;
  final String sourcePortId;
  final MacroTargetKind targetKind;
  final String targetId;
  final MacroTargetParameter parameter;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sourcePortId': sourcePortId,
    'targetKind': targetKind.name,
    'targetId': targetId,
    'parameter': parameter.name,
  };

  factory MacroTargetBinding.fromJson(Map<String, Object?> json) =>
      MacroTargetBinding(
        id: _requiredString(json, 'id'),
        sourcePortId: _requiredString(json, 'sourcePortId'),
        targetKind: _enumByName(
          MacroTargetKind.values,
          _requiredString(json, 'targetKind'),
          'targetKind',
        ),
        targetId: _requiredString(json, 'targetId'),
        parameter: _enumByName(
          MacroTargetParameter.values,
          _requiredString(json, 'parameter'),
          'parameter',
        ),
      );
}

/// Persisted editor-only position. It does not affect graph execution.
final class MacroEditorPosition {
  MacroEditorPosition({required this.x, required this.y}) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Editor positions must be finite.');
    }
  }

  final double x;
  final double y;

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};

  factory MacroEditorPosition.fromJson(Map<String, Object?> json) =>
      MacroEditorPosition(
        x: _requiredDouble(json, 'x'),
        y: _requiredDouble(json, 'y'),
      );
}

/// A repairable reference from a Scene configuration to a saved macro.
final class SceneMacroReference {
  SceneMacroReference({required this.macroId}) {
    _requireId(macroId, 'macroId');
  }

  final String macroId;

  Map<String, Object?> toJson() => <String, Object?>{'macroId': macroId};

  factory SceneMacroReference.fromJson(Map<String, Object?> json) =>
      SceneMacroReference(macroId: _requiredString(json, 'macroId'));

  @override
  bool operator ==(Object other) =>
      other is SceneMacroReference && other.macroId == macroId;

  @override
  int get hashCode => macroId.hashCode;
}

Map<String, Object?> _portToJson(MacroPortDeclaration port) =>
    <String, Object?>{
      'id': port.id,
      'direction': port.direction.name,
      'type': port.type.name,
      'displayIdentifier': port.displayIdentifier,
      if (port.displayName != null) 'displayName': port.displayName,
      'required': port.required,
      'acceptsMultipleInputs': port.acceptsMultipleInputs,
    };

MacroPortDeclaration _portFromJson(Map<String, Object?> json) =>
    MacroPortDeclaration(
      id: _requiredString(json, 'id'),
      direction: _enumByName(
        MacroPortDirection.values,
        _requiredString(json, 'direction'),
        'direction',
      ),
      type: _enumByName(
        MacroPortType.values,
        _requiredString(json, 'type'),
        'type',
      ),
      displayIdentifier: _requiredString(json, 'displayIdentifier'),
      displayName: _optionalString(json, 'displayName'),
      required: _optionalBool(json, 'required', defaultValue: true),
      acceptsMultipleInputs: _optionalBool(
        json,
        'acceptsMultipleInputs',
        defaultValue: false,
      ),
    );

T _enumByName<T extends Enum>(List<T> values, String value, String field) {
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  throw FormatException('Invalid $field: $value.');
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected non-blank string at $field.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) throw FormatException('Expected string at $field.');
  return value;
}

int _requiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) throw FormatException('Expected integer at $field.');
  return value;
}

double _requiredDouble(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! num || !value.isFinite) {
    throw FormatException('Expected finite number at $field.');
  }
  return value.toDouble();
}

bool _optionalBool(
  Map<String, Object?> json,
  String field, {
  required bool defaultValue,
}) {
  final value = json[field];
  if (value == null) return defaultValue;
  if (value is! bool) throw FormatException('Expected bool at $field.');
  return value;
}

List<Map<String, Object?>> _requiredMapList(
  Map<String, Object?> json,
  String field,
) {
  if (!json.containsKey(field)) throw FormatException('Missing $field.');
  return _mapList(json[field], field);
}

List<Map<String, Object?>> _optionalMapList(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  return value == null
      ? const <Map<String, Object?>>[]
      : _mapList(value, field);
}

List<Map<String, Object?>> _mapList(Object? value, String field) {
  if (value is! List) throw FormatException('Expected list at $field.');
  return List<Map<String, Object?>>.unmodifiable(
    value.map((item) => _asMap(item, field)),
  );
}

Map<String, Object?> _optionalMap(Map<String, Object?> json, String field) {
  final value = json[field];
  return value == null ? const <String, Object?>{} : _asMap(value, field);
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is! Map) throw FormatException('Expected object at $field.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('Expected string key at $field.');
    }
    result[entry.key as String] = entry.value;
  }
  return Map<String, Object?>.unmodifiable(result);
}

/// Makes persisted configuration values deeply immutable and rejects values
/// which cannot be encoded as ordinary JSON. This keeps a graph immutable even
/// when callers retain mutable nested parameter collections.
Map<String, Object?> _freezeJsonObjectMap(
  Map<String, Object?> value,
  String field,
) => Map<String, Object?>.unmodifiable(
  value.map(
    (key, entryValue) => MapEntry<String, Object?>(
      key,
      _freezeJsonValue(entryValue, '$field.$key'),
    ),
  ),
);

Object? _freezeJsonValue(Object? value, String field) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, field, 'JSON numbers must be finite.');
    }
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.indexed.map(
        (entry) => _freezeJsonValue(entry.$2, '$field[${entry.$1}]'),
      ),
    );
  }
  if (value is Map) {
    final object = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(
          entry.key,
          field,
          'JSON object keys must be strings.',
        );
      }
      object[entry.key as String] = _freezeJsonValue(
        entry.value,
        '$field.${entry.key}',
      );
    }
    return Map<String, Object?>.unmodifiable(object);
  }
  throw ArgumentError.value(value, field, 'Must be a JSON-compatible value.');
}

void _requireId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be blank.');
  }
}

void _requireUnique(Iterable<String> values, String description) {
  final list = values.toList(growable: false);
  if (list.toSet().length != list.length) {
    throw ArgumentError.value(values, description, 'Must be unique.');
  }
}
