import 'dart:typed_data';

/// The physical or network path used to reach a device.
enum TransportKind { ble, usb, wifi, http, mqtt }

/// A discovered transport endpoint before its lighting protocol is known.
class TransportEndpoint {
  TransportEndpoint({
    required this.id,
    required this.transport,
    this.displayName,
    Set<String> advertisedServiceIds = const <String>{},
    Map<String, String> metadata = const <String, String>{},
  }) : advertisedServiceIds = Set.unmodifiable(advertisedServiceIds.map(_normalizeIdentifier)),
       metadata = Map.unmodifiable(metadata);

  /// An identifier meaningful only to the [transport] implementation.
  final String id;

  final TransportKind transport;
  final String? displayName;

  /// Transport metadata exposed before protocol classification.
  ///
  /// This is intentionally not an application device identity.
  final Map<String, String> metadata;

  /// BLE advertised service UUIDs when the transport can provide them.
  final Set<String> advertisedServiceIds;

  bool hasAdvertisedService(String serviceId) {
    return advertisedServiceIds.contains(_normalizeIdentifier(serviceId));
  }

  static String _normalizeIdentifier(String value) => value.toLowerCase();
}

/// Transport behavior that affects scheduling and lifecycle handling.
class TransportCapabilities {
  TransportCapabilities({
    Set<DiscoveryMode> discoveryModes = const <DiscoveryMode>{},
    this.supportsPersistentConnections = false,
    this.supportsBackgroundRestoration = false,
    this.supportsIncomingMessages = false,
    this.supportsReadRequests = false,
    this.supportsDeliveryAcknowledgements = false,
    this.maximumMessageSize,
  }) : discoveryModes = Set.unmodifiable(discoveryModes);

  final Set<DiscoveryMode> discoveryModes;
  final bool supportsPersistentConnections;
  final bool supportsBackgroundRestoration;
  final bool supportsIncomingMessages;
  final bool supportsReadRequests;
  final bool supportsDeliveryAcknowledgements;
  final int? maximumMessageSize;
}

enum DiscoveryMode { activeScan, passiveScan, enumeration, configuredTargets }

/// A request made by the discovery coordinator to one transport.
class DiscoveryRequest {
  DiscoveryRequest({
    this.timeout = const Duration(seconds: 10),
    Set<String> serviceIds = const <String>{},
    Set<String> namePrefixes = const <String>{},
    this.includeUnidentified = true,
  }) : serviceIds = Set.unmodifiable(serviceIds.map((serviceId) => serviceId.toLowerCase())),
       namePrefixes = Set.unmodifiable(namePrefixes.map((prefix) => prefix.toLowerCase()));

  final Duration timeout;
  final Set<String> serviceIds;
  final Set<String> namePrefixes;
  final bool includeUnidentified;
}

class ConnectionOptions {
  const ConnectionOptions({this.autoReconnect = false, this.timeout = const Duration(seconds: 15)});

  final bool autoReconnect;
  final Duration timeout;
}

sealed class TransportDiscoveryEvent {
  const TransportDiscoveryEvent();
}

final class TransportEndpointDiscovered extends TransportDiscoveryEvent {
  const TransportEndpointDiscovered(this.endpoint);

  final TransportEndpoint endpoint;
}

final class TransportDiscoveryError extends TransportDiscoveryEvent {
  const TransportDiscoveryError(this.error, {this.message});

  final Object error;
  final String? message;
}

final class TransportDiscoveryComplete extends TransportDiscoveryEvent {
  const TransportDiscoveryComplete();
}

enum TransportSessionEventType { connected, disconnected, reconnecting, error }

class TransportSessionEvent {
  TransportSessionEvent({required this.type, DateTime? occurredAt, this.message, this.error})
    : occurredAt = occurredAt ?? DateTime.now().toUtc();

  final TransportSessionEventType type;
  final DateTime occurredAt;
  final String? message;
  final Object? error;
}

/// A protocol message moving through a selected transport session.
class TransportMessage {
  TransportMessage(Uint8List payload, {this.channel, Map<String, String> metadata = const <String, String>{}})
    : payload = Uint8List.fromList(payload),
      metadata = Map.unmodifiable(metadata);

  final Uint8List payload;

  /// A transport-specific destination, such as a BLE characteristic UUID.
  final String? channel;
  final Map<String, String> metadata;
}

enum TransportDeliveryStatus { accepted, transmitted, acknowledged, failed }

/// The result of moving a message over the transport, not device confirmation.
class TransportReceipt {
  const TransportReceipt({required this.status, this.detail});

  final TransportDeliveryStatus status;
  final String? detail;
}

/// Discovers endpoints and creates transport sessions.
abstract interface class DeviceTransport {
  TransportKind get kind;
  TransportCapabilities get capabilities;

  Stream<TransportDiscoveryEvent> discover(DiscoveryRequest request);
  Future<TransportSession> connect(TransportEndpoint endpoint, ConnectionOptions options);
}

/// A connected, transport-level channel to a single endpoint.
abstract interface class TransportSession {
  TransportEndpoint get endpoint;
  Stream<TransportSessionEvent> get events;
  Stream<TransportMessage> get incomingMessages;

  Future<TransportReceipt> send(TransportMessage message);

  /// Reads a declared protocol channel when the underlying transport supports
  /// it. A `null` result means that the channel is unavailable or not readable.
  /// Protocol adapters, not widgets, decide which channels are safe to read.
  Future<TransportMessage?> read(String channel);
  Future<void> disconnect();
}
