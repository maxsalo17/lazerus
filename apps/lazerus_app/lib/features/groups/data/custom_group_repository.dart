import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lighting_group.dart';

abstract interface class CustomGroupRepository {
  Future<List<CustomLightingGroup>> load();
  Future<void> save(List<CustomLightingGroup> groups);
}

class SharedPreferencesCustomGroupRepository implements CustomGroupRepository {
  static const _storageKey = 'lazerus.custom_lighting_groups.v1';

  @override
  Future<List<CustomLightingGroup>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawValue = preferences.getString(_storageKey);
    if (rawValue == null || rawValue.isEmpty) {
      return const <CustomLightingGroup>[];
    }
    final decoded = jsonDecode(rawValue);
    if (decoded is! List<Object?>) {
      return const <CustomLightingGroup>[];
    }
    final groups = <CustomLightingGroup>[];
    for (final value in decoded) {
      if (value is Map<String, Object?>) {
        final group = CustomLightingGroup.fromJson(value);
        if (group != null) {
          groups.add(group);
        }
      }
    }
    return List<CustomLightingGroup>.unmodifiable(groups);
  }

  @override
  Future<void> save(List<CustomLightingGroup> groups) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = groups
        .map((group) => group.toJson())
        .toList(growable: false);
    await preferences.setString(_storageKey, jsonEncode(encoded));
  }
}

class InMemoryCustomGroupRepository implements CustomGroupRepository {
  List<CustomLightingGroup> _groups = <CustomLightingGroup>[];

  @override
  Future<List<CustomLightingGroup>> load() async {
    return List<CustomLightingGroup>.unmodifiable(_groups);
  }

  @override
  Future<void> save(List<CustomLightingGroup> groups) async {
    _groups = List<CustomLightingGroup>.from(groups);
  }
}
