import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:lazerus_core/lazerus_core.dart';

/// BLE transport backed by the `bluetooth_low_energy` central-manager API.
///
/// The class deliberately knows nothing about a lighting brand or protocol.
/// A protocol adapter selects the GATT characteristic through
/// [TransportMessage.channel]. Endpoint IDs are transient platform link data;
/// they are not Lazerus' persisted device identities.
class BluetoothLowEnergyTransport implements DeviceTransport {
  BluetoothLowEnergyTransport({CentralManager? manager})
    : _manager = manager ?? CentralManager();

  static const _adapterReadinessTimeout = Duration(seconds: 5);

  final CentralManager _manager;
  final Map<String, Peripheral> _peripherals = <String, Peripheral>{};
  final Map<String, _BluetoothLowEnergyTransportSession> _sessions =
      <String, _BluetoothLowEnergyTransportSession>{};

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  TransportCapabilities get capabilities => TransportCapabilities(
    discoveryModes: const <DiscoveryMode>{DiscoveryMode.activeScan},
    supportsPersistentConnections: true,
    supportsIncomingMessages: true,
    supportsReadRequests: true,
    supportsDeliveryAcknowledgements: true,
  );

  @override
  Stream<TransportDiscoveryEvent> discover(DiscoveryRequest request) {
    late final StreamController<TransportDiscoveryEvent> controller;
    StreamSubscription<DiscoveredEventArgs>? discoveredSubscription;
    Timer? timeout;
    var completed = false;

    Future<void> finish() async {
      if (completed) {
        return;
      }
      completed = true;
      timeout?.cancel();
      await discoveredSubscription?.cancel();
      try {
        await _manager.stopDiscovery();
      } on Object catch (error) {
        if (!controller.isClosed) {
          controller.add(
            TransportDiscoveryError(
              error,
              message: 'Unable to stop the BLE discovery session.',
            ),
          );
        }
      }
      if (!controller.isClosed) {
        controller.add(const TransportDiscoveryComplete());
        await controller.close();
      }
    }

    controller = StreamController<TransportDiscoveryEvent>(
      onListen: () async {
        discoveredSubscription = _manager.discovered.listen(
          (event) {
            final endpoint = _endpointFrom(event);
            _peripherals[endpoint.id] = event.peripheral;
            if (request.includeUnidentified ||
                _matchesRequest(endpoint, request)) {
              controller.add(TransportEndpointDiscovered(endpoint));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            controller.add(
              TransportDiscoveryError(
                error,
                message: 'The BLE platform reported a discovery error.',
              ),
            );
          },
        );

        try {
          // CentralManager is initialized asynchronously by the plugin and
          // starts as `unknown`. Starting a CoreBluetooth scan before it is
          // powered on can silently produce no discoveries on the first app
          // launch, while the next scan succeeds. Subscribe before checking
          // the current state so no powered-on transition is missed.
          await _waitForPoweredOn();
          if (completed || controller.isClosed) {
            return;
          }
          // Scan generally: several supported controllers advertise a name but
          // no service UUID until after a connection is established.
          await _manager.startDiscovery();
          timeout = Timer(request.timeout, () {
            unawaited(finish());
          });
        } on Object catch (error) {
          if (!controller.isClosed) {
            controller.add(
              TransportDiscoveryError(
                error,
                message: 'BLE discovery could not be started.',
              ),
            );
          }
          await finish();
        }
      },
      onCancel: finish,
    );

    return controller.stream;
  }

  Future<void> _waitForPoweredOn() async {
    if (_manager.state == BluetoothLowEnergyState.poweredOn) {
      return;
    }

    final ready = Completer<void>();
    late final StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>
    stateSubscription;

    void resolveIfPoweredOn(BluetoothLowEnergyState state) {
      if (state == BluetoothLowEnergyState.poweredOn && !ready.isCompleted) {
        ready.complete();
      }
    }

    stateSubscription = _manager.stateChanged.listen(
      (event) => resolveIfPoweredOn(event.state),
      onError: (Object error, StackTrace stackTrace) {
        if (!ready.isCompleted) {
          ready.completeError(error, stackTrace);
        }
      },
    );
    // The adapter can transition between the first check and the subscription.
    resolveIfPoweredOn(_manager.state);

    try {
      await ready.future.timeout(
        _adapterReadinessTimeout,
        onTimeout: () => throw TimeoutException(
          'Bluetooth did not reach powered-on state within '
          '${_adapterReadinessTimeout.inSeconds} seconds.',
        ),
      );
    } finally {
      await stateSubscription.cancel();
    }
  }

  @override
  Future<TransportSession> connect(
    TransportEndpoint endpoint,
    ConnectionOptions options,
  ) async {
    if (endpoint.transport != TransportKind.ble) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Expected a BLE endpoint.',
      );
    }

