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

  Future<void> dispose() => disconnect();
}
