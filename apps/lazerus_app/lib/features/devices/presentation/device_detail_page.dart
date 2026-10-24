import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../application/device_controls_controller.dart';
import 'color_utils.dart';
import 'device_display.dart';

/// Full manual-control surface for one physical device.
class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key, required this.appDeviceId});

  final String appDeviceId;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  double? _previewBrightness;

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(debugDevicesProvider).devices[widget.appDeviceId];
    final controls = ref.read(deviceControlsProvider.notifier);
    final controlState = controls.stateFor(widget.appDeviceId);
    final brightness = _previewBrightness ?? controlState.brightness;
    final connected = device?.status == DebugDeviceConnectionStatus.connected;
    final name = device?.endpoint.displayName ?? 'Девайс';

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_deviceStatus(device)),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Живлення'),
                    value: controlState.power ?? false,
                    onChanged: connected
                        ? (enabled) => unawaited(_dispatch(SetPower(enabled)))
                        : null,
                  ),
                  const Divider(),
                  Text('Колір', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _presets
                        .map(
                          (preset) => Tooltip(
                            message: preset.label,
                            child: IconButton.filledTonal(
                              onPressed: connected
                                  ? () => unawaited(
                                      _dispatch(SetColor(preset.color)),
                                    )
                                  : null,
                              icon: Icon(
                                Icons.circle,
                                color: colorFromRgb(preset.color),
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      Text(
                        'Яскравість',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Text('${(brightness * 100).round()}%'),
                    ],
                  ),
                  Slider(
                    value: brightness,
                    divisions: 100,
                    onChanged: connected
                        ? (value) => setState(() => _previewBrightness = value)
                        : null,
                    onChangeEnd: connected
                        ? (value) {
                            setState(() => _previewBrightness = null);
                            unawaited(_dispatch(SetBrightness(value)));
                          }
                        : null,
                  ),
                  Text(
                    'Переданий стан зберігається локально. BLE-відповідь не є підтвердженням, що стрічка фізично застосувала значення.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dispatch(LightingCommand command) async {
    await ref
        .read(deviceControlsProvider.notifier)
        .dispatch(widget.appDeviceId, command);
  }

  static String _deviceStatus(DebugDevice? device) {
    if (device == null) return 'Девайс недоступний';
    return deviceStatusLabel(device.status);
  }
}

class _ColorPreset {
  const _ColorPreset(this.label, this.color);

  final String label;
  final RgbColor color;
}

final _presets = <_ColorPreset>[
  _ColorPreset('Червоний', RgbColor(255, 0, 0)),
  _ColorPreset('Помаранчевий', RgbColor(255, 96, 0)),
  _ColorPreset('Жовтий', RgbColor(255, 210, 0)),
  _ColorPreset('Зелений', RgbColor(0, 255, 80)),
  _ColorPreset('Синій', RgbColor(0, 120, 255)),
  _ColorPreset('Фіолетовий', RgbColor(192, 0, 255)),
];
