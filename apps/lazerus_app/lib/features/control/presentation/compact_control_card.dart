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
  CompactControlCard({
    super.key,
    required this.target,
    this.onOpen,
    Iterable<LightingFeature> inputDrivenFeatures = const <LightingFeature>{},
    this.inputDrivenMessage,
  }) : inputDrivenFeatures = Set<LightingFeature>.unmodifiable(
         inputDrivenFeatures,
       );

  final LightingTarget target;
  final VoidCallback? onOpen;

  /// Parameters currently owned by a higher-priority live input. The normal
  /// Controls view leaves this empty; the Macro editor uses it after a routed
  /// input has emitted at least one value.
  final Set<LightingFeature> inputDrivenFeatures;
  final String? inputDrivenMessage;

  @override
  ConsumerState<CompactControlCard> createState() => _CompactControlCardState();
}

class _CompactControlCardState extends ConsumerState<CompactControlCard> {
  double? _previewBrightness;
  RgbColor? _previewColor;
  var _suppressCardOpen = false;

  @override
  void didUpdateWidget(covariant CompactControlCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final gainedInputOwner = widget.inputDrivenFeatures.any(
      (feature) => !oldWidget.inputDrivenFeatures.contains(feature),
    );
    if (!gainedInputOwner) return;

    // A drag can have one sampled command waiting in the shared ticker. Once
    // the macro has emitted for a parameter, discard that manual preview so a
    // delayed write cannot overtake the input-owned state.
    _previewBrightness = null;
    _previewColor = null;
    ref
        .read(lightingControlsProvider.notifier)
        .cancelReplaceable(widget.target.id);
  }

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
                      color: target.isGroup ? null : colorFromRgb(color),
                      gradient: target.isGroup
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
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
                    onPressed: isEnabled && !powerDriven
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
                    enabled: isEnabled && !colorDriven,
                    onInteractionStart: _suppressOpenForDrag,
                    onInteractionEnd: _clearDragOpenSuppression,
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
                    enabled: isEnabled && !brightnessDriven,
                    onInteractionStart: _suppressOpenForDrag,
                    onInteractionEnd: _clearDragOpenSuppression,
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
        .read(lightingControlsProvider.notifier)
        .dispatch(widget.target, command);
  }

  void _suppressOpenForDrag() {
    _suppressCardOpen = true;
  }

  void _clearDragOpenSuppression() {
    // InkWell's tap callback for the same pointer is delivered after the
    // Listener receives pointer-up. Clear on the next event turn so it is
    // suppressed, but a later ordinary card tap still opens details.
    scheduleMicrotask(() {
      if (mounted) {
        _suppressCardOpen = false;
      }
    });
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
