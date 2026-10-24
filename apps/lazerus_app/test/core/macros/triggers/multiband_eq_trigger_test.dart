import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/triggers/multiband_eq/multiband_eq_trigger.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'mono input produces declared typed outputs for every configured band',
    () {
      final factory = MultibandEqTriggerFactory();
      final config = MultibandEqTriggerConfiguration(
        bands: <MultibandEqBandDefinition>[
          MultibandEqBandDefinition(
            id: 'kick',
            lowerFrequencyHz: 40,
            upperFrequencyHz: 160,
            mode: MultibandEqBandMode.gate,
            gateThreshold: -24,
            outputBuffer: Duration.zero,
          ),
          MultibandEqBandDefinition(
            id: 'presence',
            lowerFrequencyHz: 300,
            upperFrequencyHz: 900,
            mode: MultibandEqBandMode.level,
            normalizationMinimum: -72,
            normalizationMaximum: 0,
            outputBuffer: Duration.zero,
          ),
        ],
      );
      final node = MacroNode(
        id: 'eq',
        kind: factory.kind,
        ports: const <MacroPortDeclaration>[],
        parameters: config.toNodeParameters(),
      );
      final ports = factory.portsFor(node);
      final emitted = <TriggerEvent>[];
      final instance = factory.create(node);
      instance.start(_RecordingEmitter(emitted));

      instance.onInput(
        factory.inputPortId(node),
        TriggerEvent(
          sourcePortId: 'source.audio',
          timestamp: const Duration(milliseconds: 20),
          sequence: 3,
          primaryValue: TriggerMonoAudioValue(
            sampleRateHz: 8000,
            values: List<double>.generate(
              80,
              (index) => index.isEven ? 0.8 : -0.8,
            ),
          ),
        ),
      );

      expect(
        ports
            .where((port) => port.direction == MacroPortDirection.output)
            .map((port) => port.id),
        <String>[
          factory.outputPortId(node, 'kick'),
          factory.outputPortId(node, 'presence'),
        ],
      );
      expect(ports[1].type, MacroPortType.triggerGate);
      expect(ports[2].type, MacroPortType.triggerLevel);
      expect(emitted.map((event) => event.sourcePortId), <String>[
        factory.outputPortId(node, 'kick'),
        factory.outputPortId(node, 'presence'),
      ]);
      expect(emitted[0].primaryValue, isA<TriggerGateValue>());
      expect(emitted[1].primaryValue, isA<TriggerLevelValue>());
    },
  );

  test('per-band buffer emits peak level and gate values once per window', () {
    final factory = MultibandEqTriggerFactory();
    final bufferedNode = _node(
      factory,
      MultibandEqTriggerConfiguration(
        bands: <MultibandEqBandDefinition>[
          MultibandEqBandDefinition(
            id: 'gate',
            lowerFrequencyHz: 0,
            upperFrequencyHz: 100,
            mode: MultibandEqBandMode.gate,
            gateThreshold: -24,
            outputBuffer: const Duration(milliseconds: 50),
          ),
          MultibandEqBandDefinition(
            id: 'level',
            lowerFrequencyHz: 0,
            upperFrequencyHz: 100,
            mode: MultibandEqBandMode.level,
            normalizationMinimum: -72,
            normalizationMaximum: 0,
            outputBuffer: const Duration(milliseconds: 50),
          ),
        ],
      ),
    );
    final immediateNode = _node(
      factory,
      MultibandEqTriggerConfiguration(
        bands: <MultibandEqBandDefinition>[
          MultibandEqBandDefinition(
            id: 'level',
            lowerFrequencyHz: 0,
            upperFrequencyHz: 100,
            mode: MultibandEqBandMode.level,
            normalizationMinimum: -72,
            normalizationMaximum: 0,
            outputBuffer: Duration.zero,
          ),
        ],
      ),
    );
    final bufferedEvents = <TriggerEvent>[];
    final immediateEvents = <TriggerEvent>[];
    final buffered = factory.create(bufferedNode)
      ..start(_RecordingEmitter(bufferedEvents));
    final immediate = factory.create(immediateNode)
      ..start(_RecordingEmitter(immediateEvents));

    final peak = _audioEvent(const Duration(milliseconds: 0), 0.8);
    buffered.onInput(factory.inputPortId(bufferedNode), peak);
    immediate.onInput(factory.inputPortId(immediateNode), peak);
    buffered.onInput(
      factory.inputPortId(bufferedNode),
      _audioEvent(const Duration(milliseconds: 20), 0.1),
    );
    expect(bufferedEvents, isEmpty);

    buffered.onInput(
      factory.inputPortId(bufferedNode),
      _audioEvent(const Duration(milliseconds: 50), 0.1),
    );

    expect(bufferedEvents, hasLength(2));
    expect(bufferedEvents.first.primaryValue, isA<TriggerGateValue>());
    expect(
      (bufferedEvents.first.primaryValue as TriggerGateValue).value,
      isTrue,
    );
    final bufferedLevel = bufferedEvents.last.primaryValue as TriggerLevelValue;
    final immediateLevel =
        immediateEvents.single.primaryValue as TriggerLevelValue;
    expect(bufferedLevel.value, closeTo(immediateLevel.value, 0.000001));
    expect(bufferedLevel.value, inInclusiveRange(0, 1));
  });

  test('legacy linear amplitudes migrate to explicitly serialized dBFS', () {
    final level = MultibandEqBandDefinition.fromJson(<String, Object?>{
      'id': 'legacy-level',
      'lowerFrequencyHz': 20,
      'upperFrequencyHz': 200,
      'mode': 'level',
      'normalizationMinimum': 0.1,
      'normalizationMaximum': 1.0,
    });
    final gate = MultibandEqBandDefinition.fromJson(<String, Object?>{
      'id': 'legacy-gate',
      'lowerFrequencyHz': 20,
      'upperFrequencyHz': 200,
      'mode': 'gate',
      'gateThreshold': 0.5,
      'gateHysteresis': 0.25,
    });

    expect(level.normalizationMinimum, closeTo(-20, 0.000001));
    expect(level.normalizationMaximum, 0);
    expect(gate.gateThreshold, closeTo(-6.0206, 0.0001));
    expect(gate.gateHysteresis, closeTo(6.0206, 0.0001));
    expect(level.toJson(), containsPair('amplitudeUnit', 'dbfs'));
    expect(gate.toJson(), containsPair('amplitudeUnit', 'dbfs'));
  });

  test(
    'dBFS level range is independent of empty bins in the selected band',
    () {
      final factory = MultibandEqTriggerFactory();
      final node = _node(
        factory,
        MultibandEqTriggerConfiguration(
          bands: <MultibandEqBandDefinition>[
            MultibandEqBandDefinition(
              id: 'nyquist',
              lowerFrequencyHz: 3900,
              upperFrequencyHz: 4000,
              mode: MultibandEqBandMode.level,
              normalizationMinimum: -54,
              normalizationMaximum: -36,
              outputBuffer: Duration.zero,
            ),
          ],
        ),
      );
      final emitted = <TriggerEvent>[];
      final instance = factory.create(node)..start(_RecordingEmitter(emitted));

      instance.onInput(
        factory.inputPortId(node),
        TriggerEvent(
          sourcePortId: 'source.audio',
          timestamp: Duration.zero,
          sequence: 0,
          primaryValue: TriggerMonoAudioValue(
            sampleRateHz: 8000,
            values: List<double>.generate(
              80,
              (index) => index.isEven ? 0.0056234132519 : -0.0056234132519,
            ),
          ),
        ),
      );

      final level = emitted.single.primaryValue as TriggerLevelValue;
      // A -45 dBFS Nyquist tone lies exactly halfway between -54 and -36.
      // The band intentionally also includes one empty FFT bin, which must not
      // lower the reported level.
      expect(level.value, closeTo(0.5, 0.0001));
      expect(level.value, inInclusiveRange(0, 1));
    },
  );
}

MacroNode _node(
  MultibandEqTriggerFactory factory,
  MultibandEqTriggerConfiguration configuration,
) => MacroNode(
  id: 'eq-${configuration.bands.length}-${configuration.bands.first.id}',
  kind: factory.kind,
  ports: const <MacroPortDeclaration>[],
  parameters: configuration.toNodeParameters(),
);

TriggerEvent _audioEvent(Duration timestamp, double amplitude) => TriggerEvent(
  sourcePortId: 'source.audio',
  timestamp: timestamp,
  sequence: timestamp.inMilliseconds,
  primaryValue: TriggerMonoAudioValue(
    sampleRateHz: 8000,
    values: List<double>.filled(80, amplitude),
  ),
);

final class _RecordingEmitter implements MacroRuntimeEventEmitter {
  _RecordingEmitter(this.events);

  final List<TriggerEvent> events;

  @override
  void emit(TriggerEvent event) => events.add(event);
}
