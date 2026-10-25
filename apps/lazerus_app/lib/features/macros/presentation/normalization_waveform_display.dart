import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../../core/macros/modifiers/normalization/normalization_modifier.dart';

const normalizationWaveformDefaultDuration = Duration(seconds: 5);
const normalizationWaveformMinimumDuration = Duration(milliseconds: 50);
const normalizationWaveformMaximumDuration = Duration(seconds: 10);
// 50 ms increments across the full 50 ms..10 s selector range.
const normalizationWaveformSliderDivisions = 199;
const normalizationWaveformPresentationDelay = Duration(milliseconds: 100);
const normalizationWaveformMinimumAmplitudeWindowSamples = 50;
const normalizationWaveformDefaultAmplitudeWindowSamples = 1024;
const normalizationWaveformMaximumAmplitudeWindowSamples = 44000;

enum NormalizationWaveformViewMode { overlay, split }

/// A display-only point in a Normalization time-domain graph.
final class NormalizationWaveformPoint {
  const NormalizationWaveformPoint({
    required this.timestamp,
    required this.value,
  });

  final Duration timestamp;
  final double value;
}

/// Immutable, paint-safe sample of a bounded Normalization display buffer.
final class NormalizationWaveformSnapshot {
  NormalizationWaveformSnapshot({
    required this.outputMode,
    required this.duration,
    required this.latestTimestamp,
    required this.isReady,
    required Iterable<NormalizationWaveformPoint> input,
    required Iterable<NormalizationWaveformPoint> output,
  }) : input = List<NormalizationWaveformPoint>.unmodifiable(input),
       output = List<NormalizationWaveformPoint>.unmodifiable(output);

  final NormalizationOutputMode outputMode;
  final Duration duration;
  final Duration? latestTimestamp;
  final bool isReady;
  final List<NormalizationWaveformPoint> input;
  final List<NormalizationWaveformPoint> output;
}

/// Transient, strictly duration-bounded data for one Normalization graph.
///
/// PCM mode stores cropped PCM frames for each trace. Value mode stores only
/// frame-level points, so it never retains raw PCM merely for the graph.
final class NormalizationWaveformHistory {
  NormalizationWaveformHistory({
    required this.outputMode,
    Duration displayDuration = normalizationWaveformDefaultDuration,
    int amplitudeWindowSamples =
        normalizationWaveformDefaultAmplitudeWindowSamples,
  }) : _displayDuration = displayDuration,
       _amplitudeWindowSamples = amplitudeWindowSamples {
    _validateDuration(displayDuration);
    _validateAmplitudeWindowSamples(amplitudeWindowSamples);
  }

  final NormalizationOutputMode outputMode;
  final ListQueue<_PcmFrame> _inputPcm = ListQueue<_PcmFrame>();
  final ListQueue<_PcmFrame> _outputPcm = ListQueue<_PcmFrame>();
  final ListQueue<NormalizationWaveformPoint> _inputLevels =
      ListQueue<NormalizationWaveformPoint>();
  final ListQueue<NormalizationWaveformPoint> _outputLevels =
      ListQueue<NormalizationWaveformPoint>();
  Duration _displayDuration;
  int _amplitudeWindowSamples;
  Duration? _latestTimestamp;
  Duration? _latestDisplayEnd;
  var _nextInputSampleIndex = 0;
  var _nextOutputSampleIndex = 0;

  Duration get displayDuration => _displayDuration;
  int get amplitudeWindowSamples => _amplitudeWindowSamples;

  Duration get inputRetainedDuration =>
      outputMode == NormalizationOutputMode.pcm
      ? _pcmRetainedDuration(_inputPcm)
      : _pointRetainedDuration(_inputLevels);

  Duration get outputRetainedDuration =>
      outputMode == NormalizationOutputMode.pcm
      ? _pcmRetainedDuration(_outputPcm)
      : _pointRetainedDuration(_outputLevels);

  void setDisplayDuration(Duration duration) {
    _validateDuration(duration);
    _displayDuration = duration;
    _trim();
  }

  void setAmplitudeWindowSamples(int value) {
    _validateAmplitudeWindowSamples(value);
    _amplitudeWindowSamples = value;
  }

