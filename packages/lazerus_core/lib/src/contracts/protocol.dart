import 'transport.dart';
import '../model/lighting.dart';

enum ProtocolMatchKind { noMatch, candidate, matched }

/// A non-invasive classification result for a discovered endpoint.
class ProtocolMatch {
  const ProtocolMatch({
    required this.kind,
    required this.confidence,
    required this.requiresProbe,
    this.reason,
  }) : assert(confidence >= 0 && confidence <= 100);

  const ProtocolMatch.noMatch({this.reason})
    : kind = ProtocolMatchKind.noMatch,
      confidence = 0,
      requiresProbe = false;

  final ProtocolMatchKind kind;
  final int confidence;
  final bool requiresProbe;
  final String? reason;

  bool get isMatch => kind != ProtocolMatchKind.noMatch;
}

/// Adapter-provided filters combined by the discovery coordinator.
class ProtocolDiscoverySpec {
  ProtocolDiscoverySpec({
    required this.transport,
    Set<String> serviceIds = const <String>{},
    Set<String> namePrefixes = const <String>{},
    this.safeProbeAvailable = false,
  }) : serviceIds = Set.unmodifiable(
         serviceIds.map((serviceId) => serviceId.toLowerCase()),
       ),
       namePrefixes = Set.unmodifiable(
         namePrefixes.map((prefix) => prefix.toLowerCase()),
       );

  final TransportKind transport;
  final Set<String> serviceIds;
  final Set<String> namePrefixes;
  final bool safeProbeAvailable;
}

enum ProtocolProbeStatus { supported, unverified, unsupported, failed }

class ProtocolProbeOptions {
  const ProtocolProbeOptions({
    this.timeout = const Duration(seconds: 5),
    this.allowActiveProbe = false,
  });

  final Duration timeout;

  /// Must be explicitly enabled before a probe can write to an unknown device.
  final bool allowActiveProbe;
}

class ProtocolProbeResult {
  const ProtocolProbeResult({
    required this.status,
    this.capabilities,
    this.reason,
    this.error,
  });

  final ProtocolProbeStatus status;
  final DeviceCapabilities? capabilities;
  final String? reason;
  final Object? error;
}

/// A device-family codec and session factory independent of a UI or transport.
abstract interface class LightingProtocolAdapter {
  String get id;
  int get selectionPriority;
  Set<TransportKind> get supportedTransports;

  ProtocolDiscoverySpec discoverySpecFor(TransportKind transport);
  ProtocolMatch match(TransportEndpoint endpoint);
  Future<ProtocolProbeResult> probe(
    TransportSession session,
    ProtocolProbeOptions options,
  );
  Future<LightingDeviceSession> openSession(
    TransportSession transportSession,
    ProtocolProbeResult probe,
  );
}

/// A connected, protocol-aware endpoint that accepts common lighting commands.
abstract interface class LightingDeviceSession {
  String get protocolAdapterId;
  DeviceCapabilities get capabilities;
  Stream<DeviceObservation> get observations;

  Future<CommandResult> execute(LightingCommand command);
  Future<void> close();
}

class ProtocolCandidate {
  const ProtocolCandidate({required this.adapter, required this.match});

  final LightingProtocolAdapter adapter;
  final ProtocolMatch match;
}

class ProtocolSelection {
  const ProtocolSelection._(this.candidates, this.isAmbiguous);

  factory ProtocolSelection.empty() {
    return const ProtocolSelection._(<ProtocolCandidate>[], false);
  }

  final List<ProtocolCandidate> candidates;
  final bool isAmbiguous;

  ProtocolCandidate? get selected =>
      candidates.isEmpty ? null : candidates.first;
}

/// Sorts matching adapters deterministically without embedding brand logic.
class ProtocolAdapterRegistry {
  ProtocolAdapterRegistry(Iterable<LightingProtocolAdapter> adapters)
    : _adapters = List.unmodifiable(adapters) {
    final ids = _adapters.map((adapter) => adapter.id).toSet();
    if (ids.length != _adapters.length) {
      throw ArgumentError.value(
        adapters,
        'adapters',
        'Adapter IDs must be unique.',
      );
    }
  }

  final List<LightingProtocolAdapter> _adapters;

  List<LightingProtocolAdapter> get adapters => _adapters;

  ProtocolSelection select(TransportEndpoint endpoint) {
    final candidates = <ProtocolCandidate>[];
    for (final adapter in _adapters) {
      if (!adapter.supportedTransports.contains(endpoint.transport)) {
        continue;
      }

      final match = adapter.match(endpoint);
      if (match.isMatch) {
        candidates.add(ProtocolCandidate(adapter: adapter, match: match));
      }
    }

    candidates.sort((left, right) {
      final confidence = right.match.confidence.compareTo(
        left.match.confidence,
      );
      if (confidence != 0) {
        return confidence;
      }

      final priority = right.adapter.selectionPriority.compareTo(
        left.adapter.selectionPriority,
      );
      if (priority != 0) {
        return priority;
      }

      return left.adapter.id.compareTo(right.adapter.id);
    });

    final isAmbiguous =
        candidates.length > 1 &&
        candidates[0].match.confidence == candidates[1].match.confidence &&
        candidates[0].adapter.selectionPriority ==
            candidates[1].adapter.selectionPriority;

    return ProtocolSelection._(List.unmodifiable(candidates), isAmbiguous);
  }
}
