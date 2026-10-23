import 'dart:typed_data';

import 'package:lazerus_core/lazerus_core.dart';

enum DiagnosticLogLevel { info, warning, error, received }

/// A bounded, in-memory record for inspecting local transport behavior.
///
/// It intentionally keeps raw packets local to this app session. It is a
/// troubleshooting aid, not a durable device-history database.
class DiagnosticLogEntry {
  DiagnosticLogEntry({
    required this.id,
    required this.level,
    required this.message,
    DateTime? occurredAt,
    this.deviceId,
    this.deviceName,
    Uint8List? rawData,
    this.observedState,
  }) : occurredAt = occurredAt ?? DateTime.now().toUtc(),
       rawData = rawData == null ? null : Uint8List.fromList(rawData);

  final int id;
  final DiagnosticLogLevel level;
  final String message;
  final DateTime occurredAt;
  final String? deviceId;
  final String? deviceName;
  final Uint8List? rawData;
  final DesiredLightingState? observedState;

  String get rawHex => rawData == null
      ? ''
      : rawData!
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ');
}
