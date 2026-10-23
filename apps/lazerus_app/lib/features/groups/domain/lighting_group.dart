import 'dart:collection';

/// A user-managed, local logical group.
///
/// Protocol-wide default groups are derived at runtime and are intentionally
/// not represented here, so they cannot be edited or persisted accidentally.
class CustomLightingGroup {
  CustomLightingGroup({
    required this.id,
    required this.name,
    Iterable<String> memberDeviceIds = const <String>[],
    this.autoAddProtocolId,
  }) : memberDeviceIds = UnmodifiableSetView<String>(
         Set<String>.from(memberDeviceIds),
       );

  final String id;
  final String name;
  final Set<String> memberDeviceIds;

  /// Matching devices participate dynamically while this is set.
  final String? autoAddProtocolId;

  bool get automaticallyAddsSimilarDevices => autoAddProtocolId != null;

  CustomLightingGroup copyWith({
    String? name,
    Iterable<String>? memberDeviceIds,
    String? autoAddProtocolId,
    bool clearAutoAddProtocol = false,
  }) {
    return CustomLightingGroup(
      id: id,
      name: name ?? this.name,
      memberDeviceIds: memberDeviceIds ?? this.memberDeviceIds,
      autoAddProtocolId: clearAutoAddProtocol
          ? null
          : autoAddProtocolId ?? this.autoAddProtocolId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'memberDeviceIds': memberDeviceIds.toList(growable: false),
    'autoAddProtocolId': autoAddProtocolId,
  };

  static CustomLightingGroup? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final members = json['memberDeviceIds'];
    if (id is! String || name is! String || members is! List<Object?>) {
      return null;
    }
    return CustomLightingGroup(
      id: id,
      name: name,
      memberDeviceIds: members.whereType<String>(),
      autoAddProtocolId: json['autoAddProtocolId'] as String?,
    );
  }
}
