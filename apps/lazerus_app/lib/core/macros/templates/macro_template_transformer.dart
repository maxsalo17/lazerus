import 'package:lazerus_core/lazerus_core.dart';

import '../sinks/lighting_target_sink.dart';
import 'macro_template.dart';

const String macroTemplateDevicePlaceholderPrefix = 'template-device:';

/// Converts saved Macro graphs to and from portable device-free templates.
///
/// This boundary knows the shape of the installed lighting-target node, but
/// does not know about discovered devices, UI widgets, files or transports.
final class MacroTemplateTransformer {
  const MacroTemplateTransformer();

  MacroTemplate export(MacroGraph macro) {
    var nextPlaceholderIndex = 1;
    final placeholders = <MacroTemplateDevicePlaceholder>[];
    final targetInputs = <String, _TemplateTargetInput>{};
    final nodes = <MacroNode>[];

    for (final node in macro.nodes) {
      if (node.kind != lightingTargetSinkKind) {
        nodes.add(node);
        continue;
      }
      final configuration = LightingTargetNodeConfiguration.fromNode(node);
      final index = nextPlaceholderIndex++;
      final placeholder = MacroTemplateDevicePlaceholder(
        id: '$macroTemplateDevicePlaceholderPrefix$index',
        nodeId: node.id,
        requiredParameters: configuration.parameters,
      );
      placeholders.add(placeholder);
      for (final parameter in configuration.parameters) {
        targetInputs['${node.id}.${parameter.name}'] = _TemplateTargetInput(
          placeholderId: placeholder.id,
          parameter: parameter,
        );
      }
      nodes.add(
        _targetNode(
          node: node,
          targetId: placeholder.id,
          displayName: _placeholderLabel(index),
          parameters: configuration.parameters,
        ),
      );
    }

    final bindings = <MacroTargetBinding>[];
    for (final edge in macro.edges) {
      final target = targetInputs[edge.toPortId];
      if (target == null) continue;
      bindings.add(
        MacroTargetBinding(
          id: 'target-edge-${edge.id}',
          sourcePortId: edge.fromPortId,
          targetId: target.placeholderId,
          parameter: target.parameter,
        ),
      );
    }
    _ensureBindingsCanBeExported(macro, bindings);

    return MacroTemplate(
      name: macro.name,
      graph: macro.copyWith(
        // A template must not reuse a source macro identity when imported.
        id: 'template-macro',
        nodes: nodes,
        targetBindings: bindings,
      ),
      placeholders: placeholders,
    );
  }

  /// Produces a new saved Macro after verifying that it contains placeholders
  /// only, never a source installation's target identifiers.
  MacroGraph importTemplate(
    MacroTemplate template, {
    required String newMacroId,
  }) {
    _validateTemplate(template);
    return template.graph.copyWith(id: newMacroId, name: template.name);
  }

  /// Rebuilds one imported target node with a selected local device.
  ///
  /// The node and its port identifiers are retained, so all existing graph
  /// edges and positions remain valid. The editor re-derives bindings after
  /// receiving this replacement.
  MacroNode replacePlaceholderNode({
    required MacroNode node,
    required String appDeviceId,
    required String deviceName,
  }) {
    final configuration = LightingTargetNodeConfiguration.fromNode(node);
    if (!isMacroTemplateDevicePlaceholderId(configuration.targetId)) {
      throw ArgumentError.value(
        node,
        'node',
        'The node is not an imported template placeholder.',
      );
    }
    return _targetNode(
      node: node,
      targetId: appDeviceId,
      displayName: deviceName,
      parameters: configuration.parameters,
    );
  }

  bool isMacroTemplateDevicePlaceholderId(String targetId) =>
      targetId.startsWith(macroTemplateDevicePlaceholderPrefix);

  /// Creates a runtime-only view that skips unmapped template targets.
  ///
  /// The saved graph remains intact and repairable on the canvas. Filtering a
  /// binding here ensures a placeholder never reaches the delivery bridge as
  /// an app device ID while the rest of the Macro can still run.
  MacroGraph executionGraph(MacroGraph graph) => graph.copyWith(
    targetBindings: graph.targetBindings.where(
      (binding) => !isMacroTemplateDevicePlaceholderId(binding.targetId),
    ),
  );

  String placeholderLabelFor(String targetId) {
    if (!isMacroTemplateDevicePlaceholderId(targetId)) return targetId;
    final suffix = targetId.substring(
      macroTemplateDevicePlaceholderPrefix.length,
    );
    return suffix.isEmpty ? 'Device placeholder' : 'Device placeholder $suffix';
  }

  MacroNode _targetNode({
    required MacroNode node,
    required String targetId,
    required String displayName,
    required Iterable<MacroTargetParameter> parameters,
  }) {
    final configuration = LightingTargetNodeConfiguration(
      targetId: targetId,
      parameters: parameters,
    );
    return MacroNode(
      id: node.id,
      kind: node.kind,
      displayName: displayName,
      ports: configuration.portsForNode(node.id),
      parameters: configuration.toNodeParameters(),
    );
  }

  void _ensureBindingsCanBeExported(
    MacroGraph macro,
    List<MacroTargetBinding> derivedBindings,
  ) {
    final derivedBindingIds = derivedBindings
        .map((binding) => binding.id)
        .toSet();
    for (final binding in macro.targetBindings) {
      if (!derivedBindingIds.contains(binding.id)) {
        throw FormatException(
          'The macro has a legacy device binding without a repairable target '
          'node. Open and save the macro before exporting it.',
        );
      }
    }
  }

  void _validateTemplate(MacroTemplate template) {
    final placeholders = <String, MacroTemplateDevicePlaceholder>{
      for (final placeholder in template.placeholders)
        placeholder.id: placeholder,
    };
    final placeholderNodeIds = <String>{};
    for (final node in template.graph.nodes) {
      if (node.kind != lightingTargetSinkKind) continue;
      final configuration = LightingTargetNodeConfiguration.fromNode(node);
      final placeholder = placeholders[configuration.targetId];
      if (placeholder == null ||
          !isMacroTemplateDevicePlaceholderId(configuration.targetId)) {
        throw FormatException(
          'A template lighting target must use a declared device placeholder.',
        );
      }
      if (placeholder.nodeId != node.id ||
          !_sameParameters(
            placeholder.requiredParameters,
            configuration.parameters,
          )) {
        throw FormatException(
          'The template placeholder does not match its target node.',
        );
      }
      placeholderNodeIds.add(node.id);
    }
    if (placeholderNodeIds.length != template.placeholders.length) {
      throw FormatException(
        'Every template placeholder must have exactly one target node.',
      );
    }
    for (final binding in template.graph.targetBindings) {
      if (!placeholders.containsKey(binding.targetId)) {
        throw FormatException(
          'A template binding must target a declared device placeholder.',
        );
      }
    }
  }

  bool _sameParameters(
    Iterable<MacroTargetParameter> first,
    Iterable<MacroTargetParameter> second,
  ) {
    final firstValues = first.toList(growable: false);
    final secondValues = second.toList(growable: false);
    if (firstValues.length != secondValues.length) return false;
    return firstValues.toSet().containsAll(secondValues) &&
        secondValues.toSet().containsAll(firstValues);
  }

  String _placeholderLabel(int index) => 'Device placeholder $index';
}

final class _TemplateTargetInput {
  const _TemplateTargetInput({
    required this.placeholderId,
    required this.parameter,
  });

  final String placeholderId;
  final MacroTargetParameter parameter;
}
