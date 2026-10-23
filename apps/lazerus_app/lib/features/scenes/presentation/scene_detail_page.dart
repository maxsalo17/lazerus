import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_app/features/scenes/presentation/scene_control_keyboard_debug.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../control/presentation/color_utils.dart';
import '../../control/presentation/compact_control_card.dart';
import '../../control/presentation/hold_value_control.dart';
import '../../control/presentation/target_detail_page.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import '../application/scene_controls_controller.dart';
import '../application/scenes_controller.dart';
import '../domain/lighting_scene.dart';
import 'scene_settings_page.dart';

/// Runtime surface for one persisted Scene. It renders no direct BLE code: the
/// custom cards issue typed requests to [SceneControlsController], while the
/// ordinary group/device cards keep using their existing control flow.
class SceneDetailPage extends ConsumerStatefulWidget {
  const SceneDetailPage({super.key, required this.sceneId});

  final String sceneId;

  @override
  ConsumerState<SceneDetailPage> createState() => _SceneDetailPageState();
}

class _SceneDetailPageState extends ConsumerState<SceneDetailPage> {
  late final SceneControlsController _sceneControls;

  @override
  void initState() {
    super.initState();
    // Keep the notifier rather than reading [ref] in dispose, where the
    // element is already deactivated.
    _sceneControls = ref.read(sceneControlsProvider.notifier);
  }