  bool addInput(TriggerEvent event) {
    final value = event.primaryValue;
    if (value is! TriggerMonoAudioValue) return false;
    _recordTimestamp(event.timestamp);
    switch (outputMode) {
      case NormalizationOutputMode.pcm:
        _inputPcm.addLast(
          _PcmFrame.fromAudio(
            event.timestamp,
            value,
            firstSampleIndex: _nextInputSampleIndex,
          ),
        );
        _nextInputSampleIndex += value.values.length;
        break;
      case NormalizationOutputMode.value:
        _inputLevels.addLast(
          NormalizationWaveformPoint(
            timestamp: event.timestamp,
            value: _inputLevel(value.values),
          ),
        );
        break;
    }
    _trim();
    return true;
  }

  bool addOutput(TriggerEvent event) {
    switch (outputMode) {
      case NormalizationOutputMode.pcm:
        final value = event.primaryValue;
        if (value is! TriggerMonoAudioValue) return false;
        _recordTimestamp(event.timestamp);
        _outputPcm.addLast(
          _PcmFrame.fromAudio(
            event.timestamp,
            value,
            firstSampleIndex: _nextOutputSampleIndex,
          ),
        );
        _nextOutputSampleIndex += value.values.length;
        break;
      case NormalizationOutputMode.value:
        final value = event.primaryValue;
        if (value is! TriggerLevelValue) return false;
        _recordTimestamp(event.timestamp);
        _outputLevels.addLast(
          NormalizationWaveformPoint(
            timestamp: event.timestamp,
            value: value.value,
          ),
        );
        break;
    }
    _trim();
    return true;
  }

  /// Returns the data visible at [displayEnd].
  ///
  /// The presentation ticker supplies a steadily advancing [displayEnd], even
  /// when the runtime has not emitted another frame. This makes the graph a
  /// live scrolling scope: a frame enters at the right edge and then travels
  /// left through an otherwise empty viewport.
  NormalizationWaveformSnapshot snapshot({Duration? displayEnd}) {
    if (displayEnd != null) {
      _latestDisplayEnd = _laterTimestamp(_latestDisplayEnd, displayEnd);
    }
    // The display may deliberately lag the runtime clock. Do not advance its
    // viewport to a newer input event: doing so reintroduces the empty right
    // edge the delay is meant to avoid.
    final latest = _latestDisplayEnd ?? _latestTimestamp;
    _trim(displayEnd: latest);
    return NormalizationWaveformSnapshot(
      outputMode: outputMode,
      duration: _displayDuration,
      latestTimestamp: latest,
      isReady: _isReady(latest),
      input: outputMode == NormalizationOutputMode.pcm
          ? _pcmPoints(_inputPcm, displayEnd: latest)
          : _visiblePoints(_inputLevels, displayEnd: latest),
      output: outputMode == NormalizationOutputMode.pcm
          ? _pcmPoints(_outputPcm, displayEnd: latest)
          : _visiblePoints(_outputLevels, displayEnd: latest),
    );
  }

  void clear() {
    _inputPcm.clear();
    _outputPcm.clear();
    _inputLevels.clear();
    _outputLevels.clear();
    _latestTimestamp = null;
    _latestDisplayEnd = null;
    _nextInputSampleIndex = 0;
    _nextOutputSampleIndex = 0;
  }

  void _recordTimestamp(Duration timestamp) {
    final latest = _latestTimestamp;
    if (latest == null || timestamp > latest) _latestTimestamp = timestamp;
  }

  void _trim({Duration? displayEnd}) {
    final latest = displayEnd ?? _latestDisplayEnd ?? _latestTimestamp;
    if (latest == null) return;
    final cutoff = latest > _displayDuration
        ? latest - _displayDuration
        : Duration.zero;
    _trimPcm(_inputPcm, cutoff);
    _trimPcm(_outputPcm, cutoff);
    _trimPoints(_inputLevels, cutoff);
    _trimPoints(_outputLevels, cutoff);
  }

  Duration? _laterTimestamp(Duration? first, Duration? second) {
    if (first == null) return second;
    if (second == null || first >= second) return first;
    return second;
  }

  void _trimPcm(ListQueue<_PcmFrame> frames, Duration cutoff) {
    while (frames.isNotEmpty && frames.first.end <= cutoff) {
      frames.removeFirst();
    }
    if (frames.isEmpty || frames.first.start >= cutoff) return;
    final cropped = frames.removeFirst().cropBefore(cutoff);
    if (cropped != null) frames.addFirst(cropped);
  }

