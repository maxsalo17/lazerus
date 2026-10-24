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

  /// Conservative, profile-specific write suppression for the inferred E1
  /// codec. These thresholds are not a measured claim about every ELK/Lotus
  /// controller; validate and tune them per hardware/firmware profile.
  static const ProtocolCommandDelta commandDelta = ProtocolCommandDelta(
    brightness: 2 / 255,
    rgbChannel: 2,
  );

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
      commandDelta: commandDelta,
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
            'brightnessDelta': '2/255 normalized',
            'rgbChannelDelta': '2',
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
    required this.commandDelta,
  }) {
    _incomingSubscription = transportSession.incomingMessages.listen(
      _onIncomingMessage,
    );
  }

  final TransportSession transportSession;

  @override
  final DeviceCapabilities capabilities;

  final bool allowUnverifiedCommands;

  @override
  final ProtocolCommandDelta commandDelta;

  final StreamController<DeviceObservation> _observations =
      StreamController<DeviceObservation>.broadcast();
  late final StreamSubscription<TransportMessage> _incomingSubscription;
  DesiredLightingState? _lastKnownState;
  DesiredLightingState? _lastTransmittedLightingState;
  final Map<int, Uint8List> _lastEmittedFrames = <int, Uint8List>{};
  Uint8List? _lastNativeEffectFrame;
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

    final plan = _planFor(command);
    if (plan == null) {
      return CommandResult.rejected(
        command,
        'This Lotus Lamp X profile does not encode the requested command.',
      );
    }
    if (plan.frames.isEmpty) {
      return CommandResult.deduplicated(
        command,
        'No Lotus Lamp X packet differed from the prior output or the configured command delta.',
      );
    }

    final receipts = <TransportReceipt>[];
    try {
      for (final frame in plan.frames) {
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

    _rememberTransmittedPlan(plan);
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

  _LotusCommandPlan? _planFor(LightingCommand command) {
    if (command is SetPower) {
      return _planForState(DesiredLightingState(power: command.enabled));
    }
    if (command is SetColor) {
      return _planForState(DesiredLightingState(color: command.color));
    }
    if (command is SetBrightness) {
      return _planForState(DesiredLightingState(brightness: command.value));
    }
    if (command is SetNativeEffect) {
      final effect = LotusLampXNativeEffect.fromDeviceEffect(command.effect);
      if (effect == null) return null;
      final frame = LotusLampXFrameCodec.nativeEffect(effect);
      if (_sameFrame(frame, _lastNativeEffectFrame) || !_isNewFrame(frame)) {
        return _LotusCommandPlan.empty();
      }
      return _LotusCommandPlan(
        frames: <Uint8List>[frame],
        nativeEffectFrame: frame,
      );
    }
    if (command is ApplyLightingState) {
      return _planForState(command.state);
    }
    return null;
  }

  _LotusCommandPlan _planForState(DesiredLightingState state) {
    if (state.power == false) {
      final frame = LotusLampXFrameCodec.power(false);
      return _shouldSendPower(false) && _isNewFrame(frame)
          ? _LotusCommandPlan(
              frames: <Uint8List>[frame],
              transmittedState: DesiredLightingState(power: false),
            )
          : _LotusCommandPlan.empty();
    }

    final frames = <Uint8List>[];
    bool? power;
    RgbColor? color;
    double? brightness;
    if (state.color != null) {
      final frame = LotusLampXFrameCodec.color(
        state.color!.red,
        state.color!.green,
        state.color!.blue,
      );
      if (_shouldSendColor(state.color!) && _isNewFrame(frame)) {
        frames.add(frame);
        color = state.color;
      }
    }
    if (state.brightness != null) {
      final frame = LotusLampXFrameCodec.brightness(
        LotusLampXFrameCodec.normalizedBrightnessToByte(state.brightness!),
      );
      if (_shouldSendBrightness(state.brightness!) && _isNewFrame(frame)) {
        frames.add(frame);
        brightness = state.brightness;
      }
    }
    if (state.power == true) {
      final frame = LotusLampXFrameCodec.power(true);
      if (_shouldSendPower(true) && _isNewFrame(frame)) {
        frames.add(frame);
        power = true;
      }
    }
    return _LotusCommandPlan(
      frames: frames,
      transmittedState: frames.isEmpty
          ? null
          : DesiredLightingState(
              power: power,
              color: color,
              brightness: brightness,
            ),
    );
  }

  void _onIncomingMessage(TransportMessage message) {
    if (_isClosed) {
      return;
    }
    final state = LotusLampXFrameCodec.tryDecodeE1State(message.payload);
    if (state != null) {
      _lastKnownState = _mergeState(_lastKnownState, state);
      _lastTransmittedLightingState = _mergeState(
        _lastTransmittedLightingState,
        state,
      );
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

  bool _shouldSendPower(bool candidate) =>
      _lastTransmittedLightingState?.power != candidate;

  bool _shouldSendColor(RgbColor candidate) {
    final previous = _lastTransmittedLightingState?.color;
    return previous == null ||
        !commandDelta.ignoresColorChange(previous, candidate);
  }

  bool _shouldSendBrightness(double candidate) {
    final previous = _lastTransmittedLightingState?.brightness;
    return previous == null ||
        !commandDelta.ignoresBrightnessChange(previous, candidate);
  }

  bool _isNewFrame(Uint8List frame) {
    final previous = _lastEmittedFrames[_frameKey(frame)];
    return !_sameFrame(previous, frame);
  }

  void _rememberTransmittedPlan(_LotusCommandPlan plan) {
    for (final frame in plan.frames) {
      _lastEmittedFrames[_frameKey(frame)] = Uint8List.fromList(frame);
    }
    final state = plan.transmittedState;
    if (state != null && !state.isEmpty) {
      _lastKnownState = _mergeState(_lastKnownState, state);
      _lastTransmittedLightingState = _mergeState(
        _lastTransmittedLightingState,
        state,
      );
      // A direct state frame can replace a native effect. The same effect may
      // therefore be intentionally selected again afterwards.
      _lastNativeEffectFrame = null;
      _lastEmittedFrames.remove(_modeFrameKey);
    }
    if (plan.nativeEffectFrame != null) {
      _lastNativeEffectFrame = Uint8List.fromList(plan.nativeEffectFrame!);
      // A native effect may alter visible direct-lighting parameters. Make a
      // future manual/static lighting command explicit instead of trusting a
      // stale cached RGB or brightness value.
      _lastTransmittedLightingState = null;
      _lastEmittedFrames.removeWhere(
        (key, _) =>
            key == _frameKey(LotusLampXFrameCodec.power(false)) ||
            key == _frameKey(LotusLampXFrameCodec.power(true)) ||
            key == _frameKey(LotusLampXFrameCodec.color(0, 0, 0)) ||
            key == _frameKey(LotusLampXFrameCodec.brightness(0)),
      );
    }
  }

  static int _frameKey(Uint8List frame) => (frame[1] << 8) | frame[2];

  // E1 mode packets have command-length byte 0x07 and command byte 0x03.
  static const int _modeFrameKey = 0x0703;

  static bool _sameFrame(Uint8List? left, Uint8List? right) {
    if (left == null || right == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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

final class _LotusCommandPlan {
  _LotusCommandPlan({
    required this.frames,
    this.transmittedState,
    this.nativeEffectFrame,
  });

  _LotusCommandPlan.empty()
    : frames = const <Uint8List>[],
      transmittedState = null,
      nativeEffectFrame = null;

  final List<Uint8List> frames;
  final DesiredLightingState? transmittedState;
  final Uint8List? nativeEffectFrame;
}
