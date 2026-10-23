import 'dart:collection';

const int sceneConfigurationSchemaVersion = 1;

/// A stable local reference to a target that participates in a Scene.
///
/// Group references resolve their current membership at runtime. Device
/// references use Lazerus' application-generated device ID, never a mutable
/// platform BLE identifier.
enum SceneTargetType { group, device }

class SceneTargetReference {
  SceneTargetReference({required this.type, required this.targetId}) {
    if (targetId.trim().isEmpty) {
      throw ArgumentError.value(targetId, 'targetId', 'Must not be empty.');
    }
  }

  final SceneTargetType type;
  final String targetId;

  Map<String, Object> toJson() => <String, Object>{
    'type': type.name,
    'targetId': targetId,
  };

  static SceneTargetReference? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final typeName = value['type'];
    final targetId = value['targetId'];
    if (typeName is! String || targetId is! String) {
      return null;
    }
    final type = SceneTargetType.values.where(
      (candidate) => candidate.name == typeName,
    );
    if (type.isEmpty) {
      return null;
    }
    try {
      return SceneTargetReference(type: type.first, targetId: targetId);
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SceneTargetReference &&
      other.type == type &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(type, targetId);
}

enum SceneControlType { toggle, brightnessSlider, colorSlider }

enum SceneParameter { power, brightness, color }

extension SceneControlTypeParameter on SceneControlType {
  SceneParameter get parameter => switch (this) {
    SceneControlType.toggle => SceneParameter.power,
    SceneControlType.brightnessSlider => SceneParameter.brightness,
    SceneControlType.colorSlider => SceneParameter.color,
  };
}

/// One target parameter linked to a user-created Scene control.
class SceneControlBinding {
  const SceneControlBinding({required this.target, required this.parameter});

  final SceneTargetReference target;
  final SceneParameter parameter;

  Map<String, Object> toJson() => <String, Object>{
    'target': target.toJson(),
    'parameter': parameter.name,
  };

  static SceneControlBinding? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final target = SceneTargetReference.fromJson(value['target']);
    final parameterName = value['parameter'];
    if (target == null || parameterName is! String) {
      return null;
    }
    final parameter = SceneParameter.values.where(
      (candidate) => candidate.name == parameterName,
    );
    if (parameter.isEmpty) {
      return null;
    }
    return SceneControlBinding(target: target, parameter: parameter.first);
  }

  @override
  bool operator ==(Object other) =>
      other is SceneControlBinding &&
      other.target == target &&
      other.parameter == parameter;

  @override
  int get hashCode => Object.hash(target, parameter);
}

/// A user-configured control. Its value is runtime state and is never stored
/// here as though it were a confirmed controller state.
class SceneCustomControl {
  SceneCustomControl({
    required this.id,
    required this.type,
    Iterable<SceneControlBinding> bindings = const <SceneControlBinding>[],
    this.label,
  }) : bindings = UnmodifiableListView<SceneControlBinding>(
         List<SceneControlBinding>.from(bindings),
       ) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (label != null && label!.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be blank.');
    }
    if (this.bindings.isEmpty) {
      throw ArgumentError.value(
        bindings,
        'bindings',
        'A control needs at least one binding.',
      );
    }
    if (this.bindings.any((binding) => binding.parameter != type.parameter)) {
      throw ArgumentError(
        'All bindings must match the control parameter ${type.parameter.name}.',
      );
    }
    if (this.bindings.toSet().length != this.bindings.length) {
      throw ArgumentError('A control cannot contain duplicate bindings.');
    }
  }

  final String id;
  final SceneControlType type;
  final String? label;
  final List<SceneControlBinding> bindings;

  SceneCustomControl copyWith({
    String? id,
    SceneControlType? type,
    String? label,
    bool clearLabel = false,
    Iterable<SceneControlBinding>? bindings,
  }) {
    return SceneCustomControl(
      id: id ?? this.id,
      type: type ?? this.type,
      label: clearLabel ? null : label ?? this.label,
      bindings: bindings ?? this.bindings,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type.name,
    'label': label,
    'bindings': bindings.map((binding) => binding.toJson()).toList(),
  };

  static SceneCustomControl? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final id = value['id'];
    final typeName = value['type'];
    final label = value['label'];
    final rawBindings = value['bindings'];
    if (id is! String ||
        typeName is! String ||
        (label != null && label is! String) ||
        rawBindings is! List<Object?>) {
      return null;
    }
    final type = SceneControlType.values.where(
      (candidate) => candidate.name == typeName,
    );
    final bindings = rawBindings
        .map(SceneControlBinding.fromJson)
        .whereType<SceneControlBinding>()
        .toList(growable: false);
    if (type.isEmpty || bindings.length != rawBindings.length) {
      return null;
    }
    try {
      return SceneCustomControl(
        id: id,
        type: type.first,
        label: label as String?,
        bindings: bindings,
      );
    } on ArgumentError {
      return null;
    }
  }
}

/// A stable layout position that may be unconfigured or contain one control.
class SceneControlSlot {
  SceneControlSlot({required this.id, this.control}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
  }

  final String id;
  final SceneCustomControl? control;

