import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lazerus_core/lazerus_core.dart';
import 'package:lazerus_proto_lotus_lamp_x/lazerus_proto_lotus_lamp_x.dart';

void main() {
  test('encodes inferred Lotus Lamp X E1 frames', () {
    expect(
      LotusLampXFrameCodec.power(true),
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
      LotusLampXFrameCodec.brightness(128),
      orderedEquals(<int>[0x7e, 0x04, 0x01, 128, 0xff, 0xff, 0xff, 0x00, 0xef]),
    );
    expect(
      LotusLampXFrameCodec.color(1, 2, 3),
      orderedEquals(<int>[0x7e, 0x07, 0x05, 0x03, 1, 2, 3, 0x10, 0xef]),
    );
  });

  test('decodes E1-shaped inbound state only as a best-effort value', () {
    final color = LotusLampXFrameCodec.tryDecodeE1State(
      LotusLampXFrameCodec.color(1, 2, 3),
    );
    final brightness = LotusLampXFrameCodec.tryDecodeE1State(
      LotusLampXFrameCodec.brightness(128),
    );

    expect(color!.color, RgbColor(1, 2, 3));
    expect(brightness!.brightness, closeTo(128 / 255, 0.0001));
    expect(
      LotusLampXFrameCodec.tryDecodeE1State(Uint8List.fromList(<int>[0x00])),
      isNull,
    );
  });

  test(
    'recognizes a named ELK device without requiring a service advertisement',
    () {
      final adapter = LotusLampXProtocolAdapter();

      final match = adapter.match(
        TransportEndpoint(
          id: 'ble-endpoint',
          transport: TransportKind.ble,
          displayName: 'ELK-BLEDDM',
        ),
      );

      expect(match.kind, ProtocolMatchKind.candidate);
      expect(match.requiresProbe, isTrue);
      expect(match.confidence, 65);
    },
  );

  test(
    'keeps inferred commands disabled until an explicit diagnostic opt-in',
    () async {
      final transport = _RecordingTransportSession();
      final adapter = LotusLampXProtocolAdapter();
      final device = await adapter.openSession(
        transport,
        const ProtocolProbeResult(status: ProtocolProbeStatus.unverified),
      );

      final result = await device.execute(const SetPower(true));

      expect(result.outcome, CommandOutcome.rejected);
      expect(transport.sentMessages, isEmpty);
      await device.close();
      await transport.dispose();
    },
  );

  test(
    'sends an opted-in command through the generic transport session',
    () async {
      final transport = _RecordingTransportSession();
      final adapter = LotusLampXProtocolAdapter(allowUnverifiedCommands: true);
      final device = await adapter.openSession(
        transport,
        const ProtocolProbeResult(status: ProtocolProbeStatus.unverified),
      );

      final result = await device.execute(SetColor(RgbColor(1, 2, 3)));

      expect(result.outcome, CommandOutcome.transmitted);
      expect(transport.sentMessages, hasLength(1));
      expect(
        transport.sentMessages.single.channel,
        LotusLampXBleIdentifiers.writeCharacteristicUuid,
      );
      expect(
        transport.sentMessages.single.payload,
        orderedEquals(<int>[0x7e, 0x07, 0x05, 0x03, 1, 2, 3, 0x10, 0xef]),
      );
      expect(device.lastKnownState!.color, RgbColor(1, 2, 3));
      await device.close();
      await transport.dispose();
    },
  );

  test(
    'suppresses duplicate and sub-delta Lotus lighting frames per session',
    () async {
      final transport = _RecordingTransportSession();
      final adapter = LotusLampXProtocolAdapter(allowUnverifiedCommands: true);
      final device = await adapter.openSession(
        transport,
        const ProtocolProbeResult(status: ProtocolProbeStatus.unverified),
      );

      expect(device.commandDelta, LotusLampXProtocolAdapter.commandDelta);
      expect(
        (await device.execute(SetBrightness(0.5))).outcome,
        CommandOutcome.transmitted,
      );
      expect(
        (await device.execute(SetBrightness(0.5 + 1 / 255))).outcome,
        CommandOutcome.deduplicated,
      );
      expect(transport.sentMessages, hasLength(1));

      expect(
        (await device.execute(SetBrightness(0.5 + 3 / 255))).outcome,
        CommandOutcome.transmitted,
      );
      expect(transport.sentMessages, hasLength(2));

      expect(
        (await device.execute(SetColor(RgbColor(100, 120, 140)))).outcome,
        CommandOutcome.transmitted,
      );
      expect(
        (await device.execute(SetColor(RgbColor(102, 122, 142)))).outcome,
        CommandOutcome.deduplicated,
      );
      expect(
        (await device.execute(SetColor(RgbColor(103, 123, 143)))).outcome,
        CommandOutcome.transmitted,
      );
      expect(transport.sentMessages, hasLength(4));

      await device.close();
      await transport.dispose();
    },
  );

  test('encodes black ApplyLightingState as a black RGB frame', () async {
    final transport = _RecordingTransportSession();
    final adapter = LotusLampXProtocolAdapter(allowUnverifiedCommands: true);
    final device = await adapter.openSession(
      transport,
      const ProtocolProbeResult(status: ProtocolProbeStatus.unverified),
    );

    final result = await device.execute(
      ApplyLightingState(DesiredLightingState(color: RgbColor(0, 0, 0))),
    );

    expect(result.outcome, CommandOutcome.transmitted);
    expect(
      transport.sentMessages.single.payload,
      orderedEquals(LotusLampXFrameCodec.color(0, 0, 0)),
    );
    await device.close();
    await transport.dispose();
  });

  test(
    'requests the declared FFF4 channel and emits a decoded observation',
    () async {
      final transport = _RecordingTransportSession()
        ..readResponse = TransportMessage(
          LotusLampXFrameCodec.brightness(128),
          channel: LotusLampXBleIdentifiers.notifyCharacteristicUuid,
        );
      final adapter = LotusLampXProtocolAdapter();
      final device = await adapter.openSession(
        transport,
        const ProtocolProbeResult(status: ProtocolProbeStatus.unverified),
      );
      final observation = device.observations.first;

      await device.requestCurrentState();

      expect(
        transport.lastReadChannel,
        LotusLampXBleIdentifiers.notifyCharacteristicUuid,
      );
      expect((await observation).state!.brightness, closeTo(128 / 255, 0.0001));
      await device.close();
      await transport.dispose();
    },
  );
}

class _RecordingTransportSession implements TransportSession {
  _RecordingTransportSession()
    : endpoint = TransportEndpoint(
        id: 'test-elk',
        transport: TransportKind.ble,
        displayName: 'ELK-BLEDDM',
      );

  @override
  final TransportEndpoint endpoint;
  final List<TransportMessage> sentMessages = <TransportMessage>[];
  TransportMessage? readResponse;
  String? lastReadChannel;

  @override
  Stream<TransportSessionEvent> get events =>
      Stream<TransportSessionEvent>.empty();

  @override
  Stream<TransportMessage> get incomingMessages =>
      Stream<TransportMessage>.empty();

  @override
  Future<void> disconnect() async {}

  @override
  Future<TransportReceipt> send(TransportMessage message) async {
    sentMessages.add(message);
    return const TransportReceipt(status: TransportDeliveryStatus.transmitted);
  }

  @override
  Future<TransportMessage?> read(String channel) async {
    lastReadChannel = channel;
    return readResponse;
  }

  Future<void> dispose() => disconnect();
}
