/// The value family carried by an edge in a Macro graph.
enum MacroPortType {
  /// A mono PCM sample array with a required, positive sample rate.
  triggerMonoAudio,

  /// A generic numeric array. It deliberately has no audio metadata.
  triggerArray,

  /// A binary event value.
  triggerGate,

  /// A normalized, continuous event value in the inclusive range 0..1.
  triggerLevel,

  /// A HSV colour value. Hue is expressed in degrees and saturation/value are
  /// normalized, allowing colour-producing modules to remain independent from
  /// protocol-specific RGB, RGBW, or CCT encoders.
  triggerHsv,
}

/// The direction of a port declared by a trigger or modifier module.
enum MacroPortDirection { input, output }

/// Static port metadata exposed by an independently registered module.
///
/// This belongs to the macro graph contract so that triggers and modifiers can
/// declare compatible ports without depending on one another.
final class MacroPortDeclaration {
  MacroPortDeclaration({
    required this.id,
    required this.direction,
    required this.type,
    required this.displayIdentifier,
    this.displayName,
    this.required = true,
    this.acceptsMultipleInputs = false,
  }) {
    _requireMacroId(id, 'id');
    _requireMacroId(displayIdentifier, 'displayIdentifier');
    if (acceptsMultipleInputs && direction != MacroPortDirection.input) {
      throw ArgumentError.value(
        acceptsMultipleInputs,
        'acceptsMultipleInputs',
        'Only input ports can accept multiple inputs.',
      );
    }
  }

  final String id;
  final MacroPortDirection direction;
  final MacroPortType type;
  final String displayIdentifier;
  final String? displayName;
  final bool required;
  final bool acceptsMultipleInputs;
}

void _requireMacroId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be blank.');
  }
}
