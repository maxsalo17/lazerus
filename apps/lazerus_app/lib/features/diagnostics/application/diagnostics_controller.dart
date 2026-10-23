import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../domain/diagnostic_log_entry.dart';

final diagnosticsProvider =
    NotifierProvider<DiagnosticsController, DiagnosticsLogState>(
      DiagnosticsController.new,
    );

class DiagnosticsLogState {
  const DiagnosticsLogState({this.entries = const <DiagnosticLogEntry>[]});

  final List<DiagnosticLogEntry> entries;
}

class DiagnosticsController extends Notifier<DiagnosticsLogState> {
  static const _maximumEntries = 400;
  var _nextId = 0;

  @override
  DiagnosticsLogState build() => const DiagnosticsLogState();

  void info(String message, {String? deviceId, String? deviceName}) => _record(
    DiagnosticLogLevel.info,
    message,
    deviceId: deviceId,
    deviceName: deviceName,
  );

  void warning(String message, {String? deviceId, String? deviceName}) =>
      _record(
        DiagnosticLogLevel.warning,
        message,
        deviceId: deviceId,
        deviceName: deviceName,
      );

  void error(String message, {String? deviceId, String? deviceName}) => _record(
    DiagnosticLogLevel.error,
    message,
    deviceId: deviceId,
    deviceName: deviceName,
  );

  void received(
    String message, {
    String? deviceId,
    String? deviceName,
    Uint8List? rawData,
    DesiredLightingState? observedState,
  }) => _record(
    DiagnosticLogLevel.received,
    message,
    deviceId: deviceId,
    deviceName: deviceName,
    rawData: rawData,
    observedState: observedState,
  );

  void clear() {
    state = const DiagnosticsLogState();
  }

  void _record(
    DiagnosticLogLevel level,
    String message, {
    String? deviceId,
    String? deviceName,
    Uint8List? rawData,
    DesiredLightingState? observedState,
  }) {
    final entry = DiagnosticLogEntry(
      id: ++_nextId,
      level: level,
      message: message,
      deviceId: deviceId,
      deviceName: deviceName,
      rawData: rawData,
      observedState: observedState,
    );
    final entries = <DiagnosticLogEntry>[entry, ...state.entries];
    if (entries.length > _maximumEntries) {
      entries.removeRange(_maximumEntries, entries.length);
    }
    state = DiagnosticsLogState(entries: List.unmodifiable(entries));
  }
}
