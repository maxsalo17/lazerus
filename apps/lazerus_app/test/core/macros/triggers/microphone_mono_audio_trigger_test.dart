import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/triggers/microphone/microphone_mono_audio_trigger.dart';
import 'package:lazerus_app/core/macros/triggers/microphone/microphone_pcm_session.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test('microphone PCM frame becomes its declared mono-audio output', () async {
    final session = _FakeMicrophoneSession();
    final factory = MicrophoneMonoAudioTriggerFactory(
      createSession: () => session,
    );
    final node = MacroNode(
      id: 'microphone',
      kind: factory.kind,
      ports: factory.portsFor(
        MacroNode(
          id: 'microphone',
          kind: factory.kind,
          ports: const <MacroPortDeclaration>[],
        ),
      ),
    );
    final emitted = <TriggerEvent>[];
    final instance = factory.create(node);
    instance.start(_RecordingEmitter(emitted));

    session.add(Uint8List.fromList(<int>[0x00, 0x80, 0xff, 0x7f]));

    expect(emitted, hasLength(1));
    expect(emitted.single.sourcePortId, factory.outputPortId(node));
    final value = emitted.single.primaryValue as TriggerMonoAudioValue;
    expect(value.sampleRateHz, 8000);
    expect(value.values, <double>[-1, 32767 / 32768]);

    instance.stop();
    await session.disposed;
  });
}

final class _RecordingEmitter implements MacroRuntimeEventEmitter {
  _RecordingEmitter(this.events);

  final List<TriggerEvent> events;

  @override
  void emit(TriggerEvent event) => events.add(event);
}

final class _FakeMicrophoneSession implements MicrophonePcmSession {
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<MicrophoneCaptureStatus> _statuses =
      StreamController<MicrophoneCaptureStatus>.broadcast(sync: true);
  final Completer<void> _disposed = Completer<void>();

  @override
  MicrophonePcmFormat get format =>
      const MicrophonePcmFormat(sampleRateHz: 8000);

  @override
  Stream<Uint8List> get pcm16leFrames => _frames.stream;

  @override
  Stream<MicrophoneCaptureStatus> get statuses => _statuses.stream;

  void add(Uint8List frame) => _frames.add(frame);

  Future<void> get disposed => _disposed.future;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _frames.close();
    await _statuses.close();
    if (!_disposed.isCompleted) {
      _disposed.complete();
    }
  }
}
