import 'dart:async';
import 'dart:typed_data';

import 'package:lazerus_core/lazerus_core.dart';

import 'microphone_pcm_session.dart';

/// Creates the live microphone source module for macro graphs.
///
/// This trigger deliberately has no dependency on audio analysis or EQ. It
/// emits each transient PCM frame as [TriggerMonoAudioValue].
final class MicrophoneMonoAudioTriggerFactory
    implements
        MacroModuleFactory,
        MacroNodePortContractProvider,
        MacroTriggerDefinition {
  MicrophoneMonoAudioTriggerFactory({
    MicrophonePcmSession Function()? createSession,
  }) : _createSession = createSession ?? RecordMicrophonePcmSession.new;

  static const String moduleKind = 'trigger.microphone.mono_audio';
  static const String audioPortId = 'audio';

  final MicrophonePcmSession Function() _createSession;
  final StreamController<MicrophoneCaptureStatus> _statuses =
      StreamController<MicrophoneCaptureStatus>.broadcast(sync: true);

  /// Permission and capture state for instances created by this factory.
  ///
  /// The application composition root owns and disposes the factory. Widgets
  /// can observe this stream through a controller without owning audio I/O.
  Stream<MicrophoneCaptureStatus> get statuses => _statuses.stream;

  @override
  String get kind => moduleKind;

  @override
  String get displayName => 'Microphone';

  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: audioPortId,
      direction: MacroPortDirection.output,
      type: MacroPortType.triggerMonoAudio,
      displayIdentifier: 'microphone.audio',
      displayName: 'Microphone audio',
    ),
  ];

  /// Keeps every microphone instance addressable in the graph. The static
  /// [ports] list remains only as a backwards-compatible registry fallback.
  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: outputPortId(node),
      direction: MacroPortDirection.output,
      type: MacroPortType.triggerMonoAudio,
      displayIdentifier: 'microphone.audio',
      displayName: 'Microphone audio',
    ),
  ];

  String outputPortId(MacroNode node) => '${node.id}.audio';

  @override
  MacroModuleInstance create(MacroNode node) {
    final session = _createSession();
    return _MicrophoneMonoAudioTrigger(
      outputPortId: outputPortId(node),
      session: session,
      reportStatus: _reportStatus,
    );
  }

  Future<void> dispose() => _statuses.close();

  void _reportStatus(MicrophoneCaptureStatus status) {
    if (!_statuses.isClosed) {
      _statuses.add(status);
    }
  }
}

final class _MicrophoneMonoAudioTrigger implements MacroModuleInstance {
  _MicrophoneMonoAudioTrigger({
    required this.outputPortId,
    required this.session,
    required this.reportStatus,
  });

  final String outputPortId;
  final MicrophonePcmSession session;
  final void Function(MicrophoneCaptureStatus status) reportStatus;
  StreamSubscription<Uint8List>? _frameSubscription;
  StreamSubscription<MicrophoneCaptureStatus>? _statusSubscription;
  Stopwatch? _clock;
  MacroRuntimeEventEmitter? _emitter;
  var _sequence = 0;
  var _released = false;

  @override
  void start(MacroRuntimeEventEmitter emitter) {
    if (_released) return;
    _emitter = emitter;
    _clock = Stopwatch()..start();
    _frameSubscription = session.pcm16leFrames.listen(_emitFrame);
    _statusSubscription = session.statuses.listen(reportStatus);
    unawaited(_startSession());
  }

  Future<void> _startSession() async {
    try {
      await session.start();
    } catch (_) {
      // Session status exposes permission and platform errors to the feature
      // layer; runtime event routing remains intentionally data-only.
    }
  }

  void _emitFrame(Uint8List bytes) {
    final emitter = _emitter;
    final clock = _clock;
    if (_released || emitter == null || clock == null) return;
    final samples = decodePcm16LittleEndian(bytes);
    if (samples.isEmpty) return;
    emitter.emit(
      TriggerEvent(
        sourcePortId: outputPortId,
        timestamp: clock.elapsed,
        sequence: _sequence++,
        primaryValue: TriggerMonoAudioValue(
          values: samples,
          sampleRateHz: session.format.sampleRateHz,
        ),
      ),
    );
  }

  @override
  void onInput(String inputPortId, TriggerEvent event) {}

  @override
  void stop() {
    if (_released) return;
    _released = true;
    _clock?.stop();
    _emitter = null;
    unawaited(_release());
  }

  Future<void> _release() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    try {
      await session.stop();
    } finally {
      try {
        await session.dispose();
      } finally {
        await _statusSubscription?.cancel();
        _statusSubscription = null;
      }
    }
  }
}

/// Decodes signed little-endian PCM16 into normalized mono samples.
///
/// A trailing incomplete byte is ignored because it cannot be one PCM sample.
List<double> decodePcm16LittleEndian(Uint8List bytes) {
  final sampleCount = bytes.lengthInBytes ~/ 2;
  return List<double>.generate(sampleCount, (index) {
    final offset = index * 2;
    final unsigned = bytes[offset] | (bytes[offset + 1] << 8);
    final signed = unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
    return signed / 32768.0;
  }, growable: false);
}
