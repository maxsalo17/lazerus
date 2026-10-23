import 'dart:async';
import 'dart:typed_data';

import 'package:lazerus_core/lazerus_core.dart';

import 'lotus_lamp_x_codec.dart';
import 'lotus_lamp_x_identifiers.dart';

/// Adapter for the initial BLE-only Lotus Lamp X / ELK reference profile.
///
/// Frame semantics are inferred from LotusLampX and are deliberately exposed as
/// [CapabilityAvailability.inferred] until confirmed on target hardware.
class LotusLampXProtocolAdapter implements LightingProtocolAdapter {
  LotusLampXProtocolAdapter({
    this.allowUnverifiedCommands = false,
    this.selectionPriority = 0,
  });

  static const String adapterId = 'lazerus.protocol.lotus_lamp_x';

  /// Enables command writes only for an explicitly chosen diagnostic session.
  ///
  /// Product UI must leave this false until the matching hardware profile has
  /// been physically validated.
  final bool allowUnverifiedCommands;

  @override
  final int selectionPriority;

  @override
  String get id => adapterId;

  @override
  Set<TransportKind> get supportedTransports => const <TransportKind>{
    TransportKind.ble,
  };

  @override
  ProtocolDiscoverySpec discoverySpecFor(TransportKind transport) {
    if (transport != TransportKind.ble) {
      throw ArgumentError.value(
        transport,
        'transport',
        'Lotus Lamp X requires BLE.',
      );
    }

    return ProtocolDiscoverySpec(
      transport: TransportKind.ble,
      serviceIds: <String>{LotusLampXBleIdentifiers.serviceUuid},
      namePrefixes: LotusLampXBleIdentifiers.namePrefixes,
      safeProbeAvailable: false,
    );
  }

  @override
  ProtocolMatch match(TransportEndpoint endpoint) {
    if (endpoint.transport != TransportKind.ble) {
      return const ProtocolMatch.noMatch(reason: 'Lotus Lamp X requires BLE.');
    }

    final name = (endpoint.displayName ?? endpoint.metadata['localName'])
        ?.toLowerCase();
    final matchesName =
        name != null &&
        LotusLampXBleIdentifiers.namePrefixes.any(name.startsWith);
    final matchesService = endpoint.hasAdvertisedService(
      LotusLampXBleIdentifiers.serviceUuid,
    );

    if (matchesName && matchesService) {
      return const ProtocolMatch(
        kind: ProtocolMatchKind.matched,
        confidence: 85,
        requiresProbe: true,
        reason: 'Known ELK/MELK name and the FFF0 service were advertised.',
      );
    }
    if (matchesName) {
      return const ProtocolMatch(
        kind: ProtocolMatchKind.candidate,
        confidence: 65,
        requiresProbe: true,
        reason: 'Known ELK/MELK name; service advertisement is optional.',
      );
    }
    if (matchesService) {
      return const ProtocolMatch(
        kind: ProtocolMatchKind.candidate,
        confidence: 35,
        requiresProbe: true,
        reason:
            'FFF0 service alone is insufficient to identify a protocol family.',
      );
    }

    return const ProtocolMatch.noMatch(
      reason: 'No Lotus Lamp X discovery signal.',
    );
  }

  @override
  Future<ProtocolProbeResult> probe(
    TransportSession session,
    ProtocolProbeOptions options,
  ) async {
    if (session.endpoint.transport != TransportKind.ble) {
      return const ProtocolProbeResult(
        status: ProtocolProbeStatus.unsupported,
        reason: 'Lotus Lamp X requires a BLE transport session.',
      );
    }

    final protocolMatch = match(session.endpoint);
    if (!protocolMatch.isMatch) {
      return const ProtocolProbeResult(
        status: ProtocolProbeStatus.unsupported,
        reason: 'The endpoint does not match Lotus Lamp X discovery signals.',
      );
    }

    return ProtocolProbeResult(
      status: ProtocolProbeStatus.unverified,
      capabilities: inferredCapabilities(),
      reason:
          'E1 command framing is inferred from LotusLampX and awaits hardware validation.',
    );
  }

