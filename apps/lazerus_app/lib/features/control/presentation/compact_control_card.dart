import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/group_targets.dart';
import '../application/lighting_controls_controller.dart';
import 'color_utils.dart';
import 'hold_value_control.dart';

class CompactControlCard extends ConsumerStatefulWidget {
  const CompactControlCard({super.key, required this.target, this.onOpen});

  final LightingTarget target;
  final VoidCallback? onOpen;

  @override
  ConsumerState<CompactControlCard> createState() => _CompactControlCardState();
}

class _CompactControlCardState extends ConsumerState<CompactControlCard> {
  double? _previewBrightness;
  RgbColor? _previewColor;

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final devices = ref.watch(debugDevicesProvider).devices;
    final controls = ref.read(lightingControlsProvider.notifier);
    final state = controls.stateFor(target);
    final brightness = _previewBrightness ?? state.brightness;
    final color = _previewColor ?? state.color;
    final swatchColors = state.displayColors.isEmpty
        ? <RgbColor>[color, color]
        : state.displayColors.length == 1
        ? <RgbColor>[state.displayColors.single, state.displayColors.single]
        : state.displayColors;
    final connectedCount = target.memberDeviceIds
        .map((deviceId) => devices[deviceId])
        .whereType<DebugDevice>()
        .where(
          (device) => device.status == DebugDeviceConnectionStatus.connected,
        )
        .length;
    final isEnabled = connectedCount > 0;
    final isOn = state.power ?? false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 36,
                    decoration: BoxDecoration(
                      color: target.isGroup ? null : colorFromRgb(color),
                      gradient: target.isGroup
                          ? LinearGradient(
                              colors: swatchColors
                                  .map(colorFromRgb)
                                  .toList(growable: false),
                            )
                          : null,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          target.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          target.isGroup
                              ? '$connectedCount з ${target.memberDeviceIds.length} підключено'
                              : _deviceConnectionText(devices[target.id]),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: isOn ? 'Вимкнути' : 'Увімкнути',
                    onPressed: isEnabled
                        ? () => unawaited(_dispatch(SetPower(!isOn)))
                        : null,
                    icon: Icon(isOn ? Icons.power_settings_new : Icons.power),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  HoldValueControl(
                    key: Key('${target.id}-hold-color'),
                    kind: HoldValueKind.hue,
                    value: lotusHueValueFor(color),
                    label: 'Колір',
                    brightnessColor: colorFromRgb(color),
                    enabled: isEnabled,
                    onPreview: (value) {
                      final selected = lotusHueColor(value);
                      setState(() => _previewColor = selected);
                      controls.queueReplaceable(target, SetColor(selected));
                    },
                    onCommit: isEnabled
                        ? (value) {
                            final selected = lotusHueColor(value);
                            setState(() => _previewColor = null);
                            controls.queueReplaceable(
                              target,
                              SetColor(selected),
                            );
                            unawaited(controls.flushReplaceable(target.id));
                          }
                        : (_) => setState(() => _previewColor = null),
                  ),
                  const SizedBox(width: 8),
                  HoldValueControl(
                    key: Key('${target.id}-hold-brightness'),
                    kind: HoldValueKind.brightness,
                    value: brightness,
                    label: '${(brightness * 100).round()}%',
                    brightnessColor: colorFromRgb(color),
                    enabled: isEnabled,
                    onPreview: (value) {
                      setState(() => _previewBrightness = value);
                      controls.queueReplaceable(target, SetBrightness(value));
                    },
                    onCommit: isEnabled
                        ? (value) {
                            setState(() => _previewBrightness = null);
                            controls.queueReplaceable(
                              target,
                              SetBrightness(value),
                            );
                            unawaited(controls.flushReplaceable(target.id));
                          }
                        : (_) => setState(() => _previewBrightness = null),
                  ),
                  const Spacer(),
                  const Icon(Icons.open_in_new, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dispatch(LightingCommand command) async {
    await ref
        .read(lightingControlsProvider.notifier)
        .dispatch(widget.target, command);
  }

  static String _deviceConnectionText(DebugDevice? device) {
    if (device == null) {
      return 'Недоступний';
    }
    return switch (device.status) {
      DebugDeviceConnectionStatus.connected => 'Підключено',
      DebugDeviceConnectionStatus.connecting => 'Підключення…',
      DebugDeviceConnectionStatus.disconnected => 'Від’єднано',
      DebugDeviceConnectionStatus.error => 'Помилка',
      DebugDeviceConnectionStatus.unsupported => 'Не підтримується',
      DebugDeviceConnectionStatus.discovered => 'Знайдено',
    };
  }
}
