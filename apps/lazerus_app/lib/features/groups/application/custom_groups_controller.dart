import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/custom_group_repository.dart';
import '../domain/lighting_group.dart';

final customGroupRepositoryProvider = Provider<CustomGroupRepository>((ref) {
  return SharedPreferencesCustomGroupRepository();
});

final customGroupsProvider =
    NotifierProvider<CustomGroupsController, CustomGroupsState>(
      CustomGroupsController.new,
    );

class CustomGroupsState {
  const CustomGroupsState({
    this.isLoading = true,
    this.groups = const <CustomLightingGroup>[],
    this.error,
  });

  final bool isLoading;
  final List<CustomLightingGroup> groups;
  final String? error;

  CustomGroupsState copyWith({
    bool? isLoading,
    List<CustomLightingGroup>? groups,
    String? error,
  }) {
    return CustomGroupsState(
      isLoading: isLoading ?? this.isLoading,
      groups: groups ?? this.groups,
      error: error ?? this.error,
    );
  }
}

class CustomGroupsController extends Notifier<CustomGroupsState> {
  late final CustomGroupRepository _repository;
  final Uuid _uuid = const Uuid();
  var _disposed = false;

  @override
  CustomGroupsState build() {
    _repository = ref.watch(customGroupRepositoryProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(_load());
    return const CustomGroupsState();
  }

  Future<CustomLightingGroup?> create({
    required String name,
    Iterable<String> memberDeviceIds = const <String>[],
    String? autoAddProtocolId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      _setError('A group name is required.');
      return null;
    }
    final group = CustomLightingGroup(
      id: _uuid.v4(),
      name: normalizedName,
      memberDeviceIds: memberDeviceIds,
      autoAddProtocolId: autoAddProtocolId,
    );
    final saved = await _replaceGroups(<CustomLightingGroup>[
      ...state.groups,
      group,
    ]);
    return saved ? group : null;
  }

  Future<void> update(CustomLightingGroup group) async {
    final normalizedName = group.name.trim();
    if (normalizedName.isEmpty) {
      _setError('A group name is required.');
      return;
    }
    final normalized = group.copyWith(name: normalizedName);
    await _replaceGroups(
      state.groups
          .map((current) => current.id == group.id ? normalized : current)
          .toList(growable: false),
    );
  }

  Future<void> delete(String groupId) async {
    await _replaceGroups(
      state.groups
          .where((group) => group.id != groupId)
          .toList(growable: false),
    );
  }

  Future<void> _load() async {
    try {
      final groups = await _repository.load();
      if (!_disposed) {
        state = CustomGroupsState(isLoading: false, groups: groups);
      }
    } on Object catch (error) {
      if (!_disposed) {
        state = CustomGroupsState(
          isLoading: false,
          error: 'Could not load custom groups: $error',
        );
      }
    }
  }

  Future<bool> _replaceGroups(List<CustomLightingGroup> groups) async {
    final previous = state.groups;
    state = CustomGroupsState(isLoading: false, groups: groups);
    try {
      await _repository.save(groups);
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = CustomGroupsState(
          isLoading: false,
          groups: previous,
          error: 'Could not save custom groups: $error',
        );
      }
      return false;
    }
  }

  void _setError(String error) {
    if (!_disposed) {
      state = state.copyWith(error: error);
    }
  }
}
