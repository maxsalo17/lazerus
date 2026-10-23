import 'package:flutter_test/flutter_test.dart';

import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'selects the highest-confidence compatible protocol deterministically',
    () {
      final registry = ProtocolAdapterRegistry(<LightingProtocolAdapter>[
        _FakeAdapter(id: 'second', confidence: 80, selectionPriority: 0),
        _FakeAdapter(id: 'first', confidence: 80, selectionPriority: 1),
      ]);

      final selection = registry.select(
        TransportEndpoint(id: 'endpoint-1', transport: TransportKind.ble),
      );

      expect(selection.selected?.adapter.id, 'first');
      expect(selection.isAmbiguous, isFalse);
    },
  );

  test(
    'does not treat inferred capabilities as ordinary supported controls',
    () {
      final capabilities = DeviceCapabilities(
        features: <LightingFeature, FeatureCapability>{
          LightingFeature.rgb: FeatureCapability(
            availability: CapabilityAvailability.inferred,
          ),
        },
      );

      expect(capabilities.supports(LightingFeature.rgb), isFalse);
      expect(
        capabilities.supports(LightingFeature.rgb, allowInferred: true),
        isTrue,
      );
    },
  );

  test('rejects invalid shared lighting values outside normalized ranges', () {
    expect(() => RgbColor(-1, 0, 0), throwsRangeError);
    expect(() => SetBrightness(1.01), throwsArgumentError);
  });
}

class _FakeAdapter implements LightingProtocolAdapter {
  _FakeAdapter({
    required this.id,
    required this.confidence,
    required this.selectionPriority,
  });

  @override
  final String id;
  final int confidence;

  @override
  final int selectionPriority;

  @override
  Set<TransportKind> get supportedTransports => <TransportKind>{
    TransportKind.ble,
  };

  @override
  ProtocolDiscoverySpec discoverySpecFor(TransportKind transport) {
    return ProtocolDiscoverySpec(transport: transport);
  }

  @override
  ProtocolMatch match(TransportEndpoint endpoint) {
    return ProtocolMatch(
      kind: ProtocolMatchKind.matched,
      confidence: confidence,
      requiresProbe: false,
    );
  }

  @override
  Future<LightingDeviceSession> openSession(
    TransportSession transportSession,
    ProtocolProbeResult probe,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ProtocolProbeResult> probe(
    TransportSession session,
    ProtocolProbeOptions options,
  ) {
    throw UnimplementedError();
  }
}
