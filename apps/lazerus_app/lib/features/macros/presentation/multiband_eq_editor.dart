import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../../core/macros/triggers/multiband_eq/multiband_eq_trigger.dart';
import 'node_modules/multiband_eq/multiband_eq_spectrum_analyzer.dart';

typedef MultibandEqConfigurationChanged = void Function(MultibandEqTriggerConfiguration configuration);

/// Edits a serializable EQ-band configuration without owning persistence or
/// audio capture. It accepts only raw events from the source ports connected
/// to this EQ node, then coalesces visual frames through a Flutter [Ticker].
class MultibandEqEditor extends StatefulWidget {
  MultibandEqEditor({
    super.key,
    required this.configuration,
    required this.onChanged,
    required Iterable<String> audioSourcePortIds,
    this.runtimeFrames,
    this.enabled = true,
  }) : audioSourcePortIds = Set<String>.unmodifiable(audioSourcePortIds);

  final MultibandEqTriggerConfiguration configuration;
  final MultibandEqConfigurationChanged onChanged;
  final Set<String> audioSourcePortIds;
  final Stream<Object>? runtimeFrames;
  final bool enabled;

  @override
  State<MultibandEqEditor> createState() => _MultibandEqEditorState();
}

class _MultibandEqEditorState extends State<MultibandEqEditor> with SingleTickerProviderStateMixin {
  late List<MultibandEqBandDefinition> _bands;
  late final Ticker _spectrumTicker;
  static const _spectrumAnalyzer = MultibandEqSpectrumAnalyzer();
  StreamSubscription<Object>? _spectrumSubscription;
  MultibandEqSpectrum? _pendingSpectrum;
  MultibandEqSpectrum? _displayedSpectrum;
  var _hasPendingSpectrum = false;

  @override
  void initState() {
    super.initState();
    _bands = List<MultibandEqBandDefinition>.of(widget.configuration.bands);
    _spectrumTicker = createTicker(_onSpectrumTick);
    _bindRuntimeFrames(widget.runtimeFrames);
  }

  @override
  void didUpdateWidget(covariant MultibandEqEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration != widget.configuration) {
      _bands = List<MultibandEqBandDefinition>.of(widget.configuration.bands);
    }
    if (oldWidget.runtimeFrames != widget.runtimeFrames) {
      _bindRuntimeFrames(widget.runtimeFrames);
    }
  }

  @override
  void dispose() {
    unawaited(_spectrumSubscription?.cancel());
    _spectrumTicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectrum = _displayedSpectrum;
    final spectrumValues = spectrum?.levels ?? const <double>[];
    final spectrumFrequenciesHz = spectrum?.frequenciesHz ?? const <double>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Multiband EQ', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Semantics(
          label: 'Current audio spectrum display',
          child: SizedBox(
            height: 174,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SpectrumPainter(values: spectrumValues, frequenciesHz: spectrumFrequenciesHz, bands: _bands),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Live analyzer · dBFS scale · bands, modes and thresholds are shown over the spectrum. Display values are transient and are not saved.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _bands.indexed
              .map((entry) => _SpectrumBandLegend(band: entry.$2, color: _spectrumBandColor(entry.$1)))
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        ..._bands.indexed.map(
          (entry) => _BandCard(
            key: ValueKey<String>('eq-band-${entry.$2.id}'),
            band: entry.$2,
            enabled: widget.enabled,
            onChanged: (band) => _replaceBand(entry.$1, band),
            onRemove: _bands.length > 1 ? () => _removeBand(entry.$1) : null,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-eq-band'),
          onPressed: widget.enabled ? _addBand : null,
          icon: const Icon(Icons.add),
          label: const Text('Add frequency band'),
        ),
      ],
    );
  }

  void _bindRuntimeFrames(Stream<Object>? runtimeFrames) {
    unawaited(_spectrumSubscription?.cancel());
    _spectrumTicker.stop();
    _pendingSpectrum = null;
    _displayedSpectrum = null;
    _hasPendingSpectrum = false;
    _spectrumSubscription = runtimeFrames?.listen(_onRuntimeFrame);
  }

  void _onRuntimeFrame(Object frame) {
    if (frame is! TriggerEvent ||
        !widget.audioSourcePortIds.contains(frame.sourcePortId) ||
        frame.primaryValue is! TriggerMonoAudioValue) {
      return;
    }
    final spectrum = _spectrumAnalyzer.analyze(frame.primaryValue as TriggerMonoAudioValue);
    _pendingSpectrum = spectrum;
    _hasPendingSpectrum = true;
    if (!_spectrumTicker.isActive) {
      _spectrumTicker.start();
    }
  }

  void _onSpectrumTick(Duration _) {
    if (!_hasPendingSpectrum || !mounted) {
      _spectrumTicker.stop();
      return;
    }
    final nextSpectrum = _pendingSpectrum;
    _hasPendingSpectrum = false;
    if (nextSpectrum != null) {
      setState(() => _displayedSpectrum = nextSpectrum);
    }
    if (!_hasPendingSpectrum) {
      _spectrumTicker.stop();
    }
  }

  void _replaceBand(int index, MultibandEqBandDefinition band) {
    final candidate = List<MultibandEqBandDefinition>.of(_bands)..[index] = band;
    _commit(candidate);
  }

  void _removeBand(int index) => _commit(List<MultibandEqBandDefinition>.of(_bands)..removeAt(index));
  void _addBand() {
    final last = _bands.last;
    final lower = last.upperFrequencyHz;
    _commit(<MultibandEqBandDefinition>[
      ..._bands,
      MultibandEqBandDefinition(
        id: _nextId(),
        lowerFrequencyHz: lower,
        upperFrequencyHz: lower + 1000,
        mode: MultibandEqBandMode.level,
        normalizationMinimum: multibandEqMinimumDbfs,
        normalizationMaximum: multibandEqMaximumDbfs,
        outputBuffer: const Duration(milliseconds: 50),
      ),
    ]);
  }

  String _nextId() {
    var index = _bands.length + 1;
    while (_bands.any((band) => band.id == 'band_$index')) {
      index++;
    }
    return 'band_$index';
  }

  void _commit(List<MultibandEqBandDefinition> bands) {
    try {
      final configuration = MultibandEqTriggerConfiguration(bands: bands, outputInterval: widget.configuration.outputInterval);
      setState(() => _bands = bands);
      widget.onChanged(configuration);
    } on ArgumentError {
      // Input fields can briefly be incomplete. Retain the last valid model
      // and let the relevant field show its normal validation state.
    }
  }
}