  void _trimPoints(
    ListQueue<NormalizationWaveformPoint> points,
    Duration cutoff,
  ) {
    while (points.isNotEmpty && points.first.timestamp < cutoff) {
      points.removeFirst();
    }
  }

  bool _isReady(Duration? latest) {
    if (latest == null || latest < _displayDuration) return false;
    final cutoff = latest - _displayDuration;
    return switch (outputMode) {
      NormalizationOutputMode.pcm =>
        _inputPcm.isNotEmpty &&
            _outputPcm.isNotEmpty &&
            _inputPcm.first.start <= cutoff &&
            _outputPcm.first.start <= cutoff,
      NormalizationOutputMode.value =>
        _inputLevels.isNotEmpty &&
            _outputLevels.isNotEmpty &&
            _inputLevels.first.timestamp <= cutoff &&
            _outputLevels.first.timestamp <= cutoff,
    };
  }

  List<NormalizationWaveformPoint> _pcmPoints(
    ListQueue<_PcmFrame> frames, {
    required Duration? displayEnd,
  }) {
    final buckets = <int, _AmplitudeBucket>{};
    for (final frame in frames) {
      for (var index = 0; index < frame.samples.length; index++) {
        final timestamp = frame.timestampForSample(index);
        if (displayEnd != null && timestamp > displayEnd) continue;
        final bucketIndex =
            (frame.firstSampleIndex + index) ~/ _amplitudeWindowSamples;
        final amplitude = frame.samples[index].abs().clamp(0.0, 1.0).toDouble();
        final bucket = buckets.putIfAbsent(
          bucketIndex,
          () => _AmplitudeBucket(timestamp: timestamp),
        );
        bucket.add(amplitude, timestamp);
      }
    }
    return buckets.values
        .map(
          (bucket) => NormalizationWaveformPoint(
            timestamp: bucket.timestamp,
            value: bucket.maximumAmplitude,
          ),
        )
        .toList(growable: false);
  }

  Iterable<NormalizationWaveformPoint> _visiblePoints(
    Iterable<NormalizationWaveformPoint> points, {
    required Duration? displayEnd,
  }) => displayEnd == null
      ? points
      : points.where((point) => point.timestamp <= displayEnd);

  Duration _pcmRetainedDuration(ListQueue<_PcmFrame> frames) {
    if (frames.isEmpty) return Duration.zero;
    final duration = frames.last.end - frames.first.start;
    return duration.isNegative ? Duration.zero : duration;
  }

  Duration _pointRetainedDuration(
    ListQueue<NormalizationWaveformPoint> points,
  ) {
    if (points.length < 2) return Duration.zero;
    return points.last.timestamp - points.first.timestamp;
  }
}

void _validateDuration(Duration value) {
  if (value < normalizationWaveformMinimumDuration ||
      value > normalizationWaveformMaximumDuration) {
    throw ArgumentError.value(
      value,
      'displayDuration',
      'Must be between ${normalizationWaveformMinimumDuration.inMilliseconds} '
          'and ${normalizationWaveformMaximumDuration.inMilliseconds} ms.',
    );
  }
}

void _validateAmplitudeWindowSamples(int value) {
  if (value < normalizationWaveformMinimumAmplitudeWindowSamples ||
      value > normalizationWaveformMaximumAmplitudeWindowSamples) {
    throw ArgumentError.value(
      value,
      'amplitudeWindowSamples',
      'Must be between $normalizationWaveformMinimumAmplitudeWindowSamples '
          'and $normalizationWaveformMaximumAmplitudeWindowSamples.',
    );
  }
}

double _inputLevel(List<double> samples) {
  if (samples.isEmpty) return 0;
  var sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }
  final rms = math.sqrt(sumSquares / samples.length);
  if (rms <= 0) return 0;
  final dbfs = (20 * math.log(rms) / math.ln10).clamp(-72.0, 0.0);
  return ((dbfs + 72) / 72).toDouble();
}

final class _PcmFrame {
  _PcmFrame({
    required this.start,
    required this.end,
    required this.sampleRateHz,
    required this.firstSampleIndex,
    required this.samples,
  });

