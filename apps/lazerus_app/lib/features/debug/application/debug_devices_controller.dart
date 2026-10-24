import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:lazerus_proto_lotus_lamp_x/lazerus_proto_lotus_lamp_x.dart';

import '../../../core/bluetooth/bluetooth_low_energy_transport.dart';
import '../../../core/persistence/device_identity_repository.dart';
import '../../calibration/application/device_calibration_controller.dart';
import '../../diagnostics/application/diagnostics_controller.dart';

/// The transport used by the first end-user Lazerus surface.
///
/// UI code only depends on this provider and the protocol contracts; it never
/// calls a BLE SDK directly.
final bleTransportProvider = Provider<DeviceTransport>((ref) {
  return BluetoothLowEnergyTransport();
});

final deviceIdentityRepositoryProvider = Provider<DeviceIdentityRepository>((
  ref,
) {
  return SharedPreferencesDeviceIdentityRepository();
});

/// Installed lighting family adapters. Adding a future protocol does not
/// require brand checks in the debug feature.
final protocolAdapterRegistryProvider = Provider<ProtocolAdapterRegistry>((
  ref,
) {
  return ProtocolAdapterRegistry(<LightingProtocolAdapter>[
    // The locally exercised profile allows basic controls. Broader Lotus/ELK
    // capability claims remain inferred until reproducible records exist.
    LotusLampXProtocolAdapter(allowUnverifiedCommands: true),
  ]);
});

final debugDevicesProvider =
    NotifierProvider<DebugDevicesController, DebugModuleState>(
      DebugDevicesController.new,
    );

enum DebugDeviceConnectionStatus {
  discovered,
  connecting,
  connected,
  disconnected,
  unsupported,
  error,
}

/// UI-safe information about one automatically classified device.
class DebugDevice {
  const DebugDevice({
    required this.appDeviceId,
    required this.endpoint,
    required this.protocolId,
    required this.matchConfidence,
    required this.matchReason,
    required this.status,
    this.capabilities,
    this.statusDetail,
    this.commandInFlight = false,
    this.lastCommandOutcome,
    this.requestedPower,
    this.requestedColor,
    this.requestedBrightness,
    this.observedState,
    this.observedAt,
    this.transportState,
    this.localState,
  });

  /// Stable local identity used by groups and persisted configuration.
  final String appDeviceId;
  final TransportEndpoint endpoint;
  final String protocolId;
  final int matchConfidence;
  final String? matchReason;
  final DebugDeviceConnectionStatus status;
  final DeviceCapabilities? capabilities;
  final String? statusDetail;
  final bool commandInFlight;
  final CommandOutcome? lastCommandOutcome;

  /// A command accepted by the transport, not a state observed on hardware.
  final bool? requestedPower;
  final RgbColor? requestedColor;
  final double? requestedBrightness;

  /// A best-effort value reported by the protocol, separate from commands the
  /// app asked the controller to apply.
  final DesiredLightingState? observedState;
  final DateTime? observedAt;

  /// The most recently known protocol-side values. Colour in this state can be
  /// calibrated for transport and must not replace the requested UI colour.
  final DesiredLightingState? transportState;

  /// The merged desired state used by UI and group aggregation. It is updated
  /// by accepted app commands, not treated as physical confirmation.
  final DesiredLightingState? localState;

  /// Locally tracked state for rendering and group aggregation. It is never a
  /// claim that a write changed the physical strip.
  DesiredLightingState get lastKnownState =>
      localState ??
      DesiredLightingState(
        power: observedState?.power ?? requestedPower,
        color: observedState?.color ?? requestedColor,
        brightness: observedState?.brightness ?? requestedBrightness,
      );

