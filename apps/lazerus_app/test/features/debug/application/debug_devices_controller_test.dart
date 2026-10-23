import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/persistence/device_identity_repository.dart';
import 'package:lazerus_app/features/calibration/application/device_calibration_controller.dart';
import 'package:lazerus_app/features/calibration/data/device_calibration_repository.dart';
import 'package:lazerus_app/features/calibration/domain/hue_calibration.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/diagnostics/application/diagnostics_controller.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:lazerus_proto_lotus_lamp_x/lazerus_proto_lotus_lamp_x.dart';

void main() {
  late _FakeBleTransport transport;
  late InMemoryDeviceCalibrationRepository calibrationRepository;
  late ProviderContainer container;
  late DebugDevicesController controller;

  setUp(() {
    transport = _FakeBleTransport();
    calibrationRepository = InMemoryDeviceCalibrationRepository();
    container = ProviderContainer(
      overrides: [
        bleTransportProvider.overrideWithValue(transport),
        deviceIdentityRepositoryProvider.overrideWithValue(
          const _EndpointIdentityRepository(),
        ),
        protocolAdapterRegistryProvider.overrideWithValue(
          ProtocolAdapterRegistry(<LightingProtocolAdapter>[
            LotusLampXProtocolAdapter(allowUnverifiedCommands: true),
          ]),
        ),
        deviceCalibrationRepositoryProvider.overrideWithValue(
          calibrationRepository,
        ),
      ],
    );
    controller = container.read(debugDevicesProvider.notifier);
  });

  tearDown(() {
    container.dispose();
    transport.dispose();
  });

  test(
    'recognizes a supported controller and connects automatically',
    () async {
      await controller.startDiscovery();
      transport.discoveries.add(
        TransportEndpointDiscovered(
          TransportEndpoint(
            id: 'peripheral-1',
            transport: TransportKind.ble,
            displayName: 'ELK test strip',
          ),
        ),
      );
      transport.discoveries.add(
        TransportEndpointDiscovered(
          TransportEndpoint(
            id: 'other-peripheral',
            transport: TransportKind.ble,
            displayName: 'Unknown controller',
          ),
        ),
      );
      await _settle();

      final state = container.read(debugDevicesProvider);
      expect(state.devices, hasLength(1));
      expect(
        state.devices['peripheral-1']!.status,
        DebugDeviceConnectionStatus.connected,
      );
      expect(transport.connectCount, 1);
    },
  );

  test(
    'gates inferred control frames until diagnostic mode is enabled',
    () async {
      await controller.startDiscovery();
      transport.discoveries.add(
        TransportEndpointDiscovered(
          TransportEndpoint(
            id: 'peripheral-1',
            transport: TransportKind.ble,
            displayName: 'MELK diagnostic strip',
          ),
        ),
      );
      await _settle();

      controller.setDiagnosticCommandsEnabled(false);
      final rejected = await controller.execute(
        'peripheral-1',
        const SetPower(true),
      );
      expect(rejected.outcome, CommandOutcome.rejected);
      expect(transport.session.sentMessages, isEmpty);

      controller.setDiagnosticCommandsEnabled(true);
      final transmitted = await controller.execute(
        'peripheral-1',
        const SetPower(true),
      );

      expect(transmitted.outcome, CommandOutcome.transmitted);
      expect(transport.session.sentMessages, hasLength(1));
      expect(
        transport.session.sentMessages.single.payload,
        orderedEquals(<int>[
          0x7e,
          0x07,
          0x04,
          0xff,
          0x01,
          0x01,
          0x02,
          0x01,
          0xef,
        ]),
      );
      expect(
        container
            .read(debugDevicesProvider)
            .devices['peripheral-1']!
            .requestedPower,
        isTrue,
      );
    },
  );

  test('records a best-effort inbound Lotus state in diagnostics', () async {
    await controller.startDiscovery();
    transport.discoveries.add(
      TransportEndpointDiscovered(
        TransportEndpoint(
          id: 'peripheral-1',
          transport: TransportKind.ble,
          displayName: 'ELK test strip',
        ),
      ),
    );
    await _settle();

    transport.session.emitIncoming(
      TransportMessage(
        LotusLampXFrameCodec.color(20, 40, 60),
        channel: LotusLampXBleIdentifiers.notifyCharacteristicUuid,
      ),
    );
    await _settle();

    final device = container
        .read(debugDevicesProvider)
        .devices['peripheral-1']!;
    expect(device.observedState!.color, RgbColor(20, 40, 60));
    expect(
      container
          .read(diagnosticsProvider)
          .entries
          .where((entry) => entry.observedState != null),
      isNotEmpty,
    );
  });

  test(
    'maps a calibrated colour only at the protocol command boundary',
    () async {
      final profile = HueCalibrationProfile(
        id: 'warm-strip',
        name: 'Warm strip correction',
        protocolId: LotusLampXProtocolAdapter.adapterId,
        hueStartDegrees: 0,
        hueEndDegrees: 285,
        anchors: const <HueCalibrationAnchor>[
          HueCalibrationAnchor(input: 0, output: 0),
          HueCalibrationAnchor(input: .5, output: .75),
          HueCalibrationAnchor(input: 1, output: 1),
        ],
      );
      await calibrationRepository.save(
        DeviceCalibrationConfiguration(
          profiles: <HueCalibrationProfile>[profile],
          assignments: const <String, String>{'peripheral-1': 'warm-strip'},
        ),
      );
      container.read(deviceCalibrationProvider.notifier);
      await _settle();
      await controller.startDiscovery();
      transport.discoveries.add(
        TransportEndpointDiscovered(
          TransportEndpoint(
            id: 'peripheral-1',
            transport: TransportKind.ble,
            displayName: 'ELK test strip',
          ),
        ),
      );
      await _settle();
      final desired = RgbColor(255, 128, 0);

      final result = await controller.execute(
        'peripheral-1',
        SetColor(desired),
      );

      final transportColor = profile.mapColor(desired);
      expect(result.command, isA<SetColor>());
      expect((result.command as SetColor).color, desired);
      expect(
        transport.session.sentMessages.last.payload,
        orderedEquals(
          LotusLampXFrameCodec.color(
            transportColor.red,
            transportColor.green,
            transportColor.blue,
          ),
        ),
      );
      final device = container
          .read(debugDevicesProvider)
          .devices['peripheral-1']!;
      expect(device.requestedColor, desired);
      expect(device.lastKnownState.color, desired);
      expect(device.transportState!.color, transportColor);
    },
  );

  test('records a current-state read failure in diagnostics', () async {
    transport.session.readError = StateError('FFF4 read failed');
    await controller.startDiscovery();
    transport.discoveries.add(
      TransportEndpointDiscovered(
        TransportEndpoint(
          id: 'peripheral-1',
          transport: TransportKind.ble,
          displayName: 'ELK test strip',
        ),
      ),
    );
    await _settle();

    expect(
      container
          .read(diagnosticsProvider)
          .entries
          .any(
            (entry) => entry.message.contains('Current-state request failed'),
          ),
      isTrue,
    );
  });
}

