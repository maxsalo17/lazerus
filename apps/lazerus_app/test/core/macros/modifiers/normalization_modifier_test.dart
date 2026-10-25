import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/modifiers/normalization/normalization_modifier.dart';
import 'package:lazerus_app/core/macros/registry/macro_module_registry.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  group('NormalizationModifierConfiguration', () {
    test('defaults to a five-second PCM window and round-trips', () {
      final configuration =
          NormalizationModifierConfiguration.fromNodeParameters(
            const <String, Object?>{},
          );

      expect(configuration.outputMode, NormalizationOutputMode.pcm);
      expect(configuration.windowDuration, const Duration(seconds: 5));
      expect(
        NormalizationModifierConfiguration.fromNodeParameters(
          configuration.toNodeParameters(),
        ).outputMode,
        NormalizationOutputMode.pcm,
      );
    });

    test('rejects an unknown mode and invalid window duration', () {
      expect(
        () => NormalizationModifierConfiguration.fromNodeParameters(
          const <String, Object?>{'outputMode': 'unknown'},
        ),
        throwsFormatException,
      );
      expect(
        () => NormalizationModifierConfiguration.fromNodeParameters(
          const <String, Object?>{'windowDurationMilliseconds': 0},
        ),
        throwsFormatException,
      );
    });
  });

  test('declares PCM or value output ports from the configured mode', () {
    final factory = NormalizationModifierFactory();

    expect(
      factory
          .portsFor(_node(factory, NormalizationOutputMode.pcm))
          .map((port) => port.type),
      orderedEquals(<MacroPortType>[
        MacroPortType.triggerMonoAudio,
        MacroPortType.triggerMonoAudio,
      ]),
    );
    expect(
      factory
          .portsFor(_node(factory, NormalizationOutputMode.value))
          .map((port) => port.type),
      orderedEquals(<MacroPortType>[
        MacroPortType.triggerMonoAudio,
        MacroPortType.triggerLevel,
      ]),
    );
  });

  test('runtime registry resolves the configured normalization contract', () {
    final factory = NormalizationModifierFactory();
    final ports = createMacroModuleRegistry().portsFor(
      _node(factory, NormalizationOutputMode.value),
    );

    expect(ports, isNotNull);
    expect(ports!.last.type, MacroPortType.triggerLevel);
  });

  test('value mode maps relative RMS dynamics into 0..1', () {
    final factory = NormalizationModifierFactory();
    final node = _node(
      factory,
      NormalizationOutputMode.value,
      windowDuration: const Duration(seconds: 1),
    );
    final emitted = <TriggerEvent>[];
    final instance = factory.create(node)..start(_RecordingEmitter(emitted));

    instance.onInput(factory.audioInputPortId(node), _audioEvent(0, 0.01));
    instance.onInput(factory.audioInputPortId(node), _audioEvent(100, 1));
    instance.onInput(factory.audioInputPortId(node), _audioEvent(200, 0.1));

    expect(
      emitted.map((event) => event.primaryValue),
      everyElement(isA<TriggerLevelValue>()),
    );
    final values = emitted
        .map((event) => (event.primaryValue as TriggerLevelValue).value)
        .toList(growable: false);
    expect(values[0], 0);
    expect(values[1], 1);
    expect(values[2], closeTo(0.5, 0.000001));
    expect(emitted.last.timestamp, const Duration(milliseconds: 200));
    expect(emitted.last.sequence, 200);
  });

  test('value mode discards values outside the exact rolling window', () {
    final factory = NormalizationModifierFactory();
    final node = _node(
      factory,
      NormalizationOutputMode.value,
      windowDuration: const Duration(seconds: 1),
    );
    final emitted = <TriggerEvent>[];
    final instance = factory.create(node)..start(_RecordingEmitter(emitted));

    instance.onInput(factory.audioInputPortId(node), _audioEvent(0, 0.01));
    instance.onInput(factory.audioInputPortId(node), _audioEvent(100, 1));
    instance.onInput(factory.audioInputPortId(node), _audioEvent(1101, 0.1));

    final value = emitted.last.primaryValue as TriggerLevelValue;
    expect(value.value, 0);
  });

  test('value mode retains a frame exactly on the rolling-window boundary', () {
    final factory = NormalizationModifierFactory();
    final node = _node(
      factory,
      NormalizationOutputMode.value,
      windowDuration: const Duration(seconds: 1),
    );
    final emitted = <TriggerEvent>[];
    final instance = factory.create(node)..start(_RecordingEmitter(emitted));

    instance.onInput(factory.audioInputPortId(node), _audioEvent(0, 0.01));
    instance.onInput(factory.audioInputPortId(node), _audioEvent(1000, 1));

    expect((emitted.last.primaryValue as TriggerLevelValue).value, 1);
  });

  test(
    'identical dynamics at different microphone gains normalize equally',
    () {
      final factory = NormalizationModifierFactory();
      final quiet = _node(factory, NormalizationOutputMode.value);
      final loud = _node(factory, NormalizationOutputMode.value);
      final quietEvents = <TriggerEvent>[];
      final loudEvents = <TriggerEvent>[];
      final quietInstance = factory.create(quiet)
        ..start(_RecordingEmitter(quietEvents));
      final loudInstance = factory.create(loud)
        ..start(_RecordingEmitter(loudEvents));

      for (final entry in <(int, double)>[
        (0, 0.001), // -60 dBFS
        (100, 0.01), // -40 dBFS
        (200, 0.00316227766), // -50 dBFS
      ]) {
        quietInstance.onInput(
          factory.audioInputPortId(quiet),
          _audioEvent(entry.$1, entry.$2),
        );
      }
      for (final entry in <(int, double)>[
        (0, 0.01), // -40 dBFS
        (100, 0.1), // -20 dBFS
        (200, 0.0316227766), // -30 dBFS
      ]) {
        loudInstance.onInput(
          factory.audioInputPortId(loud),
          _audioEvent(entry.$1, entry.$2),
        );
      }

      final quietValues = _levels(quietEvents);
      final loudValues = _levels(loudEvents);
      expect(quietValues, hasLength(3));
      expect(loudValues, hasLength(3));
      for (var index = 0; index < quietValues.length; index++) {
        expect(quietValues[index], closeTo(loudValues[index], 0.000001));
      }
      expect(quietValues.last, closeTo(0.5, 0.000001));
    },
  );

  test('PCM mode preserves sample rate and maps frames in dBFS space', () {
    final factory = NormalizationModifierFactory();
    final node = _node(
      factory,
      NormalizationOutputMode.pcm,
      windowDuration: const Duration(seconds: 1),
    );
    final emitted = <TriggerEvent>[];
    final instance = factory.create(node)..start(_RecordingEmitter(emitted));

    instance.onInput(factory.audioInputPortId(node), _audioEvent(0, 0.1));
    instance.onInput(factory.audioInputPortId(node), _audioEvent(100, 1));
    instance.onInput(
      factory.audioInputPortId(node),
      _audioEvent(200, 0.316227766),
    );

    final first = emitted.first.primaryValue as TriggerMonoAudioValue;
    final normalized = emitted.last.primaryValue as TriggerMonoAudioValue;
    expect(first.values, everyElement(closeTo(0.1, 0.000001)));
    expect(normalized.sampleRateHz, 8000);
    // -10 dBFS lies halfway through the observed -20..0 dBFS range, so the
    // output target is -36 dBFS (approximately 0.0158489 linear RMS).
    expect(normalized.values, everyElement(closeTo(0.0158489319, 0.000001)));
  });

  test('PCM mode handles silence and clamps peaks to valid PCM', () {
    final factory = NormalizationModifierFactory();
    final node = _node(factory, NormalizationOutputMode.pcm);
    final emitted = <TriggerEvent>[];
    final instance = factory.create(node)..start(_RecordingEmitter(emitted));

    instance.onInput(factory.audioInputPortId(node), _audioEvent(0, 0.1));
    instance.onInput(
      factory.audioInputPortId(node),
      TriggerEvent(
        sourcePortId: 'microphone.audio',
        timestamp: const Duration(milliseconds: 10),
        sequence: 10,
        primaryValue: TriggerMonoAudioValue(
          sampleRateHz: 8000,
          values: const <double>[1, 0],
        ),
      ),
    );
    instance.onInput(factory.audioInputPortId(node), _audioEvent(20, 0));

    final peaked = emitted[1].primaryValue as TriggerMonoAudioValue;
    final silent = emitted.last.primaryValue as TriggerMonoAudioValue;
    expect(peaked.values, everyElement(inInclusiveRange(-1.0, 1.0)));
    expect(peaked.values.first, 1);
    expect(silent.values, everyElement(0));
  });
}