  factory _PcmFrame.fromAudio(
    Duration end,
    TriggerMonoAudioValue audio, {
    required int firstSampleIndex,
  }) {
    final duration = Duration(
      microseconds:
          (audio.values.length *
                  Duration.microsecondsPerSecond /
                  audio.sampleRateHz)
              .round(),
    );
    return _PcmFrame(
      // The runtime event is the end of the captured frame. Keeping its true
      // (possibly negative-at-startup) start lets [_trimPcm] crop away every
      // sample outside the visible horizon instead of retaining a full frame.
      start: end - duration,
      end: end,
      sampleRateHz: audio.sampleRateHz,
      firstSampleIndex: firstSampleIndex,
      samples: audio.values,
    );
  }

  final Duration start;
  final Duration end;
  final int sampleRateHz;
  final int firstSampleIndex;
  final List<double> samples;

  _PcmFrame? cropBefore(Duration cutoff) {
    if (cutoff <= start) return this;
    final elapsedMicroseconds = (cutoff - start).inMicroseconds;
    final discardCount =
        (elapsedMicroseconds * sampleRateHz / Duration.microsecondsPerSecond)
            .ceil()
            .clamp(0, samples.length);
    if (discardCount >= samples.length) return null;
    final nextStart =
        start +
        Duration(
          microseconds:
              (discardCount * Duration.microsecondsPerSecond / sampleRateHz)
                  .round(),
        );
    return _PcmFrame(
      start: nextStart,
      end: end,
      sampleRateHz: sampleRateHz,
      firstSampleIndex: firstSampleIndex + discardCount,
      samples: List<double>.unmodifiable(samples.sublist(discardCount)),
    );
  }

  Duration timestampForSample(int index) =>
      start +
      Duration(
        microseconds: (index * Duration.microsecondsPerSecond / sampleRateHz)
            .round(),
      );
}

final class _AmplitudeBucket {
  _AmplitudeBucket({required this.timestamp});

  Duration timestamp;
  var maximumAmplitude = 0.0;

  void add(double amplitude, Duration nextTimestamp) {
    if (amplitude > maximumAmplitude) maximumAmplitude = amplitude;
    timestamp = nextTimestamp;
  }
}

/// VSync-coalesced Normalization graph with a transient display-only buffer.
class NormalizationWaveformDisplay extends StatefulWidget {
  NormalizationWaveformDisplay({
    super.key,
    required this.outputMode,
    required Iterable<String> inputSourcePortIds,
    required this.outputPortId,
    this.runtimeFrames,
  }) : inputSourcePortIds = Set<String>.unmodifiable(inputSourcePortIds);

  final NormalizationOutputMode outputMode;
  final Set<String> inputSourcePortIds;
  final String outputPortId;
  final Stream<Object>? runtimeFrames;

  @override
  State<NormalizationWaveformDisplay> createState() =>
      _NormalizationWaveformDisplayState();
}

