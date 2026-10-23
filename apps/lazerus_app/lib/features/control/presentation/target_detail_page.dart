import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../devices/presentation/device_display.dart';
import '../../groups/application/group_targets.dart';
import '../application/lighting_controls_controller.dart';
import 'color_utils.dart';

class TargetDetailPage extends ConsumerStatefulWidget {
  const TargetDetailPage({super.key, required this.target});

  final LightingTarget target;

  @override
  ConsumerState<TargetDetailPage> createState() => _TargetDetailPageState();
}

class _TargetDetailPageState extends ConsumerState<TargetDetailPage> {
  double? _previewBrightness;

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final devices = ref.watch(debugDevicesProvider).devices;
    final controlNotifier = ref.read(lightingControlsProvider.notifier);
    final controlState = controlNotifier.stateFor(target);
    final brightness = _previewBrightness ?? controlState.brightness;
    final connectedDevices = target.memberDeviceIds
        .map((id) => devices[id])
        .whereType<DebugDevice>()
        .where(
          (device) => device.status == DebugDeviceConnectionStatus.connected,
        )
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(target.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    target.isGroup
                        ? '$connectedDevices з ${target.memberDeviceIds.length} девайсів підключено'
                        : _singleDeviceStatus(devices[target.id]),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Живлення'),
                    value: controlState.power ?? false,
                    onChanged: connectedDevices == 0
                        ? null
                        : (enabled) => unawaited(_dispatch(SetPower(enabled))),
                  ),
                  const Divider(),
                  Text('Колір', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _presets
                        .map((preset) {
                          return Tooltip(
                            message: preset.label,
                            child: IconButton.filledTonal(
                              onPressed: connectedDevices == 0
                                  ? null
                                  : () => unawaited(
                                      _dispatch(SetColor(preset.color)),
                                    ),
                              icon: Icon(
                                Icons.circle,
                                color: colorFromRgb(preset.color),
                              ),
                            ),
                          );
                        })
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
                    onChanged: connectedDevices == 0
                        ? null
                        : (value) => setState(() => _previewBrightness = value),
                    onChangeEnd: connectedDevices == 0
                        ? null
                        : (value) {
                            setState(() => _previewBrightness = null);
                            unawaited(_dispatch(SetBrightness(value)));
                          },
                  ),
                  Text(
                    'Переданий стан зберігається локально. BLE-відповідь не є підтвердженням, що стрічка фізично застосувала значення.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (target.isGroup) ...<Widget>[
            const SizedBox(height: 20),
            Text('Учасники', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...target.memberDeviceIds.map((deviceId) {
              final device = devices[deviceId];
              if (device == null) {
                return const ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Недоступний девайс'),
                  subtitle: Text('Потрібне повторне виявлення або relink.'),
                );
              }
              return ListTile(
                leading: Icon(deviceStatusIcon(device.status)),
                title: Text(device.endpoint.displayName ?? 'Без назви'),
                subtitle: Text(deviceStatusLabel(device.status)),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _dispatch(LightingCommand command) async {
    await ref
        .read(lightingControlsProvider.notifier)
        .dispatch(widget.target, command);
  }

  static String _singleDeviceStatus(DebugDevice? device) {
    if (device == null) {
      return 'Девайс недоступний';
    }
    return deviceStatusLabel(device.status);
  }
}

class _ColorPreset {
  const _ColorPreset(this.label, this.color);

  final String label;
  final RgbColor color;
}

final List<_ColorPreset> _presets = <_ColorPreset>[
  _ColorPreset('Червоний', RgbColor(255, 0, 0)),
  _ColorPreset('Помаранчевий', RgbColor(255, 96, 0)),
  _ColorPreset('Жовтий', RgbColor(255, 210, 0)),
  _ColorPreset('Зелений', RgbColor(0, 255, 80)),
  _ColorPreset('Синій', RgbColor(0, 120, 255)),
  _ColorPreset('Фіолетовий', RgbColor(192, 0, 255)),
];
