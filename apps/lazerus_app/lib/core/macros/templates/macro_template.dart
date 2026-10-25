import 'package:lazerus_core/lazerus_core.dart';

/// Current version of the portable Macro-template document schema.
const int currentMacroTemplateSchemaVersion = 1;

/// A portable Macro graph with explicit, non-device target placeholders.
///
/// A template is deliberately separate from [MacroGraph]'s persistence schema:
/// its graph may contain only template-local target IDs and is always assigned
/// a fresh [MacroGraph.id] when imported into a library.
final class MacroTemplate {
  MacroTemplate({
    required this.name,
    required this.graph,
    required Iterable<MacroTemplateDevicePlaceholder> placeholders,
    this.schemaVersion = currentMacroTemplateSchemaVersion,
  }) : placeholders = List<MacroTemplateDevicePlaceholder>.unmodifiable(
         placeholders,
       ) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be blank.');
    }
    if (schemaVersion <= 0) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Must be greater than zero.',
      );
    }
    final placeholderIds = this.placeholders
        .map((placeholder) => placeholder.id)
        .toSet();
    if (placeholderIds.length != this.placeholders.length) {
      throw ArgumentError.value(
        placeholders,
        'placeholders',
        'Placeholder IDs must be unique.',
      );
    }
    final nodeIds = this.placeholders
        .map((placeholder) => placeholder.nodeId)
        .toSet();
    if (nodeIds.length != this.placeholders.length) {
      throw ArgumentError.value(
        placeholders,
        'placeholders',
        'Each placeholder must own one node.',
      );
    }
  }

  final String name;
  final MacroGraph graph;
  final int schemaVersion;
  final List<MacroTemplateDevicePlaceholder> placeholders;

  Map<String, Object?> toJson() => <String, Object?>{
    'templateSchemaVersion': schemaVersion,
    'name': name,
    'graph': graph.toJson(),
    'placeholders': placeholders
        .map((placeholder) => placeholder.toJson())
        .toList(growable: false),
  };

  factory MacroTemplate.fromJson(Map<String, Object?> json) {
    final schemaVersion = _requiredInt(json, 'templateSchemaVersion');
    if (schemaVersion > currentMacroTemplateSchemaVersion) {
      throw FormatException(
        'Unsupported future macro template schema version: $schemaVersion.',
      );
    }
    return MacroTemplate(
      schemaVersion: schemaVersion,
      name: _requiredString(json, 'name'),
      graph: MacroGraph.fromJson(_requiredMap(json, 'graph')),
      placeholders: _requiredMapList(
        json,
        'placeholders',
      ).map(MacroTemplateDevicePlaceholder.fromJson),
    );
  }
}

/// One portable target requirement that must be explicitly mapped after import.
final class MacroTemplateDevicePlaceholder {
  MacroTemplateDevicePlaceholder({
    required this.id,
    required this.nodeId,
    required Iterable<MacroTargetParameter> requiredParameters,
  }) : requiredParameters = List<MacroTargetParameter>.unmodifiable(
         requiredParameters,
       ) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (nodeId.trim().isEmpty) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Must not be blank.');
    }
    if (this.requiredParameters.isEmpty) {
      throw ArgumentError.value(
        requiredParameters,
        'requiredParameters',
        'At least one required parameter is needed.',
      );
    }
    if (this.requiredParameters.toSet().length !=
        this.requiredParameters.length) {
      throw ArgumentError.value(
        requiredParameters,
        'requiredParameters',
        'Parameters must be unique.',
      );
    }
  }

  final String id;
  final String nodeId;
  final List<MacroTargetParameter> requiredParameters;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'nodeId': nodeId,
    'requiredParameters': requiredParameters
        .map((parameter) => parameter.name)
        .toList(growable: false),
  };

  factory MacroTemplateDevicePlaceholder.fromJson(Map<String, Object?> json) {
    return MacroTemplateDevicePlaceholder(
      id: _requiredString(json, 'id'),
      nodeId: _requiredString(json, 'nodeId'),
      requiredParameters: _requiredStringList(
        json,
        'requiredParameters',
      ).map(_targetParameterByName),
    );
  }
}

MacroTargetParameter _targetParameterByName(String value) {
  for (final parameter in MacroTargetParameter.values) {
    if (parameter.name == value) return parameter;
  }
  throw FormatException('Unknown target parameter "$value".');
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected non-blank string at $field.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) {
    throw FormatException('Expected integer at $field.');
  }
  return value;
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String field) {
  if (!json.containsKey(field)) {
    throw FormatException('Missing $field.');
  }
  return _asMap(json[field], field);
}

List<Map<String, Object?>> _requiredMapList(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value is! List) {
    throw FormatException('Expected list at $field.');
  }
  return List<Map<String, Object?>>.unmodifiable(
    value.map((item) => _asMap(item, field)),
  );
}

List<String> _requiredStringList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! List) {
    throw FormatException('Expected list at $field.');
  }
  return List<String>.unmodifiable(
    value.map((item) {
      if (item is! String || item.trim().isEmpty) {
        throw FormatException('Expected non-blank string in $field.');
      }
      return item;
    }),
  );
}

Map<String, Object?> _asMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('Expected object at $field.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('Expected string key at $field.');
    }
    result[entry.key as String] = entry.value;
  }
  return Map<String, Object?>.unmodifiable(result);
}
