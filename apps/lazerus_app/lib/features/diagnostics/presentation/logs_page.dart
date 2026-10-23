import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../application/diagnostics_controller.dart';
import '../domain/diagnostic_log_entry.dart';

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logState = ref.watch(diagnosticsProvider);
    final diagnostics = ref.read(diagnosticsProvider.notifier);
    final devices = ref.read(debugDevicesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Спробувати зчитати стан',
            onPressed: () => unawaited(devices.requestCurrentStates()),
            icon: const Icon(Icons.sensors),
          ),
          IconButton(
            tooltip: 'Очистити logs',
            onPressed: diagnostics.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: logState.entries.isEmpty
          ? const _EmptyLogs()
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: logState.entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _LogEntryCard(entry: logState.entries[index]),
            ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Поки що немає подій. Після підключення тут з’являться BLE-пакети, '
          'спроби зчитування та помилки комунікації.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.entry});

  final DiagnosticLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(context, entry.level);
    final state = entry.observedState;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(entry.level), size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _labelFor(entry.level),
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: color),
                  ),
                ),
                Text(
                  _time(entry.occurredAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(entry.message),
            if (entry.deviceName != null || entry.deviceId != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                entry.deviceName ?? entry.deviceId!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (state != null) ...<Widget>[
              const SizedBox(height: 6),
              _ObservedState(state: state),
            ],
            if (entry.rawData != null) ...<Widget>[
              const SizedBox(height: 6),
              SelectableText(
                entry.rawHex,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _colorFor(BuildContext context, DiagnosticLogLevel level) {
    return switch (level) {
      DiagnosticLogLevel.info => Theme.of(context).colorScheme.primary,
      DiagnosticLogLevel.warning => Colors.orange,
      DiagnosticLogLevel.error => Theme.of(context).colorScheme.error,
      DiagnosticLogLevel.received => Colors.teal,
    };
  }

  static IconData _iconFor(DiagnosticLogLevel level) {
    return switch (level) {
      DiagnosticLogLevel.info => Icons.info_outline,
      DiagnosticLogLevel.warning => Icons.warning_amber_outlined,
      DiagnosticLogLevel.error => Icons.error_outline,
      DiagnosticLogLevel.received => Icons.sensors,
    };
  }

  static String _labelFor(DiagnosticLogLevel level) {
    return switch (level) {
      DiagnosticLogLevel.info => 'INFO',
      DiagnosticLogLevel.warning => 'WARNING',
      DiagnosticLogLevel.error => 'ERROR',
      DiagnosticLogLevel.received => 'RX',
    };
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}.'
        '${local.millisecond.toString().padLeft(3, '0')}';
  }
}

class _ObservedState extends StatelessWidget {
  const _ObservedState({required this.state});

  final DesiredLightingState state;

  @override
  Widget build(BuildContext context) {
    final color = state.color;
    final brightness = state.brightness;
    final fields = <String>[
      if (state.power != null) 'power: ${state.power}',
      if (color != null) 'rgb: ${color.red}, ${color.green}, ${color.blue}',
      if (brightness != null) 'brightness: ${(brightness * 100).round()}%',
    ];
    return Text(
      'Спостережений стан (best-effort): ${fields.join(' · ')}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
