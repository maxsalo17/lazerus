import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../application/device_controls_controller.dart';
import 'color_utils.dart';
import 'hold_value_control.dart';

/// Compact controls for one physical device.
///
/// It is reused in the Macro editor only for a device target node; routed
/// inputs disable the matching manual controls after their first value.
class DeviceControlCard extends ConsumerStatefulWidget {
  DeviceControlCard({
    super.key,
    required this.appDeviceId,
    required this.deviceName,
    this.onOpen,
    Iterable<LightingFeature> inputDrivenFeatures = const <LightingFeature>{},
    this.inputDrivenMessage,
  }) : inputDrivenFeatures = Set<LightingFeature>.unmodifiable(
         inputDrivenFeatures,
       );

  final String appDeviceId;
  final String deviceName;
  final VoidCallback? onOpen;
  final Set<LightingFeature> inputDrivenFeatures;
  final String? inputDrivenMessage;

  @override
  ConsumerState<DeviceControlCard> createState() => _DeviceControlCardState();
}

class _DeviceControlCardState extends ConsumerState<DeviceControlCard> {
  double? _previewBrightness;
  RgbColor? _previewColor;
  var _suppressCardOpen = false;

  @override
  void didUpdateWidget(covariant DeviceControlCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final gainedInputOwner = widget.inputDrivenFeatures.any(
      (feature) => !oldWidget.inputDrivenFeatures.contains(feature),
    );
    if (!gainedInputOwner) return;

    _previewBrightness = null;
    _previewColor = null;
    ref
        .read(deviceControlsProvider.notifier)
        .cancelReplaceable(widget.appDeviceId);
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(debugDevicesProvider).devices[widget.appDeviceId];
    final controls = ref.read(deviceControlsProvider.notifier);
    final state = controls.stateFor(widget.appDeviceId);
    final brightness = _previewBrightness ?? state.brightness;
    final color = _previewColor ?? state.color;
    final isEnabled = device?.status == DebugDeviceConnectionStatus.connected;
    final isOn = state.power ?? false;
    final powerDriven = widget.inputDrivenFeatures.contains(
      LightingFeature.power,
    );
    final colorDriven =
        widget.inputDrivenFeatures.contains(LightingFeature.rgb) ||
        widget.inputDrivenFeatures.contains(LightingFeature.rgbw);
    final brightnessDriven = widget.inputDrivenFeatures.contains(
      LightingFeature.brightness,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen == null
            ? null
            : () {
                if (_suppressCardOpen) {
                  _suppressCardOpen = false;
                  return;
                }
                widget.onOpen!.call();
              },
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
                      color: colorFromRgb(color),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          _deviceConnectionText(device),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (isOn)
                    IconButton.filled(
                      tooltip: 'Вимкнути',
                      onPressed: isEnabled && !powerDriven
                          ? () => unawaited(_dispatch(SetPower(false)))
                          : null,
                      icon: const Icon(Icons.power_settings_new),
                    )
                  else
                    IconButton.outlined(
                      tooltip: 'Увімкнути',
                      onPressed: isEnabled && !powerDriven
                          ? () => unawaited(_dispatch(SetPower(true)))
                          : null,
                      icon: const Icon(Icons.power_settings_new),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  HoldValueControl(
                    key: Key('${widget.appDeviceId}-hold-color'),
                    kind: HoldValueKind.hue,
                    value: lotusHueValueFor(color),
                    label: 'Колір',
                    brightnessColor: colorFromRgb(color),
                    enabled: isEnabled && !colorDriven,
                    onInteractionStart: _suppressOpenForDrag,
                    onInteractionEnd: _clearDragOpenSuppression,
                    onPreview: (value) {
                      final selected = lotusHueColor(value);
                      setState(() => _previewColor = selected);
                      controls.queueReplaceable(
                        operationId: widget.appDeviceId,
                        appDeviceIds: <String>{widget.appDeviceId},
                        command: SetColor(selected),
                      );
                    },
                    onCommit: isEnabled
                        ? (value) {
                            final selected = lotusHueColor(value);
                            setState(() => _previewColor = null);
                            controls.queueReplaceable(
                              operationId: widget.appDeviceId,
                              appDeviceIds: <String>{widget.appDeviceId},
                              command: SetColor(selected),
                            );
                            unawaited(
                              controls.flushReplaceable(widget.appDeviceId),
                            );
                          }
                        : (_) => setState(() => _previewColor = null),
                  ),
                  const SizedBox(width: 8),
                  HoldValueControl(
                    key: Key('${widget.appDeviceId}-hold-brightness'),
                    kind: HoldValueKind.brightness,
                    value: brightness,
                    label: '${(brightness * 100).round()}%',
                    brightnessColor: colorFromRgb(color),
                    enabled: isEnabled && !brightnessDriven,
                    onInteractionStart: _suppressOpenForDrag,
                    onInteractionEnd: _clearDragOpenSuppression,
                    onPreview: (value) {
                      setState(() => _previewBrightness = value);
                      controls.queueReplaceable(
                        operationId: widget.appDeviceId,
                        appDeviceIds: <String>{widget.appDeviceId},
                        command: SetBrightness(value),
                      );
                    },
                    onCommit: isEnabled
                        ? (value) {
                            setState(() => _previewBrightness = null);
                            controls.queueReplaceable(
                              operationId: widget.appDeviceId,
                              appDeviceIds: <String>{widget.appDeviceId},
                              command: SetBrightness(value),
                            );
                            unawaited(
                              controls.flushReplaceable(widget.appDeviceId),
                            );
                          }
                        : (_) => setState(() => _previewBrightness = null),
                  ),
                  const Spacer(),
                  if (widget.onOpen != null)
                    const Icon(Icons.open_in_new, size: 18),
                ],
              ),
              if (widget.inputDrivenFeatures.isNotEmpty &&
                  widget.inputDrivenMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  widget.inputDrivenMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dispatch(LightingCommand command) async {
    await ref
        .read(deviceControlsProvider.notifier)
        .dispatch(widget.appDeviceId, command);
  }

  void _suppressOpenForDrag() {
    _suppressCardOpen = true;
  }

  void _clearDragOpenSuppression() {
    scheduleMicrotask(() {
      if (mounted) {
        _suppressCardOpen = false;
      }
    });
  }

  static String _deviceConnectionText(DebugDevice? device) {
    if (device == null) return 'Недоступний';
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