    final existing = _sessions[endpoint.id];
    if (existing != null && !existing.isClosed) {
      return existing;
    }

    final peripheral = _peripherals[endpoint.id];
    if (peripheral == null) {
      throw StateError(
        'The BLE endpoint is no longer available. Run discovery before connecting.',
      );
    }

    await _manager.connect(peripheral).timeout(options.timeout);
    final services = await _manager
        .discoverGATT(peripheral)
        .timeout(options.timeout);
    final session = _BluetoothLowEnergyTransportSession(
      manager: _manager,
      peripheral: peripheral,
      endpoint: endpoint,
      services: services,
      onClosed: () {
        _sessions.remove(endpoint.id);
      },
    );
    _sessions[endpoint.id] = session;
    return session;
  }

  TransportEndpoint _endpointFrom(DiscoveredEventArgs event) {
    final serviceIds = event.advertisement.serviceUUIDs
        .map((uuid) => uuid.toString())
        .toSet();
    final name = event.advertisement.name;
    final metadata = <String, String>{'rssi': '${event.rssi}'};
    if (name != null) {
      metadata['localName'] = name;
    }
    return TransportEndpoint(
      id: event.peripheral.uuid.toString(),
      transport: TransportKind.ble,
      displayName: name,
      advertisedServiceIds: serviceIds,
      metadata: metadata,
    );
  }

  bool _matchesRequest(TransportEndpoint endpoint, DiscoveryRequest request) {
    final name = (endpoint.displayName ?? '').toLowerCase();
    final matchesName = request.namePrefixes.any(name.startsWith);
    final matchesService = request.serviceIds.any(
      endpoint.hasAdvertisedService,
    );
    return matchesName || matchesService;
  }
}

class _BluetoothLowEnergyTransportSession implements TransportSession {
  _BluetoothLowEnergyTransportSession({
    required CentralManager manager,
    required Peripheral peripheral,
    required this.endpoint,
    required List<GATTService> services,
    required void Function() onClosed,
  }) : _manager = manager,
       _peripheral = peripheral,
       _onClosed = onClosed,
       _characteristics = _indexCharacteristics(services) {
    _connectionSubscription = _manager.connectionStateChanged.listen(
      _onConnectionStateChanged,
    );
    _notificationSubscription = _manager.characteristicNotified.listen(
      _onCharacteristicNotified,
    );
    unawaited(_enableAvailableNotifications());
  }

  final CentralManager _manager;
  final Peripheral _peripheral;
  final void Function() _onClosed;
  final Map<String, GATTCharacteristic> _characteristics;
  final StreamController<TransportSessionEvent> _events =
      StreamController<TransportSessionEvent>.broadcast();
  final StreamController<TransportMessage> _incomingMessages =
      StreamController<TransportMessage>.broadcast();
  late final StreamSubscription<PeripheralConnectionStateChangedEventArgs>
  _connectionSubscription;
  late final StreamSubscription<GATTCharacteristicNotifiedEventArgs>
  _notificationSubscription;
  var _isClosed = false;

  @override
  final TransportEndpoint endpoint;

  bool get isClosed => _isClosed;

  @override
  Stream<TransportSessionEvent> get events => _events.stream;

  @override
  Stream<TransportMessage> get incomingMessages => _incomingMessages.stream;

  @override
  Future<TransportReceipt> send(TransportMessage message) async {
    if (_isClosed) {
      return const TransportReceipt(
        status: TransportDeliveryStatus.failed,
        detail: 'The BLE session is closed.',
      );
    }

    final characteristic = _resolveCharacteristic(message.channel);
    if (characteristic == null) {
      return TransportReceipt(
        status: TransportDeliveryStatus.failed,
        detail: message.channel == null
            ? 'No writable GATT characteristic is available.'
            : 'The requested GATT characteristic is unavailable or not writable.',
      );
    }

    final writeType = _writeTypeFor(characteristic);
    if (writeType == null) {
      return const TransportReceipt(
        status: TransportDeliveryStatus.failed,
        detail: 'The requested GATT characteristic is not writable.',
      );
    }

    try {
      final maximumLength = await _manager.getMaximumWriteLength(
        _peripheral,
        type: writeType,
      );
      if (maximumLength <= 0) {
        throw StateError('The BLE stack reported an invalid write length.');
      }
      for (
        var start = 0;
        start < message.payload.length;
        start += maximumLength
      ) {
        final end = (start + maximumLength).clamp(0, message.payload.length);
        await _manager.writeCharacteristic(
          _peripheral,
          characteristic,
          value: Uint8List.fromList(message.payload.sublist(start, end)),
          type: writeType,
        );
      }
      return TransportReceipt(
        status: writeType == GATTCharacteristicWriteType.withResponse
            ? TransportDeliveryStatus.acknowledged
            : TransportDeliveryStatus.transmitted,
        detail: writeType == GATTCharacteristicWriteType.withResponse
            ? 'The GATT write received a transport-level response.'
            : 'The BLE stack accepted a write without response.',
      );
    } on Object catch (error) {
      _events.add(
        TransportSessionEvent(
          type: TransportSessionEventType.error,
          error: error,
          message: 'BLE characteristic write failed.',
        ),
      );
      return TransportReceipt(
        status: TransportDeliveryStatus.failed,
        detail: 'BLE write failed: $error',
      );
    }
  }

