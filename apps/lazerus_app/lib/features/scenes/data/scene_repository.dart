import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lighting_scene.dart';

abstract interface class SceneRepository {
  Future<SceneConfiguration> load();
  Future<void> save(SceneConfiguration configuration);
}

class SharedPreferencesSceneRepository implements SceneRepository {
  static const _storageKey = 'lazerus.scenes.v1';

  @override
  Future<SceneConfiguration> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return SceneConfiguration.empty;
    }
    try {
      return SceneConfiguration.fromJson(jsonDecode(raw)) ??
          SceneConfiguration.empty;
    } on Object {
      return SceneConfiguration.empty;
    }
  }

  @override
  Future<void> save(SceneConfiguration configuration) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(configuration.toJson()),
    );
  }
}

class InMemorySceneRepository implements SceneRepository {
  InMemorySceneRepository([
    SceneConfiguration configuration = SceneConfiguration.empty,
  ]) : _configuration = configuration;

  SceneConfiguration _configuration;

  @override
  Future<SceneConfiguration> load() async => _configuration;

  @override
  Future<void> save(SceneConfiguration configuration) async {
    _configuration = configuration;
  }
}