  @override
  Future<LightingDeviceSession> openSession(
    TransportSession transportSession,
    ProtocolProbeResult probe,
  ) async {
    if (transportSession.endpoint.transport != TransportKind.ble) {
      throw ArgumentError.value(
        transportSession,
        'transportSession',
        'Lotus Lamp X requires a BLE transport session.',
      );
    }
    if (!match(transportSession.endpoint).isMatch) {
      throw StateError('The transport endpoint does not match Lotus Lamp X.');
    }
    if (probe.status == ProtocolProbeStatus.unsupported ||
        probe.status == ProtocolProbeStatus.failed) {
      throw StateError(
        'Cannot open a Lotus Lamp X session for an unsupported probe.',
      );
    }

    return LotusLampXDeviceSession(
      transportSession: transportSession,
      capabilities: probe.capabilities ?? inferredCapabilities(),
      allowUnverifiedCommands: allowUnverifiedCommands,
    );
  }

  /// Capability claims that are available to diagnostics but not ordinary UI.
  DeviceCapabilities inferredCapabilities() {
    return DeviceCapabilities(
      features: <LightingFeature, FeatureCapability>{
        LightingFeature.power: FeatureCapability(
          availability: CapabilityAvailability.inferred,
        ),
        LightingFeature.rgb: FeatureCapability(
          availability: CapabilityAvailability.inferred,
        ),
        LightingFeature.brightness: FeatureCapability(
          availability: CapabilityAvailability.inferred,
          range: const NumericRange(0, 1),
        ),
        LightingFeature.nativeEffects: FeatureCapability(
          availability: CapabilityAvailability.inferred,
          supportedValues: LotusLampXNativeEffect.values
              .map((effect) => effect.effectId)
              .toSet(),
        ),
        LightingFeature.effectSpeed: FeatureCapability(
          availability: CapabilityAvailability.inferred,
          range: const NumericRange(0, 1),
        ),
        LightingFeature.notifications: FeatureCapability(
          availability: CapabilityAvailability.inferred,
        ),
      },
      protocolExtensions: <String, ProtocolCapability>{
        'lotus_lamp_x.e1_plain_frames': ProtocolCapability(
          id: 'lotus_lamp_x.e1_plain_frames',
          availability: CapabilityAvailability.inferred,
          metadata: const <String, String>{
            'frameLength': '9',
            'writeCharacteristic':
                LotusLampXBleIdentifiers.writeCharacteristicUuid,
          },
        ),
      },
    );
  }
}

/// A protocol-aware session over an already-connected BLE transport session.
class LotusLampXDeviceSession implements LightingDeviceSession {
  LotusLampXDeviceSession({
    required this.transportSession,
    required this.capabilities,
    required this.allowUnverifiedCommands,
  }) {
    _incomingSubscription = transportSession.incomingMessages.listen(
      _onIncomingMessage,
    );
  }

  final TransportSession transportSession;

  @override
  final DeviceCapabilities capabilities;

  final bool allowUnverifiedCommands;
  final StreamController<DeviceObservation> _observations =
      StreamController<DeviceObservation>.broadcast();
  late final StreamSubscription<TransportMessage> _incomingSubscription;
  DesiredLightingState? _lastKnownState;
  var _isClosed = false;

  @override
  String get protocolAdapterId => LotusLampXProtocolAdapter.adapterId;

  @override
  Stream<DeviceObservation> get observations => _observations.stream;

  @override
  DesiredLightingState? get lastKnownState => _lastKnownState;

  @override
  Future<CommandResult> execute(LightingCommand command) async {
    if (_isClosed) {
      return CommandResult.rejected(
        command,
        'The Lotus Lamp X session is closed.',
      );
    }
    if (!allowUnverifiedCommands) {
      return CommandResult.rejected(
        command,
        'Lotus Lamp X commands are inferred and require diagnostic opt-in until hardware validation.',
      );
    }

    final frames = _framesFor(command);
    if (frames == null) {
      return CommandResult.rejected(
        command,
        'This Lotus Lamp X profile does not encode the requested command.',
      );
    }

    final receipts = <TransportReceipt>[];
    try {
      for (final frame in frames) {
        final receipt = await transportSession.send(
          TransportMessage(
            frame,
            channel: LotusLampXBleIdentifiers.writeCharacteristicUuid,
          ),
        );
        receipts.add(receipt);
        if (receipt.status == TransportDeliveryStatus.failed) {
          return CommandResult.failed(
            command,
            StateError(
              receipt.detail ?? 'Transport rejected the Lotus Lamp X frame.',
            ),
            receipts: receipts,
          );
        }
      }
    } on Object catch (error) {
      return CommandResult.failed(command, error, receipts: receipts);
    }

    final outcome =
        receipts.any(
          (receipt) => receipt.status == TransportDeliveryStatus.acknowledged,
        )
        ? CommandOutcome.acknowledged
        : receipts.any(
            (receipt) => receipt.status == TransportDeliveryStatus.transmitted,
          )
        ? CommandOutcome.transmitted
        : CommandOutcome.queued;

    _rememberCommand(command);
    return CommandResult(
      command: command,
      outcome: outcome,
      receipts: receipts,
      detail:
          'Frames were accepted by the transport; physical execution is unconfirmed.',
    );
  }

