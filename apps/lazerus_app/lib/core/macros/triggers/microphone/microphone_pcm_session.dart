import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Fixed capture format accepted by the microphone macro trigger.
///
/// The source deliberately streams PCM only. It never receives a path and
/// therefore cannot persist captured audio.
final class MicrophonePcmFormat {
  const MicrophonePcmFormat({this.sampleRateHz = 44100, this.channels = 1})
    : assert(sampleRateHz > 0),
      assert(channels == 1);

  final int sampleRateHz;
  final int channels;
}

enum MicrophoneCaptureState {
  idle,
  requestingPermission,
  starting,
  streaming,
  stopping,
  stopped,
  permissionDenied,
  error,
  disposed,
}

/// Observable session state for UI diagnostics and recovery affordances.
final class MicrophoneCaptureStatus {
  const MicrophoneCaptureStatus(this.state, {this.error, this.stackTrace});

  final MicrophoneCaptureState state;
  final Object? error;
  final StackTrace? stackTrace;
}

final class MicrophonePermissionDeniedException implements Exception {
  const MicrophonePermissionDeniedException();

  @override
  String toString() => 'Microphone permission was denied.';
}

/// Narrow, raw-audio-only boundary used by the macro trigger.
///
/// A session has one explicit owner. Callers must stop or dispose it when the
/// graph stops; no bytes are written to disk by this abstraction.
abstract interface class MicrophonePcmSession {
  MicrophonePcmFormat get format;
  Stream<Uint8List> get pcm16leFrames;
  Stream<MicrophoneCaptureStatus> get statuses;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// [record]-backed live microphone capture using PCM16, mono input.
final class RecordMicrophonePcmSession implements MicrophonePcmSession {
  RecordMicrophonePcmSession({
    AudioRecorder? recorder,
    this.format = const MicrophonePcmFormat(),
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  final MicrophonePcmFormat format;

  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<MicrophoneCaptureStatus> _statuses =
      StreamController<MicrophoneCaptureStatus>.broadcast(sync: true);

  StreamSubscription<Uint8List>? _captureSubscription;
  Future<void> _operation = Future<void>.value();
  MicrophoneCaptureState _state = MicrophoneCaptureState.idle;
  bool _isDisposed = false;

  @override
  Stream<Uint8List> get pcm16leFrames => _frames.stream;

  @override
  Stream<MicrophoneCaptureStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() => _serialize(() async {
    _throwIfDisposed();
    if (_state == MicrophoneCaptureState.streaming ||
        _state == MicrophoneCaptureState.starting) {
      return;
    }

    _report(MicrophoneCaptureState.requestingPermission);
    try {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        const error = MicrophonePermissionDeniedException();
        _report(MicrophoneCaptureState.permissionDenied, error: error);
        throw error;
      }

      _report(MicrophoneCaptureState.starting);
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: format.sampleRateHz,
          numChannels: format.channels,
        ),
      );
      _captureSubscription = stream.listen(
        _frames.add,
        onError: _onCaptureError,
        onDone: _onCaptureDone,
        cancelOnError: false,
      );
      _report(MicrophoneCaptureState.streaming);
    } catch (error, stackTrace) {
      if (error is! MicrophonePermissionDeniedException) {
        _report(
          MicrophoneCaptureState.error,
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  });

  @override
  Future<void> stop() => _serialize(_stopUnsafe);

  @override
  Future<void> dispose() => _serialize(() async {
    if (_isDisposed) return;
    await _stopUnsafe();
    _isDisposed = true;
    try {
      await _recorder.dispose();
    } catch (error, stackTrace) {
      _report(
        MicrophoneCaptureState.error,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _report(MicrophoneCaptureState.disposed);
      await _frames.close();
      await _statuses.close();
    }
  });

  Future<void> _stopUnsafe() async {
    if (_state == MicrophoneCaptureState.idle ||
        _state == MicrophoneCaptureState.stopped ||
        _state == MicrophoneCaptureState.disposed) {
      return;
    }
    if (_state == MicrophoneCaptureState.permissionDenied) {
      _report(MicrophoneCaptureState.stopped);
      return;
    }
    _report(MicrophoneCaptureState.stopping);
    try {
      await _captureSubscription?.cancel();
      _captureSubscription = null;
      await _recorder.stop();
      _report(MicrophoneCaptureState.stopped);
    } catch (error, stackTrace) {
      _report(
        MicrophoneCaptureState.error,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _onCaptureError(Object error, StackTrace stackTrace) {
    _report(MicrophoneCaptureState.error, error: error, stackTrace: stackTrace);
  }

  void _onCaptureDone() {
    if (!_isDisposed && _state == MicrophoneCaptureState.streaming) {
      _report(MicrophoneCaptureState.stopped);
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _operation.then<void>(
      (_) => action(),
      onError: (_) => action(),
    );
    _operation = next.catchError((Object _) {});
    return next;
  }

  void _report(
    MicrophoneCaptureState state, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _state = state;
    if (!_statuses.isClosed) {
      _statuses.add(
        MicrophoneCaptureStatus(state, error: error, stackTrace: stackTrace),
      );
    }
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError('The microphone session has been disposed.');
    }
  }
}