  @override
  void dispose() {
    _sceneControls.cancelScene(widget.sceneId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scenesState = ref.watch(scenesProvider);
    // These watches redraw the runtime view when connection, membership or
    // capabilities change. Resolution itself remains in the controller.
    ref.watch(debugDevicesProvider);
    ref.watch(customGroupsProvider);
    final scene = _findScene(scenesState.scenes, widget.sceneId);

    if (scenesState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (scene == null) {
      return const Scaffold(
        body: Center(child: Text('Scene більше не існує.')),
      );
    }

    final resolutions = ref.read(scenesProvider.notifier).resolveTargets(scene);
    final groups = resolutions
        .where(
          (resolution) => resolution.reference.type == SceneTargetType.group,
        )
        .toList(growable: false);
    final devices = resolutions
        .where(
          (resolution) => resolution.reference.type == SceneTargetType.device,
        )
        .toList(growable: false);
    final controls = scene.controlSlots
        .map((slot) => slot.control)
        .whereType<SceneCustomControl>()
        .toList(growable: false);

    return SceneControlKeyboardDebug(
      scene: scene,
      sceneControls: _sceneControls,
      child: Scaffold(
        appBar: AppBar(
          title: Text(scene.name),
          actions: <Widget>[
            IconButton(
              key: const Key('open-scene-settings'),
              tooltip: 'Scene Settings',
              onPressed: () => unawaited(_openSettings(scene)),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Custom controls',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (controls.isEmpty)
              const _EmptyDetailSection(
                text:
                    'У Scene ще немає custom controls. Додайте їх у Settings.',
              )
            else
              ...controls.expand(
                (control) => <Widget>[
                  SceneCustomControlCard(
                    key: ValueKey<String>(
                      'scene-runtime-control-${control.id}',
                    ),
                    scene: scene,
                    control: control,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            const SizedBox(height: 16),
            Text('Групи', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (groups.isEmpty)
              const _EmptyDetailSection(text: 'У Scene не додано груп.')
            else
              ...groups.expand(
                (resolution) => <Widget>[
                  _SceneResolvedTargetCard(
                    resolution: resolution,
                    onOpen: _openTargetDetails,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            const SizedBox(height: 16),
            Text('Девайси', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const _EmptyDetailSection(text: 'У Scene не додано девайсів.')
            else
              ...devices.expand(
                (resolution) => <Widget>[
                  _SceneResolvedTargetCard(
                    resolution: resolution,
                    onOpen: _openTargetDetails,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            const SizedBox(height: 28),
            Text(
              'Переданий стан зберігається локально. Успішний BLE write не є підтвердженням, що стрічка фізично застосувала значення.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings(LightingScene scene) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => SceneSettingsPage(scene: scene)),
    );
  }

  void _openTargetDetails(LightingTarget target) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => TargetDetailPage(target: target)),
    );
  }

  static LightingScene? _findScene(
    Iterable<LightingScene> scenes,
    String sceneId,
  ) {
    for (final scene in scenes) {
      if (scene.id == sceneId) {
        return scene;
      }
    }
    return null;
  }
}

class SceneCustomControlCard extends ConsumerStatefulWidget {
  const SceneCustomControlCard({
    super.key,
    required this.scene,
    required this.control,
  });

  final LightingScene scene;
  final SceneCustomControl control;

  @override
  ConsumerState<SceneCustomControlCard> createState() =>
      _SceneCustomControlCardState();
}

class _SceneCustomControlCardState
    extends ConsumerState<SceneCustomControlCard> {
  double? _previewBrightness;
  RgbColor? _previewColor;

  @override
  Widget build(BuildContext context) {
    // The notifier resolves from these live values. Watching here keeps the
    // presentation reactive without moving transport logic into the widget.
    ref.watch(debugDevicesProvider);
    ref.watch(customGroupsProvider);
    ref.watch(sceneControlsProvider);
    final controller = ref.read(sceneControlsProvider.notifier);
    final view = controller.viewStateFor(widget.scene, widget.control);
    // Slider previews are intentionally still interactive while the replaceable
    // ticker has a pending or in-flight write. Disabling here would terminate a
    // long-press gesture before its release can flush the latest value.
    final enabled = view.plan.canDispatch;
    final brightness = _previewBrightness ?? view.controlState.brightness;
    final color = _previewColor ?? view.controlState.color;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(widget.control.type)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _titleFor(widget.control),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        view.plan.canDispatch
                            ? '${view.status.targetDeviceCount} ${_deviceWord(view.status.targetDeviceCount)} готово'
                            : 'Немає доступних девайсів',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (view.status.isDispatching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _ControlBody(
              scene: widget.scene,
              control: widget.control,
              controller: controller,
              enabled: enabled,
              power: view.controlState.power ?? false,
              brightness: brightness,
              color: color,
              onPreviewBrightness: (value) {
                setState(() => _previewBrightness = value);
                controller.previewBrightness(
                  widget.scene,
                  widget.control,
                  value,
                );
              },
              onCommitBrightness: (value) {
                setState(() => _previewBrightness = null);
                unawaited(
                  controller.commitBrightness(
                    widget.scene,
                    widget.control,
                    value,
                  ),
                );
              },
              onPreviewColor: (value) {
                final next = lotusHueColor(value);
                setState(() => _previewColor = next);
                controller.previewColor(widget.scene, widget.control, next);
              },
              onCommitColor: (value) {
                final next = lotusHueColor(value);

                setState(() => _previewColor = null);

                unawaited(
                  controller.commitColor(widget.scene, widget.control, next),
                );
              },
            ),
            if (view.status.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              _SceneControlIssues(issues: view.status.issues),
            ],
            if (view.status.lastError case final error?
                when error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              _SceneControlError(message: error),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(SceneControlType type) => switch (type) {
    SceneControlType.toggle => Icons.power_settings_new,
    SceneControlType.brightnessSlider => Icons.brightness_6_outlined,
    SceneControlType.colorSlider => Icons.palette_outlined,
  };

  static String _titleFor(SceneCustomControl control) =>
      control.label ??
      switch (control.type) {
        SceneControlType.toggle => 'Живлення',
        SceneControlType.brightnessSlider => 'Яскравість',
        SceneControlType.colorSlider => 'Колір',
      };

  static String _deviceWord(int value) => switch (value) {
    1 => 'девайс',
    >= 2 && <= 4 => 'девайси',
    _ => 'девайсів',
  };
}

class _ControlBody extends StatelessWidget {
  const _ControlBody({
    required this.scene,
    required this.control,
    required this.controller,
    required this.enabled,
    required this.power,
    required this.brightness,
    required this.color,
    required this.onPreviewBrightness,
    required this.onCommitBrightness,
    required this.onPreviewColor,
    required this.onCommitColor,
  });

  final LightingScene scene;
  final SceneCustomControl control;
  final SceneControlsController controller;
  final bool enabled;
  final bool power;
  final double brightness;
  final RgbColor color;
  final ValueChanged<double> onPreviewBrightness;
  final ValueChanged<double> onCommitBrightness;
  final ValueChanged<double> onPreviewColor;
  final ValueChanged<double> onCommitColor;

  @override
  Widget build(BuildContext context) {
    return switch (control.type) {
      SceneControlType.toggle => SwitchListTile.adaptive(
        key: Key('scene-control-${control.id}-toggle'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Живлення'),
        value: power,
        onChanged: enabled
            ? (value) => unawaited(controller.setPower(scene, control, value))
            : null,
      ),
      SceneControlType.brightnessSlider => HoldValueControl(
        key: Key('scene-control-${control.id}-brightness'),
        kind: HoldValueKind.brightness,
        value: brightness,
        label: '${(brightness * 100).round()}%',
        brightnessColor: colorFromRgb(color),
        enabled: enabled,
        onPreview: onPreviewBrightness,
        onCommit: onCommitBrightness,
      ),
      SceneControlType.colorSlider => HoldValueControl(
        key: Key('scene-control-${control.id}-color'),
        kind: HoldValueKind.hue,
        value: lotusHueValueFor(color),
        label: 'Колір',
        brightnessColor: colorFromRgb(color),
        enabled: enabled,
        onPreview: onPreviewColor,
        onCommit: onCommitColor,
      ),
    };
  }
}

class _SceneResolvedTargetCard extends StatelessWidget {
  const _SceneResolvedTargetCard({
    required this.resolution,
    required this.onOpen,
  });

  final SceneTargetResolution resolution;
  final ValueChanged<LightingTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    final target = resolution.target;
    if (target == null) {
      return _UnavailableSceneTarget(resolution: resolution);
    }
    return CompactControlCard(
      key: ValueKey<String>('scene-target-control-${target.id}'),
      target: target,
      onOpen: () => onOpen(target),
    );
  }
}

class _UnavailableSceneTarget extends StatelessWidget {
  const _UnavailableSceneTarget({required this.resolution});

  final SceneTargetResolution resolution;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        key: Key(
          'scene-unavailable-${resolution.reference.type.name}-${resolution.reference.targetId}',
        ),
        leading: const Icon(Icons.link_off),
        title: Text(
          resolution.reference.type == SceneTargetType.group
              ? 'Недоступна група'
              : 'Недоступний девайс',
        ),
        subtitle: Text(
          resolution.detail ?? 'Потрібне повторне виявлення або relink.',
        ),
      ),
    );
  }
}

class _EmptyDetailSection extends StatelessWidget {
  const _EmptyDetailSection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
    );
  }
}

class _SceneControlIssues extends StatelessWidget {
  const _SceneControlIssues({required this.issues});

  final List<SceneControlBindingIssue> issues;

  @override
  Widget build(BuildContext context) {
    final details = issues.map((issue) => issue.detail).toSet().join('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(details)),
        ],
      ),
    );
  }
}

class _SceneControlError extends StatelessWidget {
  const _SceneControlError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