  @override
  Future<void> requestCurrentState() async {
    if (_isClosed) {
      return;
    }
    final message = await transportSession.read(
      LotusLampXBleIdentifiers.notifyCharacteristicUuid,
    );
    if (message == null) {
      _observations.add(
        DeviceObservation(
          kind: DeviceObservationKind.notification,
          detail:
              'FFF4 is not readable; waiting for controller notifications instead.',
        ),
      );
      return;
    }
    _onIncomingMessage(message);
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _incomingSubscription.cancel();
    await _observations.close();
  }

  List<Uint8List>? _framesFor(LightingCommand command) {
    if (command is SetPower) {
      return <Uint8List>[LotusLampXFrameCodec.power(command.enabled)];
    }
    if (command is SetColor) {
      return <Uint8List>[
        LotusLampXFrameCodec.color(
          command.color.red,
          command.color.green,
          command.color.blue,
        ),
      ];
    }
    if (command is SetBrightness) {
      return <Uint8List>[
        LotusLampXFrameCodec.brightness(
          LotusLampXFrameCodec.normalizedBrightnessToByte(command.value),
        ),
      ];
    }
    if (command is SetNativeEffect) {
      final effect = LotusLampXNativeEffect.fromDeviceEffect(command.effect);
      return effect == null
          ? null
          : <Uint8List>[LotusLampXFrameCodec.nativeEffect(effect)];
    }
    if (command is ApplyLightingState) {
      return _framesForState(command.state);
    }
    return null;
  }

  List<Uint8List> _framesForState(DesiredLightingState state) {
    if (state.power == false) {
      return <Uint8List>[LotusLampXFrameCodec.power(false)];
    }

    final frames = <Uint8List>[];
    if (state.color != null) {
      frames.add(
        LotusLampXFrameCodec.color(
          state.color!.red,
          state.color!.green,
          state.color!.blue,
        ),
      );
    }
    if (state.brightness != null) {
      frames.add(
        LotusLampXFrameCodec.brightness(
          LotusLampXFrameCodec.normalizedBrightnessToByte(state.brightness!),
        ),
      );
    }
    if (state.power == true) {
      frames.add(LotusLampXFrameCodec.power(true));
    }
    return frames;
  }

  void _onIncomingMessage(TransportMessage message) {
    if (_isClosed) {
      return;
    }
    final state = LotusLampXFrameCodec.tryDecodeE1State(message.payload);
    if (state != null) {
      _lastKnownState = _mergeState(_lastKnownState, state);
    }
    _observations.add(
      DeviceObservation(
        kind: state == null
            ? DeviceObservationKind.rawProtocolMessage
            : DeviceObservationKind.state,
        state: state == null ? null : _lastKnownState,
        rawData: message.payload,
        detail: state == null
            ? 'Raw message received on ${message.channel ?? 'the default channel'}.'
            : 'Best-effort E1 state decoded from ${message.channel ?? 'the default channel'}.',
      ),
    );
  }

  void _rememberCommand(LightingCommand command) {
    final state = switch (command) {
      SetPower(:final enabled) => DesiredLightingState(power: enabled),
      SetColor(:final color) => DesiredLightingState(color: color),
      SetBrightness(:final value) => DesiredLightingState(brightness: value),
      ApplyLightingState(:final state) => state,
      _ => null,
    };
    if (state != null) {
      _lastKnownState = _mergeState(_lastKnownState, state);
    }
  }

  static DesiredLightingState _mergeState(
    DesiredLightingState? previous,
    DesiredLightingState incoming,
  ) {
    return DesiredLightingState(
      power: incoming.power ?? previous?.power,
      color: incoming.color ?? previous?.color,
      brightness: incoming.brightness ?? previous?.brightness,
    );
  }
}