MacroNode _node(
  NormalizationModifierFactory factory,
  NormalizationOutputMode outputMode, {
  Duration windowDuration = const Duration(seconds: 5),
}) {
  final configuration = NormalizationModifierConfiguration(
    outputMode: outputMode,
    windowDuration: windowDuration,
  );
  final bareNode = MacroNode(
    id: 'normalization-${outputMode.name}',
    kind: factory.kind,
    ports: const <MacroPortDeclaration>[],
    parameters: configuration.toNodeParameters(),
  );
  return bareNode.copyWith(ports: factory.portsFor(bareNode));
}

TriggerEvent _audioEvent(int milliseconds, double amplitude) => TriggerEvent(
  sourcePortId: 'microphone.audio',
  timestamp: Duration(milliseconds: milliseconds),
  sequence: milliseconds,
  primaryValue: TriggerMonoAudioValue(
    sampleRateHz: 8000,
    values: List<double>.filled(80, amplitude),
  ),
);

List<double> _levels(Iterable<TriggerEvent> events) => events
    .map((event) => (event.primaryValue as TriggerLevelValue).value)
    .toList(growable: false);

final class _RecordingEmitter implements MacroRuntimeEventEmitter {
  _RecordingEmitter(this.events);

  final List<TriggerEvent> events;

  @override
  void emit(TriggerEvent event) => events.add(event);
}
