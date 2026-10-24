import 'dart:async';
import 'dart:convert';

import 'package:lazerus_core/lazerus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Resolves a mutable transport locator to Lazerus' local device identity.
///
/// A BLE identifier is retained only as a discovery/relink binding. The
/// returned application-generated UUID identifies persisted device data.
abstract interface class DeviceIdentityRepository {
  Future<SavedDeviceIdentity> resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
  });

  /// Persists a user-assigned label without changing the transport locator or
  /// the application device ID.
  Future<void> rename(String appDeviceId, String userDefinedName);
}

/// The locally persisted identity and optional user-facing device label.
///
/// [appDeviceId] is stable across rediscovery while the endpoint ID and the
/// advertised Bluetooth name remain mutable transport data.
class SavedDeviceIdentity {
  const SavedDeviceIdentity({required this.appDeviceId, this.userDefinedName});

  final String appDeviceId;
  final String? userDefinedName;
}

class SharedPreferencesDeviceIdentityRepository
    implements DeviceIdentityRepository {
  SharedPreferencesDeviceIdentityRepository({Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  static const _storageKey = 'lazerus.device_identity_bindings.v1';

  final Uuid _uuid;
  final Map<String, _DeviceIdentityBinding> _bindings =
      <String, _DeviceIdentityBinding>{};
  final Map<String, Future<SavedDeviceIdentity>> _pendingResolutions =
      <String, Future<SavedDeviceIdentity>>{};
  Future<void>? _loadOperation;

  @override
  Future<SavedDeviceIdentity> resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
  }) {
    final bindingKey = _bindingKey(endpoint.transport, endpoint.id);
    final pending = _pendingResolutions[bindingKey];
    if (pending != null) {
      return pending;
    }
    final operation = _resolve(
      endpoint,
      protocolId: protocolId,
      bindingKey: bindingKey,
    );
    _pendingResolutions[bindingKey] = operation;
    return operation.whenComplete(() => _pendingResolutions.remove(bindingKey));
  }

  Future<SavedDeviceIdentity> _resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
    required String bindingKey,
  }) async {
    await _ensureLoaded();
    final existing = _bindings[bindingKey];
    final binding = _DeviceIdentityBinding(
      appDeviceId: existing?.appDeviceId ?? _uuid.v4(),
      transport: endpoint.transport,
      endpointId: endpoint.id,
      protocolId: protocolId,
      displayName: endpoint.displayName,
      userDefinedName: existing?.userDefinedName,
    );
    _bindings[bindingKey] = binding;
    await _save();
    return SavedDeviceIdentity(
      appDeviceId: binding.appDeviceId,
      userDefinedName: binding.userDefinedName,
    );
  }

  @override
  Future<void> rename(String appDeviceId, String userDefinedName) async {
    await _ensureLoaded();
    final normalizedName = userDefinedName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        userDefinedName,
        'userDefinedName',
        'A device name cannot be empty.',
      );
    }
    final keys = _bindings.entries
        .where((entry) => entry.value.appDeviceId == appDeviceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (keys.isEmpty) {
      throw StateError('The device is not known locally.');
    }
    for (final key in keys) {
      _bindings[key] = _bindings[key]!.copyWith(
        userDefinedName: normalizedName,
      );
    }
    await _save();
  }

  Future<void> _ensureLoaded() {
    return _loadOperation ??= _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }
    final decoded = jsonDecode(stored);
    if (decoded is! List<Object?>) {
      return;
    }
    for (final item in decoded) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final binding = _DeviceIdentityBinding.fromJson(item);
      if (binding != null) {
        _bindings[_bindingKey(binding.transport, binding.endpointId)] = binding;
      }
    }
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    final values = _bindings.values
        .map((binding) => binding.toJson())
        .toList(growable: false);
    await preferences.setString(_storageKey, jsonEncode(values));
  }

  static String _bindingKey(TransportKind transport, String endpointId) {
    return '${transport.name}:$endpointId';
  }
}

class _DeviceIdentityBinding {
  const _DeviceIdentityBinding({
    required this.appDeviceId,
    required this.transport,
    required this.endpointId,
    required this.protocolId,
    required this.displayName,
    this.userDefinedName,
  });

  final String appDeviceId;
  final TransportKind transport;
  final String endpointId;
  final String protocolId;
  final String? displayName;
  final String? userDefinedName;

  _DeviceIdentityBinding copyWith({String? userDefinedName}) {
    return _DeviceIdentityBinding(
      appDeviceId: appDeviceId,
      transport: transport,
      endpointId: endpointId,
      protocolId: protocolId,
      displayName: displayName,
      userDefinedName: userDefinedName ?? this.userDefinedName,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'appDeviceId': appDeviceId,
    'transport': transport.name,
    'endpointId': endpointId,
    'protocolId': protocolId,
    'displayName': displayName,
    'userDefinedName': userDefinedName,
  };

  static _DeviceIdentityBinding? fromJson(Map<String, Object?> json) {
    final appDeviceId = json['appDeviceId'];
    final transportName = json['transport'];
    final endpointId = json['endpointId'];
    final protocolId = json['protocolId'];
    if (appDeviceId is! String ||
        transportName is! String ||
        endpointId is! String ||
        protocolId is! String) {
      return null;
    }
    final transport = TransportKind.values.where(
      (kind) => kind.name == transportName,
    );
    if (transport.isEmpty) {
      return null;
    }
    return _DeviceIdentityBinding(
      appDeviceId: appDeviceId,
      transport: transport.first,
      endpointId: endpointId,
      protocolId: protocolId,
      displayName: json['displayName'] as String?,
      userDefinedName: json['userDefinedName'] as String?,
    );
  }
}

/// Lightweight deterministic repository for controller and UI tests.
class InMemoryDeviceIdentityRepository implements DeviceIdentityRepository {
  final Map<String, _InMemoryIdentity> _identities =
      <String, _InMemoryIdentity>{};
  final Uuid _uuid = const Uuid();

  @override
  Future<SavedDeviceIdentity> resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
  }) async {
    final identity = _identities.putIfAbsent(
      '${endpoint.transport.name}:${endpoint.id}',
      () => _InMemoryIdentity(appDeviceId: _uuid.v4()),
    );
    return SavedDeviceIdentity(
      appDeviceId: identity.appDeviceId,
      userDefinedName: identity.userDefinedName,
    );
  }

  @override
  Future<void> rename(String appDeviceId, String userDefinedName) async {
    final normalizedName = userDefinedName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        userDefinedName,
        'userDefinedName',
        'A device name cannot be empty.',
      );
    }
    final identities = _identities.values.where(
      (identity) => identity.appDeviceId == appDeviceId,
    );
    if (identities.isEmpty) {
      throw StateError('The device is not known locally.');
    }
    for (final identity in identities) {
      identity.userDefinedName = normalizedName;
    }
  }
}

class _InMemoryIdentity {
  _InMemoryIdentity({required this.appDeviceId});

  final String appDeviceId;
  String? userDefinedName;
}
