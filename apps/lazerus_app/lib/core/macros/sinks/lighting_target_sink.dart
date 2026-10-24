import 'package:lazerus_core/lazerus_core.dart';

/// Input-only graph node that represents a saved lighting device on the plot.
///
/// The runtime's portable [MacroTargetBinding] remains the delivery contract;
/// the editor derives those bindings from incoming edges to this sink. The
/// sink itself intentionally has no transport dependency and ignores routed
/// events, because the runtime emits the binding intent from the edge source.
const String lightingTargetSinkKind = 'sink.lighting_target';

final class LightingTargetNodeConfiguration {
  LightingTargetNodeConfiguration({
    required this.targetId,
    required Iterable<MacroTargetParameter> parameters,
  }) : parameters = List<MacroTargetParameter>.unmodifiable(parameters) {
    if (targetId.trim().isEmpty) {
      throw ArgumentError.value(targetId, 'targetId', 'Must not be blank.');
    }
    if (this.parameters.isEmpty) {
      throw ArgumentError.value(
        parameters,
        'parameters',
        'At least one target input is required.',
      );
    }
    if (this.parameters.toSet().length != this.parameters.length) {
      throw ArgumentError.value(
        parameters,
        'parameters',
        'Parameters must be unique.',
      );
    }
  }

  final String targetId;
  final List<MacroTargetParameter> parameters;

  Map<String, Object?> toNodeParameters() => <String, Object?>{
    'targetId': targetId,
    'parameters': parameters.map((parameter) => parameter.name).toList(),
  };

  factory LightingTargetNodeConfiguration.fromNode(MacroNode node) {
    if (node.kind != lightingTargetSinkKind) {
      throw FormatException('The node is not a lighting target sink.');
    }
    final rawTargetId = node.parameters['targetId'];
    final rawParameters = node.parameters['parameters'];
    if (rawTargetId is! String) {
      throw FormatException('Target ID must be a string.');
    }
    if (rawParameters is! List<Object?>) {
      throw FormatException('Target parameters must be a list.');
    }
    return LightingTargetNodeConfiguration(
      targetId: rawTargetId,
      parameters: rawParameters.map((raw) {
        if (raw is! String) {
          throw FormatException('Target parameter must be a string.');
        }
        final parameter = MacroTargetParameter.values.where(
          (candidate) => candidate.name == raw,
        );
        if (parameter.isEmpty) {
          throw FormatException('Unknown target parameter "$raw".');
        }
        return parameter.single;
      }),
    );
  }

  List<MacroPortDeclaration> portsForNode(String nodeId) => parameters
      .map(
        (parameter) => MacroPortDeclaration(
          id: '$nodeId.${parameter.name}',
          direction: MacroPortDirection.input,
          type: _portTypeFor(parameter),
          displayIdentifier: 'target.${parameter.name}',
          displayName: _displayNameFor(parameter),
          // A physical target can expose several optional controls. An edge
          // creates a binding; an unconnected target input must not invalidate
          // the graph.
          required: false,
        ),
      )
      .toList(growable: false);

  static MacroPortType _portTypeFor(MacroTargetParameter parameter) =>
      switch (parameter) {
        MacroTargetParameter.power => MacroPortType.triggerGate,
        MacroTargetParameter.brightness => MacroPortType.triggerLevel,
        MacroTargetParameter.color => MacroPortType.triggerHsv,
      };

  static String _displayNameFor(MacroTargetParameter parameter) =>
      switch (parameter) {
        MacroTargetParameter.power => 'Power',
        MacroTargetParameter.brightness => 'Brightness',
        MacroTargetParameter.color => 'Color',
      };
}

final class LightingTargetSinkFactory
    implements MacroModuleFactory, MacroNodePortContractProvider {
  @override
  String get kind => lightingTargetSinkKind;

  /// Target ports are configured per selected device.
  @override
  List<MacroPortDeclaration> get ports => const <MacroPortDeclaration>[];

  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) =>
      LightingTargetNodeConfiguration.fromNode(node).portsForNode(node.id);

  @override
  MacroModuleInstance create(MacroNode node) {
    // Validate configuration while preparing, too, so a direct runtime caller
    // cannot create an unconfigured no-op target instance.
    LightingTargetNodeConfiguration.fromNode(node);
    return const _LightingTargetSinkInstance();
  }
}

final class _LightingTargetSinkInstance implements MacroModuleInstance {
  const _LightingTargetSinkInstance();

  @override
  void start(MacroRuntimeEventEmitter emitter) {}

  @override
  void onInput(String inputPortId, TriggerEvent event) {}

  @override
  void stop() {}
}