  @override
  Future<TransportMessage?> read(String channel) async {
    if (_isClosed) {
      throw StateError('The BLE session is closed.');
    }
    final characteristic = _characteristics[channel.toLowerCase()];
    if (characteristic == null ||
        !characteristic.properties.contains(GATTCharacteristicProperty.read)) {
      return null;
    }
    try {
      final value = await _manager.readCharacteristic(
        _peripheral,
        characteristic,
      );
      return TransportMessage(value, channel: channel.toLowerCase());
    } on Object catch (error) {
      _events.add(
        TransportSessionEvent(
          type: TransportSessionEventType.error,
          error: error,
          message: 'BLE characteristic read failed.',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_isClosed) {
      return;
    }
    try {
      await _manager.disconnect(_peripheral);
    } finally {
      await _close(emitDisconnected: true);
    }
  }

  static Map<String, GATTCharacteristic> _indexCharacteristics(
    List<GATTService> services,
  ) {
    final characteristics = <String, GATTCharacteristic>{};
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        characteristics[characteristic.uuid.toString().toLowerCase()] =
            characteristic;
      }
    }
    return characteristics;
  }

  GATTCharacteristic? _resolveCharacteristic(String? requestedChannel) {
    if (requestedChannel != null) {
      final requested = _characteristics[requestedChannel.toLowerCase()];
      return _writeTypeFor(requested) == null ? null : requested;
    }
    for (final characteristic in _characteristics.values) {
      if (_writeTypeFor(characteristic) != null) {
        return characteristic;
      }
    }
    return null;
  }

  GATTCharacteristicWriteType? _writeTypeFor(
    GATTCharacteristic? characteristic,
  ) {
    if (characteristic == null) {
      return null;
    }
    if (characteristic.properties.contains(
      GATTCharacteristicProperty.writeWithoutResponse,
    )) {
      return GATTCharacteristicWriteType.withoutResponse;
    }
    if (characteristic.properties.contains(GATTCharacteristicProperty.write)) {
      return GATTCharacteristicWriteType.withResponse;
    }
    return null;
  }

  Future<void> _enableAvailableNotifications() async {
    for (final characteristic in _characteristics.values) {
      final supportsNotifications =
          characteristic.properties.contains(
            GATTCharacteristicProperty.notify,
          ) ||
          characteristic.properties.contains(
            GATTCharacteristicProperty.indicate,
          );
      if (!supportsNotifications || _isClosed) {
        continue;
      }
      try {
        await _manager.setCharacteristicNotifyState(
          _peripheral,
          characteristic,
          state: true,
        );
      } on Object catch (error) {
        _events.add(
          TransportSessionEvent(
            type: TransportSessionEventType.error,
            error: error,
            message: 'BLE notifications could not be enabled.',
          ),
        );
      }
    }
  }

  void _onConnectionStateChanged(
    PeripheralConnectionStateChangedEventArgs event,
  ) {
    if (event.peripheral.uuid != _peripheral.uuid || _isClosed) {
      return;
    }
    if (event.state == ConnectionState.connected) {
      _events.add(
        TransportSessionEvent(type: TransportSessionEventType.connected),
      );
      return;
    }
    unawaited(_close(emitDisconnected: true));
  }

  void _onCharacteristicNotified(GATTCharacteristicNotifiedEventArgs event) {
    if (event.peripheral.uuid != _peripheral.uuid || _isClosed) {
      return;
    }
    _incomingMessages.add(
      TransportMessage(
        event.value,
        channel: event.characteristic.uuid.toString().toLowerCase(),
      ),
    );
  }

  Future<void> _close({required bool emitDisconnected}) async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    if (emitDisconnected && !_events.isClosed) {
      _events.add(
        TransportSessionEvent(type: TransportSessionEventType.disconnected),
      );
    }
    await _connectionSubscription.cancel();
    await _notificationSubscription.cancel();
    await _incomingMessages.close();
    await _events.close();
    _onClosed();
  }
}
