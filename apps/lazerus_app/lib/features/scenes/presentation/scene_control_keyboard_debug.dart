import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazerus_app/features/control/presentation/color_utils.dart';
import 'package:lazerus_app/features/scenes/application/scene_controls_controller.dart';
import 'package:lazerus_app/features/scenes/domain/lighting_scene.dart';
import 'package:lazerus_app/shared/widgets/hardware_keyboard_listener.dart';
import 'package:lazerus_core/lazerus_core.dart';

@Deprecated('Only for debug purposes to test dynamic changes capabilities')
class SceneControlKeyboardDebug extends StatefulWidget {
  final LightingScene scene;
  final SceneControlsController sceneControls;
  final Widget child;
  const SceneControlKeyboardDebug({super.key, required this.scene, required this.sceneControls, required this.child});

  @override
  State<SceneControlKeyboardDebug> createState() => _SceneControlKeyboardDebugState();
}

class _SceneControlKeyboardDebugState extends State<SceneControlKeyboardDebug> {
  var _strobeMode = false;

  @override
  Widget build(BuildContext context) {
    return HardwareKeyboardListener(
      onKeyDown: (event) => onKeyDown(event, widget.scene),
      onKeyUp: (event) => onKeyUp(event, widget.scene),
      onKeyRepeat: (event) => KeyEventResult.handled,
      child: widget.child,
    );
  }

  int? getDigitIndex(KeyEvent event) {
    final key = event.logicalKey;

    const keys = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];

    const numpadKeys = [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];

    final index = keys.indexOf(key);
    if (index != -1) return index;

    final numpadIndex = numpadKeys.indexOf(key);
    return numpadIndex != -1 ? numpadIndex : null;
  }

  KeyEventResult onKeyDown(KeyEvent event, LightingScene scene) {
    final index = getDigitIndex(event);

    if (index != null) {
      if (_strobeMode) {
        _setSceneColor(scene, index, 9);
      }

      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      _setScenePower(scene, true);

      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult onKeyUp(KeyEvent event, LightingScene scene) {
    final index = getDigitIndex(event);
    if (index != null) {
      _setSceneColor(scene, _strobeMode ? null : index, 9);

      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      _setScenePower(scene, false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      _setScenePower(scene, true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      _setScenePower(scene, false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      _strobeMode = true;
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      _strobeMode = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _setSceneColor(LightingScene scene, int? color, [int maxColors = 7]) async {
    RgbColor next;
    if (color != null) {
      final value = color / maxColors;
      next = lotusHueColor(value);
    } else {
      next = RgbColor(0, 0, 0);
    }

    final control = scene.controlSlots
        .map((slot) => slot.control)
        .whereType<SceneCustomControl>()
        .firstWhere((e) => e.type == SceneControlType.colorSlider);
    await widget.sceneControls.commitColor(scene, control, next);
  }

  Future<void> _setScenePower(LightingScene scene, bool isOn) async {
    final control = scene.controlSlots
        .map((slot) => slot.control)
        .whereType<SceneCustomControl>()
        .firstWhere((e) => e.type == SceneControlType.toggle);
    await widget.sceneControls.setPower(scene, control, isOn);
  }
}