class _BandCard extends StatelessWidget {
  const _BandCard({super.key, required this.band, required this.enabled, required this.onChanged, this.onRemove});
  final MultibandEqBandDefinition band;
  final bool enabled;
  final ValueChanged<MultibandEqBandDefinition> onChanged;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(band.id, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                key: Key('remove-eq-band-${band.id}'),
                tooltip: 'Remove band',
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberField(
                  label: 'From Hz',
                  value: band.lowerFrequencyHz,
                  enabled: enabled,
                  onSubmitted: (value) => _update(lower: value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'To Hz',
                  value: band.upperFrequencyHz,
                  enabled: enabled,
                  onSubmitted: (value) => _update(upper: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<MultibandEqBandMode>(
            key: Key('eq-band-mode-${band.id}'),
            initialValue: band.mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Output mode', border: OutlineInputBorder()),
            items: MultibandEqBandMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(mode == MultibandEqBandMode.gate ? 'Gate (on/off)' : 'Level (normalized)'),
                  ),
                )
                .toList(growable: false),
            onChanged: enabled ? _changeMode : null,
          ),
          const SizedBox(height: 8),
          if (band.mode == MultibandEqBandMode.gate) ...<Widget>[
            _NumberField(
              label: 'Gate threshold (dBFS)',
              value: band.gateThreshold!,
              enabled: enabled,
              onSubmitted: (value) => _update(gateThreshold: value),
            ),
            const SizedBox(height: 8),
            _NumberField(
              label: 'Hysteresis (dB)',
              value: band.gateHysteresis,
              enabled: enabled,
              onSubmitted: (value) => _update(hysteresis: value),
            ),
          ] else
            Row(
              children: <Widget>[
                Expanded(
                  child: _NumberField(
                    label: 'Level minimum (dBFS)',
                    value: band.normalizationMinimum!,
                    enabled: enabled,
                    onSubmitted: (value) => _update(minimum: value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    label: 'Level maximum (dBFS)',
                    value: band.normalizationMaximum!,
                    enabled: enabled,
                    onSubmitted: (value) => _update(maximum: value),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          _NumberField(
            label: 'Peak buffer (ms; 0 = immediate)',
            value: band.outputBuffer.inMilliseconds.toDouble(),
            enabled: enabled,
            onSubmitted: (value) => _update(outputBufferMilliseconds: value.round()),
          ),
        ],
      ),
    ),
  );
  void _changeMode(MultibandEqBandMode? mode) {
    if (mode == null || mode == band.mode) return;
    if (mode == MultibandEqBandMode.gate) {
      onChanged(
        MultibandEqBandDefinition(
          id: band.id,
          lowerFrequencyHz: band.lowerFrequencyHz,
          upperFrequencyHz: band.upperFrequencyHz,
          mode: mode,
          gateThreshold: -24,
          gateHysteresis: 3,
          attack: band.attack,
          release: band.release,
          outputBuffer: band.outputBuffer,
        ),
      );
    } else {
      onChanged(
        MultibandEqBandDefinition(
          id: band.id,
          lowerFrequencyHz: band.lowerFrequencyHz,
          upperFrequencyHz: band.upperFrequencyHz,
          mode: mode,
          normalizationMinimum: multibandEqMinimumDbfs,
          normalizationMaximum: multibandEqMaximumDbfs,
          attack: band.attack,
          release: band.release,
          outputBuffer: band.outputBuffer,
        ),
      );
    }
  }

  void _update({
    double? lower,
    double? upper,
    double? gateThreshold,
    double? hysteresis,
    double? minimum,
    double? maximum,
    int? outputBufferMilliseconds,
  }) {
    final nextLower = lower ?? band.lowerFrequencyHz;
    final nextUpper = upper ?? band.upperFrequencyHz;
    try {
      onChanged(
        MultibandEqBandDefinition(
          id: band.id,
          lowerFrequencyHz: nextLower,
          upperFrequencyHz: nextUpper,
          mode: band.mode,
          gateThreshold: band.mode == MultibandEqBandMode.gate ? (gateThreshold ?? band.gateThreshold) : null,
          gateHysteresis: band.mode == MultibandEqBandMode.gate ? (hysteresis ?? band.gateHysteresis) : 0,
          normalizationMinimum: band.mode == MultibandEqBandMode.level ? (minimum ?? band.normalizationMinimum) : null,
          normalizationMaximum: band.mode == MultibandEqBandMode.level ? (maximum ?? band.normalizationMaximum) : null,
          attack: band.attack,
          release: band.release,
          outputBuffer: Duration(milliseconds: outputBufferMilliseconds ?? band.outputBuffer.inMilliseconds),
        ),
      );
    } on ArgumentError {
      /* The form keeps the previous valid definition. */
    }
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.value, required this.enabled, required this.onSubmitted});
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onSubmitted;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: Key('eq-$label'),
    initialValue: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2),
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    validator: (text) => double.tryParse(text ?? '') == null ? 'Enter a number' : null,
    onFieldSubmitted: _submit,
    onChanged: _submit,
  );
  void _submit(String text) {
    final parsed = double.tryParse(text);
    if (parsed != null) onSubmitted(parsed);
  }
}