class _NormalizationWaveformDisplayState
    extends State<NormalizationWaveformDisplay>
    with SingleTickerProviderStateMixin {
  late NormalizationWaveformHistory _history;
  late NormalizationWaveformSnapshot _snapshot;
  late final Ticker _ticker;
  StreamSubscription<Object>? _subscription;
  Duration? _runtimeTimestamp;
  Duration? _displayTimestamp;
  Duration? _previousTickElapsed;
  var _amplitudeWindowSamples =
      normalizationWaveformDefaultAmplitudeWindowSamples;
  var _viewMode = NormalizationWaveformViewMode.overlay;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _resetHistory();
    _bindRuntimeFrames(widget.runtimeFrames);
  }

  @override
  void didUpdateWidget(covariant NormalizationWaveformDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final portsChanged =
        oldWidget.outputPortId != widget.outputPortId ||
        !_samePorts(oldWidget.inputSourcePortIds, widget.inputSourcePortIds);
    final streamChanged = oldWidget.runtimeFrames != widget.runtimeFrames;
    if (oldWidget.outputMode != widget.outputMode ||
        portsChanged ||
        streamChanged) {
      _resetHistory();
    }
    if (streamChanged) {
      _bindRuntimeFrames(widget.runtimeFrames);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _ticker.dispose();
    _history.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durationMilliseconds = _history.displayDuration.inMilliseconds;
    return Semantics(
      label:
          'Live normalization waveform showing the last $durationMilliseconds milliseconds of audio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Waveform'),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              _WaveLegend(
                color: const Color(0xFF89B4FA),
                label: widget.outputMode == NormalizationOutputMode.pcm
                    ? 'Input amplitude'
                    : 'Input level',
              ),
              const SizedBox(width: 12),
              _WaveLegend(
                color: const Color(0xFFF9E2AF),
                label: widget.outputMode == NormalizationOutputMode.pcm
                    ? 'Normalized amplitude'
                    : 'Normalized value',
              ),
            ],
          ),
          RepaintBoundary(
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                children: <Widget>[
                  CustomPaint(
                    size: Size.infinite,
                    painter: _NormalizationWaveformPainter(
                      _snapshot,
                      viewMode: _viewMode,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: SegmentedButton<NormalizationWaveformViewMode>(
                      key: const Key('normalization-waveform-view-mode'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments:
                          const <ButtonSegment<NormalizationWaveformViewMode>>[
                            ButtonSegment<NormalizationWaveformViewMode>(
                              value: NormalizationWaveformViewMode.overlay,
                              label: Text('Overlay'),
                            ),
                            ButtonSegment<NormalizationWaveformViewMode>(
                              value: NormalizationWaveformViewMode.split,
                              label: Text('Split'),
                            ),
                          ],
                      selected: <NormalizationWaveformViewMode>{_viewMode},
                      onSelectionChanged:
                          (Set<NormalizationWaveformViewMode> selection) {
                            setState(() => _viewMode = selection.first);
                          },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: <Widget>[
              const Text('Display frame'),
              const Spacer(),
              Text('$durationMilliseconds ms'),
            ],
          ),
          Slider(
            key: const Key('normalization-waveform-duration-slider'),
            min: normalizationWaveformMinimumDuration.inMilliseconds.toDouble(),
            max: normalizationWaveformMaximumDuration.inMilliseconds.toDouble(),
            divisions: normalizationWaveformSliderDivisions,
            value: durationMilliseconds.toDouble(),
            label: '$durationMilliseconds ms',
            onChanged: _setDisplayDuration,
          ),
          if (widget.outputMode == NormalizationOutputMode.pcm) ...<Widget>[
            Row(
              children: <Widget>[
                const Text('Amplitude window'),
                const Spacer(),
                Text('$_amplitudeWindowSamples samples'),
              ],
            ),
            Slider(
              key: const Key('normalization-waveform-amplitude-window-slider'),
              min: normalizationWaveformMinimumAmplitudeWindowSamples
                  .toDouble(),
              max: normalizationWaveformMaximumAmplitudeWindowSamples
                  .toDouble(),
              value: _amplitudeWindowSamples.toDouble(),
              label: '$_amplitudeWindowSamples samples',
              onChanged: _setAmplitudeWindowSamples,
            ),
          ],
        ],
      ),
    );
  }

  void _resetHistory() {
    _history = NormalizationWaveformHistory(outputMode: widget.outputMode);
    _snapshot = _history.snapshot();
    _runtimeTimestamp = null;
    _displayTimestamp = null;
    _previousTickElapsed = null;
    _amplitudeWindowSamples =
        normalizationWaveformDefaultAmplitudeWindowSamples;
    _ticker.stop();
  }

  void _bindRuntimeFrames(Stream<Object>? frames) {
    unawaited(_subscription?.cancel());
    _subscription = frames?.listen(_onRuntimeFrame);
  }

  void _onRuntimeFrame(Object frame) {
    if (!mounted || frame is! TriggerEvent) return;
    final didRecord = widget.inputSourcePortIds.contains(frame.sourcePortId)
        ? _history.addInput(frame)
        : frame.sourcePortId == widget.outputPortId
        ? _history.addOutput(frame)
        : false;
    if (!didRecord) return;

    // A runtime timestamp is the time the audio/value belongs at. Never move
    // the display clock backwards for a delayed frame; such a frame simply
    // appears at its correct earlier position in the scrolling window.
    final runtimeTimestamp = _runtimeTimestamp;
    if (runtimeTimestamp == null || frame.timestamp > runtimeTimestamp) {
      _runtimeTimestamp = frame.timestamp;
    }
    _displayTimestamp = _delayedDisplayTimestamp(_runtimeTimestamp!);
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final previousTickElapsed = _previousTickElapsed;
    _previousTickElapsed = elapsed;
    final runtimeTimestamp = _runtimeTimestamp;
    if (runtimeTimestamp == null) return;

    final elapsedSincePreviousTick = previousTickElapsed == null
        ? Duration.zero
        : elapsed - previousTickElapsed;
    if (!elapsedSincePreviousTick.isNegative) {
      _runtimeTimestamp = runtimeTimestamp + elapsedSincePreviousTick;
    }
    _displayTimestamp = _delayedDisplayTimestamp(_runtimeTimestamp!);

    // Keep ticking even with no new audio. The graph must continue to scroll
    // stale samples left and eventually off-screen rather than freeze or
    // return to a "waiting" state.
    setState(() {
      _snapshot = _history.snapshot(displayEnd: _displayTimestamp);
    });
  }

  void _setDisplayDuration(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.round());
    _history.setDisplayDuration(duration);
    setState(
      () => _snapshot = _history.snapshot(displayEnd: _displayTimestamp),
    );
  }

  void _setAmplitudeWindowSamples(double value) {
    final amplitudeWindowSamples = value.round();
    _history.setAmplitudeWindowSamples(amplitudeWindowSamples);
    setState(() {
      _amplitudeWindowSamples = amplitudeWindowSamples;
      _snapshot = _history.snapshot(displayEnd: _displayTimestamp);
    });
  }

  Duration _delayedDisplayTimestamp(Duration runtimeTimestamp) =>
      runtimeTimestamp > normalizationWaveformPresentationDelay
      ? runtimeTimestamp - normalizationWaveformPresentationDelay
      : Duration.zero;
}

