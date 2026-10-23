import 'dart:async';

/// Emits only the latest replaceable value at a bounded rate.
///
/// A new value received during an in-flight emission supersedes any older
/// pending value. This gives sliders responsive live feedback without building
/// an unbounded BLE command backlog.
class ReplaceableCommandTicker<T> {
  ReplaceableCommandTicker({
    required Future<void> Function(T value) onEmit,
    this.interval = const Duration(milliseconds: 100),
  }) : _onEmit = onEmit;

  final Future<void> Function(T value) _onEmit;
  final Duration interval;

  Timer? _timer;
  T? _pending;
  var _hasPending = false;
  var _isEmitting = false;
  var _isDisposed = false;
  Completer<void>? _inFlight;

  void push(T value) {
    if (_isDisposed) {
      return;
    }
    _pending = value;
    _hasPending = true;
    _schedule();
  }

  /// Sends the last value immediately after any in-flight write completes.
  Future<void> flush() async {
    if (_isDisposed) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    while (!_isDisposed && (_isEmitting || _hasPending)) {
      if (_isEmitting) {
        await _inFlight?.future;
      } else {
        await _emitLatest();
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _hasPending = false;
  }

  void _schedule() {
    if (_timer != null || _isEmitting || !_hasPending) {
      return;
    }
    _timer = Timer(interval, () {
      _timer = null;
      unawaited(_emitLatest());
    });
  }

  Future<void> _emitLatest() async {
    if (_isDisposed || _isEmitting || !_hasPending) {
      return;
    }
    final value = _pending as T;
    _pending = null;
    _hasPending = false;
    _isEmitting = true;
    final inFlight = Completer<void>();
    _inFlight = inFlight;
    try {
      await _onEmit(value);
    } catch (_) {
      // Transport failures are represented in device state by the dispatcher.
      // A future value must still be allowed to replace this failed emission.
    } finally {
      _isEmitting = false;
      if (!inFlight.isCompleted) {
        inFlight.complete();
      }
      _inFlight = null;
      _schedule();
    }
  }
}