class _SpectrumBandLegend extends StatelessWidget {
  const _SpectrumBandLegend({required this.band, required this.color});

  final MultibandEqBandDefinition band;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final details = switch (band.mode) {
      MultibandEqBandMode.gate => 'Gate ≥ ${band.gateThreshold!.toStringAsFixed(1)} dBFS',
      MultibandEqBandMode.level =>
        'Level ${band.normalizationMinimum!.toStringAsFixed(1)}–${band.normalizationMaximum!.toStringAsFixed(1)} dBFS',
    };
    final buffer = band.outputBuffer == Duration.zero ? 'immediate' : 'peak/${band.outputBuffer.inMilliseconds} ms';
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text('${band.id} · $details · $buffer'),
    );
  }
}

Color _spectrumBandColor(int index) {
  const colors = <Color>[Color(0xFF89B4FA), Color(0xFFA6E3A1), Color(0xFFF9E2AF), Color(0xFFFAB387), Color(0xFFCBA6F7)];
  return colors[index % colors.length];
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({required this.values, required this.frequenciesHz, required this.bands});

  final List<double> values;
  final List<double> frequenciesHz;
  final List<MultibandEqBandDefinition> bands;

  static const _minimumDbfs = -72.0;

  @override
  void paint(Canvas canvas, Size size) {
    const leftAxis = 32.0;
    const bottomAxis = 18.0;
    final graph = Rect.fromLTWH(leftAxis, 0, math.max(1, size.width - leftAxis), math.max(1, size.height - bottomAxis));
    final background = Paint()..color = const Color(0xFF11111B);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)), background);
    final visibleFrequencies = frequenciesHz.where((value) => value > 0);
    final lowestSpectrumHz = visibleFrequencies.isEmpty ? 20.0 : visibleFrequencies.reduce(math.min);
    final highestSpectrumHz = visibleFrequencies.isEmpty ? 20000.0 : visibleFrequencies.reduce(math.max);
    final lowestBandHz = bands.map((band) => band.lowerFrequencyHz).reduce(math.min);
    final highestBandHz = bands.map((band) => band.upperFrequencyHz).reduce(math.max);
    final minimumHz = math.max(1.0, math.min(20.0, math.min(lowestSpectrumHz, lowestBandHz)));
    final maximumHz = math.max(minimumHz * 1.01, math.max(highestSpectrumHz, highestBandHz));
    double xForFrequency(double frequencyHz) {
      final clamped = frequencyHz.clamp(minimumHz, maximumHz).toDouble();
      final fraction = math.log(clamped / minimumHz) / math.log(maximumHz / minimumHz);
      return graph.left + graph.width * fraction;
    }

    double yForDbfs(double dbfs) {
      final normalized = ((dbfs.clamp(_minimumDbfs, 0.0) - _minimumDbfs) / -_minimumDbfs).toDouble();
      return graph.bottom - graph.height * normalized;
    }

    double dbfsForLevel(double level) {
      if (level <= 0) return _minimumDbfs;
      return (20 * math.log(level) / math.ln10).clamp(_minimumDbfs, 0.0).toDouble();
    }

    final gridPaint = Paint()
      ..color = const Color(0x3345455A)
      ..strokeWidth = 1;
    for (final dbfs in <int>[-72, -54, -36, -18, 0]) {
      final y = yForDbfs(dbfs.toDouble());
      canvas.drawLine(Offset(graph.left, y), Offset(graph.right, y), gridPaint);
      _paintText(canvas, '$dbfs', Offset(2, y - 6), const Color(0xFFBAC2DE), 9);
    }
    for (final frequency in <int>[100, 1000, 10000]) {
      if (frequency <= minimumHz || frequency >= maximumHz) continue;
      final x = xForFrequency(frequency.toDouble());
      canvas.drawLine(Offset(x, graph.top), Offset(x, graph.bottom), gridPaint);
      _paintText(
        canvas,
        frequency >= 1000 ? '${frequency ~/ 1000}k' : '$frequency',
        Offset(x - 7, graph.bottom + 4),
        const Color(0xFFBAC2DE),
        9,
      );
    }

    for (final entry in bands.indexed) {
      final band = entry.$2;
      final color = _spectrumBandColor(entry.$1);
      final left = xForFrequency(band.lowerFrequencyHz);
      final right = xForFrequency(band.upperFrequencyHz);
      canvas.drawRect(Rect.fromLTRB(left, graph.top, right, graph.bottom), Paint()..color = color.withValues(alpha: 0.14));
      final thresholdPaint = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = 1.3;
      final thresholds = switch (band.mode) {
        MultibandEqBandMode.gate => <double>[band.gateThreshold!],
        MultibandEqBandMode.level => <double>[band.normalizationMinimum!, band.normalizationMaximum!],
      };
      for (final threshold in thresholds) {
        final y = yForDbfs(threshold);
        canvas.drawLine(Offset(left, y), Offset(right, y), thresholdPaint);
      }
      if (right - left >= 56) {
        final mode = band.mode == MultibandEqBandMode.gate ? 'Gate' : 'Level';
        _paintText(canvas, '${band.id} · $mode', Offset(left + 4, graph.top + 4), color, 9);
      }
    }

    if (values.isNotEmpty && values.length == frequenciesHz.length) {
      final line = Path();
      final fill = Path();
      for (var index = 0; index < values.length; index++) {
        final point = Offset(xForFrequency(frequenciesHz[index]), yForDbfs(dbfsForLevel(values[index])));
        if (index == 0) {
          line.moveTo(point.dx, point.dy);
          fill
            ..moveTo(point.dx, graph.bottom)
            ..lineTo(point.dx, point.dy);
        } else {
          line.lineTo(point.dx, point.dy);
          fill.lineTo(point.dx, point.dy);
        }
      }
      fill
        ..lineTo(xForFrequency(frequenciesHz.last), graph.bottom)
        ..close();
      canvas.drawPath(fill, Paint()..color = const Color(0x5589B4FA));
      canvas.drawPath(
        line,
        Paint()
          ..color = const Color(0xFF89B4FA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintText(Canvas canvas, String text, Offset offset, Color color, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) =>
      old.values != values || old.frequenciesHz != frequenciesHz || old.bands != bands;
}