  SceneControlSlot copyWith({
    String? id,
    SceneCustomControl? control,
    bool clearControl = false,
  }) {
    return SceneControlSlot(
      id: id ?? this.id,
      control: clearControl ? null : control ?? this.control,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'control': control?.toJson(),
  };

  static SceneControlSlot? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final id = value['id'];
    final rawControl = value['control'];
    if (id is! String ||
        (rawControl != null && rawControl is! Map<Object?, Object?>)) {
      return null;
    }
    final control = rawControl == null
        ? null
        : SceneCustomControl.fromJson(rawControl);
    if (rawControl != null && control == null) {
      return null;
    }
    try {
      return SceneControlSlot(id: id, control: control);
    } on ArgumentError {
      return null;
    }
  }
}

/// A user-created composition of existing groups and standalone devices.
class LightingScene {
  LightingScene({
    required this.id,
    required this.name,
    Iterable<SceneTargetReference> targets = const <SceneTargetReference>[],
    Iterable<SceneControlSlot> controlSlots = const <SceneControlSlot>[],
  }) : targets = UnmodifiableListView<SceneTargetReference>(
         List<SceneTargetReference>.from(targets),
       ),
       controlSlots = UnmodifiableListView<SceneControlSlot>(
         List<SceneControlSlot>.from(controlSlots),
       ) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('A Scene requires an id and name.');
    }
    if (this.targets.toSet().length != this.targets.length) {
      throw ArgumentError('A Scene cannot reference the same target twice.');
    }
    final slotIds = this.controlSlots.map((slot) => slot.id).toSet();
    if (slotIds.length != this.controlSlots.length) {
      throw ArgumentError('Scene control slot ids must be unique.');
    }
    final controls = this.controlSlots
        .map((slot) => slot.control)
        .whereType<SceneCustomControl>()
        .toList(growable: false);
    final controlIds = controls.map((control) => control.id).toSet();
    if (controlIds.length != controls.length) {
      throw ArgumentError('Scene control ids must be unique.');
    }
    final targetSet = this.targets.toSet();
    if (controls.any(
      (control) => control.bindings.any(
        (binding) => !targetSet.contains(binding.target),
      ),
    )) {
      throw ArgumentError('A control binding must target a Scene reference.');
    }
  }

  final String id;
  final String name;
  final List<SceneTargetReference> targets;
  final List<SceneControlSlot> controlSlots;

  Iterable<SceneTargetReference> get groupTargets =>
      targets.where((target) => target.type == SceneTargetType.group);

  Iterable<SceneTargetReference> get deviceTargets =>
      targets.where((target) => target.type == SceneTargetType.device);

  LightingScene copyWith({
    String? id,
    String? name,
    Iterable<SceneTargetReference>? targets,
    Iterable<SceneControlSlot>? controlSlots,
  }) {
    return LightingScene(
      id: id ?? this.id,
      name: name ?? this.name,
      targets: targets ?? this.targets,
      controlSlots: controlSlots ?? this.controlSlots,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'targets': targets.map((target) => target.toJson()).toList(),
    'controlSlots': controlSlots.map((slot) => slot.toJson()).toList(),
  };

  static LightingScene? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final id = value['id'];
    final name = value['name'];
    final rawTargets = value['targets'];
    final rawSlots = value['controlSlots'];
    if (id is! String ||
        name is! String ||
        rawTargets is! List<Object?> ||
        rawSlots is! List<Object?>) {
      return null;
    }
    final targets = rawTargets
        .map(SceneTargetReference.fromJson)
        .whereType<SceneTargetReference>()
        .toList(growable: false);
    final slots = rawSlots
        .map(SceneControlSlot.fromJson)
        .whereType<SceneControlSlot>()
        .toList(growable: false);
    if (targets.length != rawTargets.length ||
        slots.length != rawSlots.length) {
      return null;
    }
    try {
      return LightingScene(
        id: id,
        name: name,
        targets: targets,
        controlSlots: slots,
      );
    } on ArgumentError {
      return null;
    }
  }
}

/// The complete, versioned local Scene document.
class SceneConfiguration {
  SceneConfiguration({Iterable<LightingScene> scenes = const <LightingScene>[]})
    : scenes = UnmodifiableListView<LightingScene>(
        List<LightingScene>.from(scenes),
      ) {
    final ids = this.scenes.map((scene) => scene.id).toSet();
    if (ids.length != this.scenes.length) {
      throw ArgumentError('Scene ids must be unique.');
    }
  }

  const SceneConfiguration._empty() : scenes = const <LightingScene>[];

  static const empty = SceneConfiguration._empty();

  final List<LightingScene> scenes;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': sceneConfigurationSchemaVersion,
    'scenes': scenes.map((scene) => scene.toJson()).toList(),
  };

  static SceneConfiguration? fromJson(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value['schemaVersion'] != sceneConfigurationSchemaVersion ||
        value['scenes'] is! List<Object?>) {
      return null;
    }
    final rawScenes = value['scenes']! as List<Object?>;
    final scenes = rawScenes
        .map(LightingScene.fromJson)
        .whereType<LightingScene>()
        .toList(growable: false);
    if (scenes.length != rawScenes.length) {
      return null;
    }
    try {
      return SceneConfiguration(scenes: scenes);
    } on ArgumentError {
      return null;
    }
  }
}