  DebugDevice copyWith({
    String? appDeviceId,
    TransportEndpoint? endpoint,
    String? protocolId,
    int? matchConfidence,
    String? matchReason,
    DebugDeviceConnectionStatus? status,
    DeviceCapabilities? capabilities,
    String? statusDetail,
    bool? commandInFlight,
    CommandOutcome? lastCommandOutcome,
    bool? requestedPower,
    RgbColor? requestedColor,
    double? requestedBrightness,
    DesiredLightingState? observedState,
    DateTime? observedAt,
    DesiredLightingState? transportState,
    DesiredLightingState? localState,
  }) {
    return DebugDevice(
      appDeviceId: appDeviceId ?? this.appDeviceId,
      endpoint: endpoint ?? this.endpoint,
      protocolId: protocolId ?? this.protocolId,
      matchConfidence: matchConfidence ?? this.matchConfidence,
      matchReason: matchReason ?? this.matchReason,
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      statusDetail: statusDetail ?? this.statusDetail,
      commandInFlight: commandInFlight ?? this.commandInFlight,
      lastCommandOutcome: lastCommandOutcome ?? this.lastCommandOutcome,
      requestedPower: requestedPower ?? this.requestedPower,
      requestedColor: requestedColor ?? this.requestedColor,
      requestedBrightness: requestedBrightness ?? this.requestedBrightness,
      observedState: observedState ?? this.observedState,
      observedAt: observedAt ?? this.observedAt,
      transportState: transportState ?? this.transportState,
      localState: localState ?? this.localState,
    );
  }
}

class DebugModuleState {
  DebugModuleState({
    this.isScanning = false,
    this.diagnosticCommandsEnabled = true,
    Map<String, DebugDevice> devices = const <String, DebugDevice>{},
    this.scanError,
  }) : devices = UnmodifiableMapView<String, DebugDevice>(devices);

  final bool isScanning;
  final bool diagnosticCommandsEnabled;
  final Map<String, DebugDevice> devices;
  final String? scanError;

  List<DebugDevice> get sortedDevices {
    final devices = this.devices.values.toList()
      ..sort((left, right) {
        final leftName = left.endpoint.displayName ?? left.endpoint.id;
        final rightName = right.endpoint.displayName ?? right.endpoint.id;
        return leftName.compareTo(rightName);
      });
    return List<DebugDevice>.unmodifiable(devices);
  }

  DebugModuleState copyWith({
    bool? isScanning,
    bool? diagnosticCommandsEnabled,
    Map<String, DebugDevice>? devices,
    String? scanError,
  }) {
    return DebugModuleState(
      isScanning: isScanning ?? this.isScanning,
      diagnosticCommandsEnabled:
          diagnosticCommandsEnabled ?? this.diagnosticCommandsEnabled,
      devices: devices ?? this.devices,
      scanError: scanError ?? this.scanError,
    );
  }
}

/// Coordinates protocol-neutral discovery, classification and diagnostic
/// sessions. It owns all subscriptions, leaving Flutter widgets free of BLE
/// state and lifecycle concerns.
class DebugDevicesController extends Notifier<DebugModuleState> {
  late final DeviceTransport _transport;
  late final DeviceIdentityRepository _deviceIdentityRepository;
  late final ProtocolAdapterRegistry _registry;
  late final DiagnosticsController _diagnostics;
  final Map<String, _ManagedDeviceSession> _connections =
      <String, _ManagedDeviceSession>{};
  final Set<String> _connectionAttempts = <String>{};
  final Set<String> _processingEndpointIds = <String>{};
  final Set<String> _manuallyDisconnectedDeviceIds = <String>{};
  StreamSubscription<TransportDiscoveryEvent>? _discoverySubscription;
  var _disposed = false;

