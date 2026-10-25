import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/modifiers/normalization/normalization_modifier.dart';
import 'package:lazerus_app/features/macros/presentation/normalization_waveform_display.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test('display duration supports up to ten seconds in 50 ms increments', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
    );

    history.setDisplayDuration(const Duration(seconds: 10));

    expect(history.displayDuration, const Duration(seconds: 10));
    expect(
      () => history.setDisplayDuration(const Duration(milliseconds: 10001)),
      throwsArgumentError,
    );
  });

  test('defaults to a five-second frame and 1024-sample amplitude windows', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
    );

    expect(history.displayDuration, const Duration(seconds: 5));
    expect(history.amplitudeWindowSamples, 1024);
  });

  test(
    'PCM history emits the maximum absolute amplitude for each N samples',
    () {
      final history = NormalizationWaveformHistory(
        outputMode: NormalizationOutputMode.pcm,
        amplitudeWindowSamples: 50,
      );
      final samples = List<double>.filled(100, 0.1)
        ..[1] = -0.4
        ..[70] = -0.7;

      history.addInput(_pcmEvent(100, samples));

      final snapshot = history.snapshot();

      expect(snapshot.input.map((point) => point.value), <double>[0.4, 0.7]);
      expect(snapshot.input.map((point) => point.timestamp), <Duration>[
        const Duration(milliseconds: 49),
        const Duration(milliseconds: 99),
      ]);

      history.setAmplitudeWindowSamples(50);
      expect(history.amplitudeWindowSamples, 50);
      expect(() => history.setAmplitudeWindowSamples(49), throwsArgumentError);
      expect(
        () => history.setAmplitudeWindowSamples(44001),
        throwsArgumentError,
      );
    },
  );

  test('PCM history crops samples outside the selected display duration', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
      displayDuration: const Duration(milliseconds: 100),
    );

    history.addInput(_audioEvent(100, 0.1));
    history.addOutput(_audioEvent(100, 0.2));
    history.addInput(_audioEvent(200, 0.3));
    history.addOutput(_audioEvent(200, 0.4));

    final snapshot = history.snapshot();
    expect(snapshot.isReady, isTrue);
    expect(snapshot.input, isNotEmpty);
    expect(snapshot.output, isNotEmpty);
    expect(snapshot.input.every((point) => point.value == 0.3), isTrue);
    expect(snapshot.output.every((point) => point.value == 0.4), isTrue);
    expect(history.inputRetainedDuration, lessThanOrEqualTo(snapshot.duration));
    expect(
      history.outputRetainedDuration,
      lessThanOrEqualTo(snapshot.duration),
    );
  });

  test('zooming out does not restore discarded PCM history', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
      displayDuration: const Duration(milliseconds: 100),
    );

    history.addInput(_audioEvent(100, 0.1));
    history.addOutput(_audioEvent(100, 0.2));
    history.addInput(_audioEvent(200, 0.3));
    history.addOutput(_audioEvent(200, 0.4));
    history.setDisplayDuration(const Duration(milliseconds: 200));

    expect(history.snapshot().isReady, isFalse);
    expect(history.inputRetainedDuration, const Duration(milliseconds: 100));

    history.addInput(_audioEvent(300, 0.5));
    history.addOutput(_audioEvent(300, 0.6));

    expect(history.snapshot().isReady, isTrue);
    expect(
      history.inputRetainedDuration,
      lessThanOrEqualTo(const Duration(milliseconds: 200)),
    );
  });

  test('PCM history drops samples before the runtime clock begins', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
      displayDuration: const Duration(milliseconds: 100),
    );

    history.addInput(_audioEvent(50, 0.25));

    final snapshot = history.snapshot();
    expect(snapshot.input, hasLength(1));
    expect(snapshot.input.single.value, 0.25);
    expect(history.inputRetainedDuration, const Duration(milliseconds: 50));
  });

  test(
    'PCM amplitude windows retain the peak emitted for each completed range',
    () {
      final history = NormalizationWaveformHistory(
        outputMode: NormalizationOutputMode.pcm,
        displayDuration: const Duration(seconds: 1),
        amplitudeWindowSamples: 50,
      );
      final first = List<double>.filled(50, 0.1)..[1] = -0.6;
      final second = List<double>.filled(50, 0.1)..[20] = -0.8;

      history.addInput(_pcmEvent(50, first));
      history.addInput(_pcmEvent(100, second));

      expect(history.snapshot().input.map((point) => point.value), <double>[
        0.6,
        0.8,
      ]);
    },
  );

  test('a delayed display snapshot excludes future PCM samples', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
      displayDuration: const Duration(milliseconds: 100),
    );

    history.addInput(_audioEvent(100, 0.25));
    history.addOutput(_audioEvent(100, 0.5));
    final snapshot = history.snapshot(
      displayEnd: const Duration(milliseconds: 50),
    );

    expect(snapshot.latestTimestamp, const Duration(milliseconds: 50));
    expect(
      snapshot.input.every(
        (point) => point.timestamp <= const Duration(milliseconds: 50),
      ),
      isTrue,
    );
    expect(
      snapshot.output.every(
        (point) => point.timestamp <= const Duration(milliseconds: 50),
      ),
      isTrue,
    );
  });

  test('scrolling snapshot advances a signal left and then removes it', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.pcm,
      displayDuration: const Duration(milliseconds: 100),
    );

    history.addInput(_audioEvent(100, 0.25));
    history.addOutput(_audioEvent(100, 0.5));

    final atSignalEnd = history.snapshot(
      displayEnd: const Duration(milliseconds: 100),
    );
    final afterFiftyMilliseconds = history.snapshot(
      displayEnd: const Duration(milliseconds: 150),
    );
    final afterTheSignal = history.snapshot(
      displayEnd: const Duration(milliseconds: 200),
    );

    expect(atSignalEnd.latestTimestamp, const Duration(milliseconds: 100));
    expect(
      afterFiftyMilliseconds.latestTimestamp,
      const Duration(milliseconds: 150),
    );
    expect(
      afterFiftyMilliseconds.input.first.timestamp,
      const Duration(milliseconds: 99),
    );
    expect(
      afterFiftyMilliseconds.output.first.timestamp,
      const Duration(milliseconds: 99),
    );
    expect(afterTheSignal.input, isEmpty);
    expect(afterTheSignal.output, isEmpty);
  });

  test('value history overlays fixed input level and normalized output', () {
    final history = NormalizationWaveformHistory(
      outputMode: NormalizationOutputMode.value,
      displayDuration: const Duration(milliseconds: 100),
    );

    history.addInput(_audioEvent(0, 0.01)); // -40 dBFS -> 32 / 72.
    history.addOutput(_levelEvent(0, 0));
    history.addInput(_audioEvent(100, 0.1)); // -20 dBFS -> 52 / 72.
    history.addOutput(_levelEvent(100, 1));

    final snapshot = history.snapshot();
    expect(snapshot.isReady, isTrue);
    final input = snapshot.input.map((point) => point.value).toList();
    expect(input[0], closeTo(32 / 72, 0.000001));
    expect(input[1], closeTo(52 / 72, 0.000001));
    expect(snapshot.output.map((point) => point.value), <double>[0, 1]);
    expect(history.inputRetainedDuration, const Duration(milliseconds: 100));
    expect(history.outputRetainedDuration, const Duration(milliseconds: 100));
  });

  testWidgets('PCM overlay stays live when the display frame zooms out', (
    tester,
  ) async {
    final frames = StreamController<Object>.broadcast(sync: true);
    addTearDown(frames.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: NormalizationWaveformDisplay(
              outputMode: NormalizationOutputMode.pcm,
              inputSourcePortIds: const <String>{'source.audio'},
              outputPortId: 'normalization.normalized',
              runtimeFrames: frames.stream,
            ),
          ),
        ),
      ),
    );

    frames
      ..add(_pcmInputEvent(250, 0.2))
      ..add(_pcmOutputEvent(250, 0.4));
    await tester.pump();

    expect(
      find.byKey(const Key('normalization-waveform-waiting')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('normalization-waveform-amplitude-window-slider')),
      findsOneWidget,
    );
    expect(find.text('1024 samples'), findsOneWidget);
    expect(find.text('5000 ms'), findsOneWidget);
    expect(
      find.byKey(const Key('normalization-waveform-view-mode')),
      findsOneWidget,
    );
    await tester.tap(find.text('Split'));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('normalization-waveform-duration-slider')),
      const Offset(120, 0),
    );
    await tester.pump();

    expect(find.textContaining('Waiting for'), findsNothing);
  });

  testWidgets('value overlay identifies both 0..1 traces', (tester) async {
    final frames = StreamController<Object>.broadcast(sync: true);
    addTearDown(frames.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: NormalizationWaveformDisplay(
              outputMode: NormalizationOutputMode.value,
              inputSourcePortIds: const <String>{'source.audio'},
              outputPortId: 'normalization.normalized',
              runtimeFrames: frames.stream,
            ),
          ),
        ),
      ),
    );

    frames
      ..add(_audioEvent(0, 0.01))
      ..add(_levelEvent(0, 0))
      ..add(_audioEvent(250, 0.1))
      ..add(_levelEvent(250, 1));
    await tester.pump();

    expect(find.text('Input level'), findsOneWidget);
    expect(find.text('Normalized value'), findsOneWidget);
    expect(
      find.byKey(const Key('normalization-waveform-amplitude-window-slider')),
      findsNothing,
    );
    expect(find.textContaining('Waiting for'), findsNothing);
  });
}

