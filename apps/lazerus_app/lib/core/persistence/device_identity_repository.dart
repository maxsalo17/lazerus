import 'dart:async';
import 'dart:convert';

import 'package:lazerus_core/lazerus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Resolves a mutable transport locator to Lazerus' local device identity.
///
/// A BLE identifier is retained only as a discovery/relink binding. Group
/// membership uses the returned application-generated UUID instead.
abstract interface class DeviceIdentityRepository {
  Future<String> resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
  });
}

class SharedPreferencesDeviceIdentityRepository
    implements DeviceIdentityRepository {
  SharedPreferencesDeviceIdentityRepository({Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  static const _storageKey = 'lazerus.device_identity_bindings.v1';

  final Uuid _uuid;
  final Map<String, _DeviceIdentityBinding> _bindings =
      <String, _DeviceIdentityBinding>{};
  final Map<String, Future<String>> _pendingResolutions =
      <String, Future<String>>{};
  Future<void>? _loadOperation;

  @override
  Future<String> resolve(
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

  Future<String> _resolve(
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
    );
    _bindings[bindingKey] = binding;
    await _save();
    return binding.appDeviceId;
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
  });

  final String appDeviceId;
  final TransportKind transport;
  final String endpointId;
  final String protocolId;
  final String? displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'appDeviceId': appDeviceId,
    'transport': transport.name,
    'endpointId': endpointId,
    'protocolId': protocolId,
    'displayName': displayName,
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
    );
  }
}

/// Lightweight deterministic repository for controller and UI tests.
class InMemoryDeviceIdentityRepository implements DeviceIdentityRepository {
  final Map<String, String> _identities = <String, String>{};
  final Uuid _uuid = const Uuid();

  @override
  Future<String> resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
  }) async {
    return _identities.putIfAbsent(
      '${endpoint.transport.name}:${endpoint.id}',
      _uuid.v4,
    );
  }
}