Future<void> _settle() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeBleTransport implements DeviceTransport {
  final StreamController<TransportDiscoveryEvent> discoveries =
      StreamController<TransportDiscoveryEvent>.broadcast();
  final _FakeTransportSession session = _FakeTransportSession();
  var connectCount = 0;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  TransportCapabilities get capabilities => TransportCapabilities(
    discoveryModes: const <DiscoveryMode>{DiscoveryMode.activeScan},
    supportsPersistentConnections: true,
  );

  @override
  Future<TransportSession> connect(
    TransportEndpoint endpoint,
    ConnectionOptions options,
  ) async {
    connectCount++;
    session.endpoint = endpoint;
    return session;
  }

  @override
  Stream<TransportDiscoveryEvent> discover(DiscoveryRequest request) {
    return discoveries.stream;
  }

  void dispose() {
    unawaited(discoveries.close());
    session.dispose();
  }
}

class _EndpointIdentityRepository implements DeviceIdentityRepository {
  const _EndpointIdentityRepository();

  @override
  Future<String> resolve(
    TransportEndpoint endpoint, {
    required String protocolId,
  }) async {
    return endpoint.id;
  }
}

class _FakeTransportSession implements TransportSession {
  final StreamController<TransportSessionEvent> _events =
      StreamController<TransportSessionEvent>.broadcast();
  final StreamController<TransportMessage> _messages =
      StreamController<TransportMessage>.broadcast();
  final List<TransportMessage> sentMessages = <TransportMessage>[];
  Object? readError;

  @override
  TransportEndpoint endpoint = TransportEndpoint(
    id: 'placeholder',
    transport: TransportKind.ble,
  );

  @override
  Stream<TransportSessionEvent> get events => _events.stream;

  @override
  Stream<TransportMessage> get incomingMessages => _messages.stream;

  @override
  Future<void> disconnect() async {
    if (!_events.isClosed) {
      _events.add(
        TransportSessionEvent(type: TransportSessionEventType.disconnected),
      );
    }
  }

  @override
  Future<TransportReceipt> send(TransportMessage message) async {
    sentMessages.add(message);
    return const TransportReceipt(status: TransportDeliveryStatus.transmitted);
  }

  @override
  Future<TransportMessage?> read(String channel) async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return null;
  }

  void emitIncoming(TransportMessage message) {
    _messages.add(message);
  }

  void dispose() {
    unawaited(_events.close());
    unawaited(_messages.close());
  }
}