  @override
  DebugModuleState build() {
    _transport = ref.watch(bleTransportProvider);
    _deviceIdentityRepository = ref.watch(deviceIdentityRepositoryProvider);
    _registry = ref.watch(protocolAdapterRegistryProvider);
    _diagnostics = ref.read(diagnosticsProvider.notifier);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_releaseResources());
    });
    return DebugModuleState();
  }

  Future<void> startDiscovery() async {
    if (_disposed || state.isScanning) {
      return;
    }
    await stopDiscovery();
    if (_disposed) {
      return;
    }

    state = state.copyWith(isScanning: true, scanError: '');
    _diagnostics.info('BLE discovery started.');
    try {
      _discoverySubscription = _transport
          .discover(_discoveryRequest())
          .listen(_onDiscoveryEvent, onError: _onDiscoveryStreamError);
    } on Object catch (error) {
      _diagnostics.error('BLE discovery could not be started: $error');
      state = state.copyWith(
        isScanning: false,
        scanError: 'BLE discovery could not be started: $error',
      );
    }
  }

  Future<void> stopDiscovery() async {
    final subscription = _discoverySubscription;
    _discoverySubscription = null;
    await subscription?.cancel();
    if (!_disposed && state.isScanning) {
      state = state.copyWith(isScanning: false);
    }
  }

  void setDiagnosticCommandsEnabled(bool enabled) {
    if (_disposed) {
      return;
    }
    state = state.copyWith(diagnosticCommandsEnabled: enabled);
  }

  Future<CommandResult> execute(
    String appDeviceId,
    LightingCommand command,
  ) async {
    final initialDevice = state.devices[appDeviceId];
    if (initialDevice == null) {
      _diagnostics.error('Command ignored: the device is no longer listed.');
      return CommandResult.rejected(command, 'The device is no longer listed.');
    }
    final calibrations = ref.read(deviceCalibrationProvider.notifier);
    await calibrations.ensureLoaded();
    final device = state.devices[appDeviceId];
    if (_disposed || device == null) {
      return CommandResult.rejected(command, 'The device is no longer listed.');
    }
    if (!state.diagnosticCommandsEnabled) {
      const detail =
          'Enable diagnostic commands before sending inferred protocol frames.';
      _updateDevice(
        appDeviceId,
        device.copyWith(
          statusDetail: detail,
          lastCommandOutcome: CommandOutcome.rejected,
        ),
      );
      _logCommandError(appDeviceId, detail);
      return CommandResult.rejected(command, detail);
    }
    if (device.commandInFlight) {
      const detail = 'A command is already being sent to this device.';
      _updateDevice(
        appDeviceId,
        device.copyWith(
          statusDetail: detail,
          lastCommandOutcome: CommandOutcome.rejected,
        ),
      );
      _logCommandError(appDeviceId, detail);
      return CommandResult.rejected(command, detail);
    }

    final connection = _connections[appDeviceId];
    if (connection == null ||
        device.status != DebugDeviceConnectionStatus.connected) {
      const detail = 'Connect to the device before sending a command.';
      _updateDevice(
        appDeviceId,
        device.copyWith(
          statusDetail: detail,
          lastCommandOutcome: CommandOutcome.rejected,
        ),
      );
      _logCommandError(appDeviceId, detail);
      return CommandResult.rejected(command, detail);
    }

    final requiredFeature = _featureFor(command);
    if (requiredFeature != null &&
        !connection.lightingSession.capabilities.supports(
          requiredFeature,
          allowInferred: true,
        )) {
      const detail =
          'This device profile does not support the requested command.';
      _updateDevice(
        appDeviceId,
        device.copyWith(
          statusDetail: detail,
          lastCommandOutcome: CommandOutcome.rejected,
        ),
      );
      _logCommandError(appDeviceId, detail);
      return CommandResult.rejected(command, detail);
    }

    final transportCommand = _commandForTransport(
      device,
      command,
      calibrations,
    );
    _updateDevice(appDeviceId, device.copyWith(commandInFlight: true));
    late final CommandResult result;
    try {
      result = await connection.lightingSession.execute(transportCommand);
    } on Object catch (error) {
      final failed = CommandResult.failed(command, error);
      if (!_disposed && state.devices.containsKey(appDeviceId)) {
        final current = state.devices[appDeviceId]!;
        _updateDevice(
          appDeviceId,
          current.copyWith(
            commandInFlight: false,
            lastCommandOutcome: failed.outcome,
            statusDetail: 'Command failed: $error',
          ),
        );
      }
      _logCommandError(appDeviceId, 'Command failed: $error');
      return failed;
    }
    final sourceResult = CommandResult(
      command: command,
      outcome: result.outcome,
      receipts: result.receipts,
      detail: result.detail,
      error: result.error,
    );
    if (_disposed || !state.devices.containsKey(appDeviceId)) {
      return sourceResult;
    }

    final current = state.devices[appDeviceId]!;
    final protocolState = connection.lightingSession.lastKnownState;
    final desiredState = _stateForAcceptedCommand(command, sourceResult);
    final nextLocalState = desiredState == null
        ? current.localState
        : _mergeObservedState(current.lastKnownState, desiredState);
    final nextTransportState = protocolState == null
        ? current.transportState
        : _mergeObservedState(current.transportState, protocolState);
    _updateDevice(
      appDeviceId,
      current.copyWith(
        commandInFlight: false,
        lastCommandOutcome: sourceResult.outcome,
        statusDetail: sourceResult.detail ?? sourceResult.error?.toString(),
        requestedPower: (command is SetPower && _wasAccepted(sourceResult)
            ? command.enabled
            : current.requestedPower),
        requestedColor: (command is SetColor && _wasAccepted(sourceResult)
            ? command.color
            : current.requestedColor),
        requestedBrightness:
            (command is SetBrightness && _wasAccepted(sourceResult)
            ? command.value
            : current.requestedBrightness),
        transportState: nextTransportState,
        localState: _wasAccepted(sourceResult)
            ? nextLocalState
            : current.localState,
      ),
    );
    if (!_wasAccepted(sourceResult)) {
      _logCommandError(
        appDeviceId,
        sourceResult.detail ??
            sourceResult.error?.toString() ??
            'Command was not accepted.',
      );
    }
    return sourceResult;
  }

  Future<List<CommandResult>> executeForDevices(
    Iterable<String> appDeviceIds,
    LightingCommand command,
  ) async {
    final results = <CommandResult>[];
    for (final appDeviceId in appDeviceIds) {
      results.add(await execute(appDeviceId, command));
    }
    return List<CommandResult>.unmodifiable(results);
  }

  Future<void> disconnect(String appDeviceId) async {
    _manuallyDisconnectedDeviceIds.add(appDeviceId);
    final connection = _connections.remove(appDeviceId);
    if (connection == null) {
      return;
    }
    try {
      await connection.close();
    } on Object catch (error) {
      _logCommunicationError(appDeviceId, 'Disconnect failed: $error');
      _updateDeviceStatus(
        appDeviceId,
        DebugDeviceConnectionStatus.error,
        detail: 'Disconnect failed: $error',
      );
      return;
    }
    _updateDeviceStatus(
      appDeviceId,
      DebugDeviceConnectionStatus.disconnected,
      detail: 'Disconnected by the user.',
    );
    _diagnostics.info(
      'Device disconnected by the user.',
      deviceId: appDeviceId,
      deviceName: _deviceName(appDeviceId),
    );
  }

  Future<void> connectDevice(String appDeviceId) async {
    final device = state.devices[appDeviceId];
    if (device == null || _disposed) {
      return;
    }
    if (device.status == DebugDeviceConnectionStatus.connected ||
        device.status == DebugDeviceConnectionStatus.connecting ||
        _connectionAttempts.contains(appDeviceId)) {
      return;
    }
    final adapter = _registry.adapters.where(
      (candidate) => candidate.id == device.protocolId,
    );
    if (adapter.isEmpty) {
      _updateDeviceStatus(
        appDeviceId,
        DebugDeviceConnectionStatus.unsupported,
        detail: 'The saved protocol adapter is not registered.',
      );
      _logCommunicationError(
        appDeviceId,
        'The saved protocol adapter is not registered.',
      );
      return;
    }
    final selectedAdapter = adapter.first;
    final match = selectedAdapter.match(device.endpoint);
    if (!match.isMatch) {
      _updateDeviceStatus(
        appDeviceId,
        DebugDeviceConnectionStatus.unsupported,
        detail: 'The current endpoint no longer matches its protocol adapter.',
      );
      _logCommunicationError(
        appDeviceId,
        'The current endpoint no longer matches its protocol adapter.',
      );
      return;
    }
    _manuallyDisconnectedDeviceIds.remove(appDeviceId);
    await _connect(
      appDeviceId,
      device.endpoint,
      ProtocolCandidate(adapter: selectedAdapter, match: match),
    );
  }

  DiscoveryRequest _discoveryRequest() {
    final serviceIds = <String>{};
    final namePrefixes = <String>{};
    for (final adapter in _registry.adapters) {
      if (!adapter.supportedTransports.contains(_transport.kind)) {
        continue;
      }
      final spec = adapter.discoverySpecFor(_transport.kind);
      serviceIds.addAll(spec.serviceIds);
      namePrefixes.addAll(spec.namePrefixes);
    }
    return DiscoveryRequest(
      timeout: const Duration(seconds: 15),
      serviceIds: serviceIds,
      namePrefixes: namePrefixes,
      // The transport scans broadly but the controller only renders endpoints
      // classified by the installed adapter registry.
      includeUnidentified: true,
    );
  }

  void _onDiscoveryEvent(TransportDiscoveryEvent event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case TransportEndpointDiscovered(:final endpoint):
        _handleEndpoint(endpoint);
      case TransportDiscoveryError(:final message, :final error):
        _diagnostics.error(message ?? 'Discovery error: $error');
        state = state.copyWith(scanError: message ?? 'Discovery error: $error');
      case TransportDiscoveryComplete():
        unawaited(stopDiscovery());
    }
  }

  void _onDiscoveryStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }
    _diagnostics.error('BLE discovery stream ended with an error: $error');
    state = state.copyWith(
      isScanning: false,
      scanError: 'BLE discovery stream ended with an error: $error',
    );
  }

  void _handleEndpoint(TransportEndpoint endpoint) {
    if (!_processingEndpointIds.add(endpoint.id)) {
      return;
    }
    unawaited(_registerEndpoint(endpoint));
  }

  Future<void> _registerEndpoint(TransportEndpoint endpoint) async {
    final selection = _registry.select(endpoint);
    final candidate = selection.selected;
    if (candidate == null || selection.isAmbiguous) {
      _processingEndpointIds.remove(endpoint.id);
      return;
    }

    try {
      final appDeviceId = await _deviceIdentityRepository.resolve(
        endpoint,
        protocolId: candidate.adapter.id,
      );
      if (_disposed) {
        return;
      }
      final current = state.devices[appDeviceId];
      final device = DebugDevice(
        appDeviceId: appDeviceId,
        endpoint: endpoint,
        protocolId: candidate.adapter.id,
        matchConfidence: candidate.match.confidence,
        matchReason: candidate.match.reason,
        status: current?.status ?? DebugDeviceConnectionStatus.discovered,
        capabilities: current?.capabilities,
        statusDetail: current?.statusDetail ?? candidate.match.reason,
        commandInFlight: current?.commandInFlight ?? false,
        lastCommandOutcome: current?.lastCommandOutcome,
        requestedPower: current?.requestedPower,
        requestedColor: current?.requestedColor,
        requestedBrightness: current?.requestedBrightness,
        observedState: current?.observedState,
        observedAt: current?.observedAt,
        transportState: current?.transportState,
        localState: current?.localState,
      );
      _updateDevice(appDeviceId, device);

      if (device.status == DebugDeviceConnectionStatus.connected ||
          device.status == DebugDeviceConnectionStatus.connecting ||
          _connectionAttempts.contains(appDeviceId) ||
          _manuallyDisconnectedDeviceIds.contains(appDeviceId)) {
        return;
      }
      unawaited(_connect(appDeviceId, endpoint, candidate));
    } on Object catch (error) {
      _diagnostics.error('Could not resolve a local device identity: $error');
      if (!_disposed) {
        state = state.copyWith(
          scanError: 'Could not resolve a local device identity: $error',
        );
      }
    } finally {
      _processingEndpointIds.remove(endpoint.id);
    }
  }

  Future<void> _connect(
    String appDeviceId,
    TransportEndpoint endpoint,
    ProtocolCandidate candidate,
  ) async {
    if (_disposed || _connectionAttempts.contains(appDeviceId)) {
      return;
    }
    _connectionAttempts.add(appDeviceId);
    _diagnostics.info(
      'Connecting and discovering GATT characteristics…',
      deviceId: appDeviceId,
      deviceName: endpoint.displayName,
    );
    _updateDeviceStatus(
      appDeviceId,
      DebugDeviceConnectionStatus.connecting,
      detail: 'Connecting and discovering GATT characteristics…',
    );

    TransportSession? transportSession;
    LightingDeviceSession? lightingSession;
    try {
      final connectedTransportSession = await _transport.connect(
        endpoint,
        const ConnectionOptions(),
      );
      transportSession = connectedTransportSession;
      if (_disposed) {
        await connectedTransportSession.disconnect();
        return;
      }
      final probe = await candidate.adapter.probe(
        connectedTransportSession,
        const ProtocolProbeOptions(),
      );
      if (probe.status == ProtocolProbeStatus.unsupported ||
          probe.status == ProtocolProbeStatus.failed) {
        await connectedTransportSession.disconnect();
        _updateDeviceStatus(
          appDeviceId,
          DebugDeviceConnectionStatus.unsupported,
          detail:
              probe.reason ?? 'The protocol probe did not support this device.',
        );
        return;
      }

      final openedLightingSession = await candidate.adapter.openSession(
        connectedTransportSession,
        probe,
      );
      lightingSession = openedLightingSession;
      final connection = _ManagedDeviceSession(
        transportSession: connectedTransportSession,
        lightingSession: openedLightingSession,
      );
      connection.transportEvents = connectedTransportSession.events.listen(
        (event) => _handleTransportEvent(appDeviceId, event),
      );
      connection.observations = openedLightingSession.observations.listen(
        (observation) => _handleObservation(appDeviceId, observation),
        onError: (Object error, StackTrace stackTrace) {
          _logCommunicationError(
            appDeviceId,
            'Protocol observation stream failed: $error',
          );
        },
      );
      _connections[appDeviceId] = connection;
      _updateDevice(
        appDeviceId,
        state.devices[appDeviceId]!.copyWith(
          status: DebugDeviceConnectionStatus.connected,
          capabilities: openedLightingSession.capabilities,
          statusDetail: probe.reason ?? 'Connected.',
        ),
      );
      _diagnostics.info(
        'Connected. ${probe.reason ?? ''}'.trim(),
        deviceId: appDeviceId,
        deviceName: endpoint.displayName,
      );
      unawaited(requestCurrentState(appDeviceId));
    } on Object catch (error) {
      try {
        await lightingSession?.close();
        await transportSession?.disconnect();
      } on Object {
        // Preserve the original connection error for the UI.
      }
      _updateDeviceStatus(
        appDeviceId,
        DebugDeviceConnectionStatus.error,
        detail: 'Connection failed: $error',
      );
      _logCommunicationError(appDeviceId, 'Connection failed: $error');
    } finally {
      _connectionAttempts.remove(appDeviceId);
    }
  }

  /// Requests protocol-defined state from every active session. This avoids
  /// exposing transport-specific reads to the presentation layer.
  Future<void> requestCurrentStates() async {
    final deviceIds = _connections.keys.toList(growable: false);
    if (deviceIds.isEmpty) {
      _diagnostics.warning('No connected devices are available to read.');
      return;
    }
    for (final appDeviceId in deviceIds) {
      await requestCurrentState(appDeviceId);
    }
  }

  /// The protocol emits any received or decoded data through observations.
  /// A read result is never treated as confirmation the controller applied an
  /// earlier command.
  Future<void> requestCurrentState(String appDeviceId) async {
    if (_disposed) {
      return;
    }
    final device = state.devices[appDeviceId];
    final connection = _connections[appDeviceId];
    if (device == null ||
        connection == null ||
        device.status != DebugDeviceConnectionStatus.connected) {
      _diagnostics.warning(
        'Current state was not requested because the device is not connected.',
        deviceId: appDeviceId,
        deviceName: _deviceName(appDeviceId),
      );
      return;
    }

    _diagnostics.info(
      'Requesting current state through the protocol.',
      deviceId: appDeviceId,
      deviceName: _deviceName(appDeviceId),
    );
    try {
      await connection.lightingSession.requestCurrentState();
    } on Object catch (error) {
      _logCommunicationError(
        appDeviceId,
        'Current-state request failed: $error',
      );
    }
  }

  void _handleObservation(String appDeviceId, DeviceObservation observation) {
    if (_disposed) {
      return;
    }
    final device = state.devices[appDeviceId];
    final deviceName = device?.endpoint.displayName;
    final incomingState = observation.state;
    final observedState = incomingState == null
        ? device?.observedState
        : _mergeObservedState(device?.observedState, incomingState);
    final transportState = incomingState == null
        ? device?.transportState
        : _mergeObservedState(device?.transportState, incomingState);

    if (incomingState != null && device != null) {
      _updateDevice(
        appDeviceId,
        device.copyWith(
          observedState: observedState,
          observedAt: observation.occurredAt,
          transportState: transportState,
        ),
      );
    }

    final detail = observation.detail ?? _observationMessage(observation.kind);
    if (observation.rawData != null || incomingState != null) {
      _diagnostics.received(
        detail,
        deviceId: appDeviceId,
        deviceName: deviceName,
        rawData: observation.rawData,
        observedState: observedState,
      );
      return;
    }
    _diagnostics.warning(detail, deviceId: appDeviceId, deviceName: deviceName);
  }

  static DesiredLightingState _mergeObservedState(
    DesiredLightingState? previous,
    DesiredLightingState incoming,
  ) {
    return DesiredLightingState(
      power: incoming.power ?? previous?.power,
      color: incoming.color ?? previous?.color,
      brightness: incoming.brightness ?? previous?.brightness,
    );
  }

  LightingCommand _commandForTransport(
    DebugDevice device,
    LightingCommand command,
    DeviceCalibrationController calibrations,
  ) {
    RgbColor map(RgbColor color) => calibrations.mapColorForDevice(
      appDeviceId: device.appDeviceId,
      protocolId: device.protocolId,
      color: color,
    );
    return switch (command) {
      SetColor(:final color) => SetColor(map(color)),
      ApplyLightingState(:final state) when state.color != null =>
        ApplyLightingState(
          DesiredLightingState(
            power: state.power,
            color: map(state.color!),
            brightness: state.brightness,
          ),
        ),
      _ => command,
    };
  }

  static DesiredLightingState? _stateForAcceptedCommand(
    LightingCommand command,
    CommandResult result,
  ) {
    if (!_wasAccepted(result)) {
      return null;
    }
    return switch (command) {
      SetPower(:final enabled) => DesiredLightingState(power: enabled),
      SetColor(:final color) => DesiredLightingState(color: color),
      SetBrightness(:final value) => DesiredLightingState(brightness: value),
      ApplyLightingState(:final state) => state,
      _ => null,
    };
  }

  static String _observationMessage(DeviceObservationKind kind) {
    return switch (kind) {
      DeviceObservationKind.state => 'Protocol reported a best-effort state.',
      DeviceObservationKind.notification => 'Protocol notification received.',
      DeviceObservationKind.rawProtocolMessage =>
        'Raw protocol message received.',
    };
  }

  void _logCommandError(String appDeviceId, String detail) {
    _logCommunicationError(appDeviceId, 'Lighting command rejected: $detail');
  }

  void _logCommunicationError(String appDeviceId, String detail) {
    _diagnostics.error(
      detail,
      deviceId: appDeviceId,
      deviceName: _deviceName(appDeviceId),
    );
  }

  String? _deviceName(String appDeviceId) {
    return state.devices[appDeviceId]?.endpoint.displayName;
  }

  void _handleTransportEvent(String appDeviceId, TransportSessionEvent event) {
    if (_disposed) {
      return;
    }
    switch (event.type) {
      case TransportSessionEventType.connected:
        _updateDeviceStatus(
          appDeviceId,
          DebugDeviceConnectionStatus.connected,
          detail: event.message ?? 'BLE transport connected.',
        );
        _diagnostics.info(
          event.message ?? 'BLE transport connected.',
          deviceId: appDeviceId,
          deviceName: _deviceName(appDeviceId),
        );
      case TransportSessionEventType.disconnected:
        final connection = _connections.remove(appDeviceId);
        unawaited(
          connection?.closeAfterTransportDisconnect() ?? Future<void>.value(),
        );
        _updateDeviceStatus(
          appDeviceId,
          DebugDeviceConnectionStatus.disconnected,
          detail: event.message ?? 'BLE transport disconnected.',
        );
        _diagnostics.warning(
          event.message ?? 'BLE transport disconnected.',
          deviceId: appDeviceId,
          deviceName: _deviceName(appDeviceId),
        );
      case TransportSessionEventType.reconnecting:
        _updateDeviceStatus(
          appDeviceId,
          DebugDeviceConnectionStatus.connecting,
          detail: event.message ?? 'Reconnecting…',
        );
        _diagnostics.warning(
          event.message ?? 'BLE transport reconnecting.',
          deviceId: appDeviceId,
          deviceName: _deviceName(appDeviceId),
        );
      case TransportSessionEventType.error:
        _updateDeviceStatus(
          appDeviceId,
          DebugDeviceConnectionStatus.error,
          detail: event.message ?? event.error?.toString(),
        );
        _logCommunicationError(
          appDeviceId,
          event.message ?? event.error?.toString() ?? 'BLE transport error.',
        );
    }
  }

  void _updateDeviceStatus(
    String appDeviceId,
    DebugDeviceConnectionStatus status, {
    String? detail,
  }) {
    final current = state.devices[appDeviceId];
    if (current == null || _disposed) {
      return;
    }
    _updateDevice(
      appDeviceId,
      current.copyWith(status: status, statusDetail: detail),
    );
  }

  void _updateDevice(String appDeviceId, DebugDevice device) {
    if (_disposed) {
      return;
    }
    final devices = Map<String, DebugDevice>.of(state.devices)
      ..[appDeviceId] = device;
    state = state.copyWith(devices: devices);
  }

  Future<void> _releaseResources() async {
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    final connections = _connections.values.toList();
    _connections.clear();
    for (final connection in connections) {
      await connection.close();
    }
  }

  static LightingFeature? _featureFor(LightingCommand command) {
    if (command is SetPower) {
      return LightingFeature.power;
    }
    if (command is SetColor) {
      return LightingFeature.rgb;
    }
    if (command is SetBrightness) {
      return LightingFeature.brightness;
    }
    if (command is SetNativeEffect) {
      return LightingFeature.nativeEffects;
    }
    return null;
  }

  static bool _wasAccepted(CommandResult result) {
    return result.outcome == CommandOutcome.queued ||
        result.outcome == CommandOutcome.deduplicated ||
        result.outcome == CommandOutcome.transmitted ||
        result.outcome == CommandOutcome.acknowledged ||
        result.outcome == CommandOutcome.observed;
  }
}

class _ManagedDeviceSession {
  _ManagedDeviceSession({
    required this.transportSession,
    required this.lightingSession,
  });

  final TransportSession transportSession;
  final LightingDeviceSession lightingSession;
  StreamSubscription<TransportSessionEvent>? transportEvents;
  StreamSubscription<DeviceObservation>? observations;

  Future<void> close() async {
    await transportEvents?.cancel();
    await observations?.cancel();
    await lightingSession.close();
    await transportSession.disconnect();
  }

  Future<void> closeAfterTransportDisconnect() async {
    await transportEvents?.cancel();
    await observations?.cancel();
    await lightingSession.close();
  }
}