bool _samePorts(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

class _WaveLegend extends StatelessWidget {
  const _WaveLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 10, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _NormalizationWaveformPainter extends CustomPainter {
  const _NormalizationWaveformPainter(this.snapshot, {required this.viewMode});

  final NormalizationWaveformSnapshot snapshot;
  final NormalizationWaveformViewMode viewMode;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
      Paint()..color = const Color(0xFF181825),
    );
    switch (viewMode) {
      case NormalizationWaveformViewMode.overlay:
        final panel = Offset.zero & size;
        _drawGrid(canvas, panel);
        if (snapshot.latestTimestamp == null) return;
        _drawTrace(canvas, panel, snapshot.input, const Color(0xFF89B4FA));
        _drawTrace(canvas, panel, snapshot.output, const Color(0xFFF9E2AF));
      case NormalizationWaveformViewMode.split:
        const panelGap = 8.0;
        final panelHeight = (size.height - panelGap) / 2;
        final inputPanel = Rect.fromLTWH(0, 0, size.width, panelHeight);
        final outputPanel = Rect.fromLTWH(
          0,
          panelHeight + panelGap,
          size.width,
          panelHeight,
        );
        _drawGrid(canvas, inputPanel);
        _drawGrid(canvas, outputPanel);
        if (snapshot.latestTimestamp == null) return;
        _drawTrace(canvas, inputPanel, snapshot.input, const Color(0xFF89B4FA));
        _drawTrace(
          canvas,
          outputPanel,
          snapshot.output,
          const Color(0xFFF9E2AF),
        );
    }
  }

  void _drawGrid(Canvas canvas, Rect panel) {
    final gridPaint = Paint()
      ..color = const Color(0xFF6C7086)
      ..strokeWidth = 1;
    for (final fraction in <double>[0, 0.5, 1]) {
      final y = panel.top + panel.height * fraction;
      canvas.drawLine(Offset(panel.left, y), Offset(panel.right, y), gridPaint);
    }
  }

  void _drawTrace(
    Canvas canvas,
    Rect panel,
    List<NormalizationWaveformPoint> points,
    Color color,
  ) {
    if (points.isEmpty) return;
    final latest = snapshot.latestTimestamp!;
    final start = latest - snapshot.duration;
    final range = snapshot.duration.inMicroseconds;
    if (range <= 0) return;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final x =
          (panel.left +
                  (point.timestamp - start).inMicroseconds /
                      range *
                      panel.width)
              .clamp(panel.left, panel.right)
              .toDouble();
      final y = (panel.top + (1 - point.value.clamp(0.0, 1.0)) * panel.height)
          .toDouble();
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _NormalizationWaveformPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot || oldDelegate.viewMode != viewMode;
}