TriggerEvent _audioEvent(int milliseconds, double amplitude) => TriggerEvent(
  sourcePortId: 'source.audio',
  timestamp: Duration(milliseconds: milliseconds),
  sequence: milliseconds,
  primaryValue: TriggerMonoAudioValue(
    sampleRateHz: 1000,
    values: List<double>.filled(100, amplitude),
  ),
);

TriggerEvent _levelEvent(int milliseconds, double value) => TriggerEvent(
  sourcePortId: 'normalization.normalized',
  timestamp: Duration(milliseconds: milliseconds),
  sequence: milliseconds,
  primaryValue: TriggerLevelValue(value),
);

TriggerEvent _pcmOutputEvent(int milliseconds, double amplitude) =>
    TriggerEvent(
      sourcePortId: 'normalization.normalized',
      timestamp: Duration(milliseconds: milliseconds),
      sequence: milliseconds,
      primaryValue: TriggerMonoAudioValue(
        sampleRateHz: 1000,
        values: List<double>.filled(250, amplitude),
      ),
    );

TriggerEvent _pcmInputEvent(int milliseconds, double amplitude) => TriggerEvent(
  sourcePortId: 'source.audio',
  timestamp: Duration(milliseconds: milliseconds),
  sequence: milliseconds,
  primaryValue: TriggerMonoAudioValue(
    sampleRateHz: 1000,
    values: List<double>.filled(250, amplitude),
  ),
);

TriggerEvent _pcmEvent(
  int milliseconds,
  List<double> samples, {
  int sampleRateHz = 1000,
}) => TriggerEvent(
  sourcePortId: 'source.audio',
  timestamp: Duration(milliseconds: milliseconds),
  sequence: milliseconds,
  primaryValue: TriggerMonoAudioValue(
    sampleRateHz: sampleRateHz,
    values: samples,
  ),
);
