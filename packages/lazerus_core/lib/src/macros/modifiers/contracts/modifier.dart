import '../../contracts/macro_port.dart';

/// Public declaration implemented by an independently registered modifier.
///
/// A modifier can transform trigger events but is not allowed to depend on a
/// sibling trigger or modifier implementation.
abstract interface class MacroModifierDefinition {
  String get kind;
  String get displayName;
  List<MacroPortDeclaration> get ports;
}
