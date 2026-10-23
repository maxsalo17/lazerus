import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/group_targets.dart';
import 'replaceable_command_ticker.dart';

final lightingControlsProvider =
    NotifierProvider<
      LightingControlsController,
      Map<String, TargetControlState>
    >(LightingControlsController.new);

class TargetControlState {
  TargetControlState({
    this.power,
    RgbColor? color,
    this.brightness = 1,
    Iterable<RgbColor> displayColors = const <RgbColor>[],
  }) : color = color ?? RgbColor(255, 0, 0),
       displayColors = List<RgbColor>.unmodifiable(displayColors);

  final bool? power;
  final RgbColor color;
  final double brightness;

  /// Known member colours in a deterministic order. For a group, presentation
  /// renders this as a gradient instead of pretending every member has the
  /// representative [color].
  final List<RgbColor> displayColors;

  factory TargetControlState.fromTarget(
    LightingTarget target,
    Map<String, DebugDevice> devices,
  ) {
    final members =
        target.memberDeviceIds
            .map((deviceId) => devices[deviceId])
            .whereType<DebugDevice>()
            .toList(growable: false)
          ..sort((left, right) {
            final leftName = left.endpoint.displayName ?? left.appDeviceId;
            final rightName = right.endpoint.displayName ?? right.appDeviceId;
            return leftName.compareTo(rightName);
          });
    if (members.isEmpty) {
      return TargetControlState();
    }

    final states = members
        .map((device) => device.lastKnownState)
        .toList(growable: false);
    final colors = states
        .map((state) => state.color)
        .whereType<RgbColor>()
        .toList(growable: false);
    final powers = states
        .map((state) => state.power)
        .whereType<bool>()
        .toList(growable: false);
    final brightnesses = states
        .map((state) => state.brightness)
        .whereType<double>()
        .toList(growable: false);

    return TargetControlState(
      // A mixed group is considered on when one or more members are on, so the
      // compact toggle gives the useful next action: turn the group off.
      power: powers.isEmpty ? null : powers.any((value) => value),
      color: colors.isEmpty ? null : colors.first,
      brightness: brightnesses.isEmpty
          ? 1
          : brightnesses.reduce((sum, value) => sum + value) /
                brightnesses.length,
      displayColors: colors,
    );
  }
}

/// Sends a common lighting command to an individual device or every currently
/// available member of a group. The device controller still serializes writes
/// per device and reports a result for every target.
class LightingControlsController
    extends Notifier<Map<String, TargetControlState>> {
  final Map<String, ReplaceableCommandTicker<_LiveCommand>> _liveTickers =
      <String, ReplaceableCommandTicker<_LiveCommand>>{};

  @override
  Map<String, TargetControlState> build() {
    ref.onDispose(() {
      for (final ticker in _liveTickers.values) {
        ticker.dispose();
      }
      _liveTickers.clear();
    });
    return const <String, TargetControlState>{};
  }

  TargetControlState stateFor(LightingTarget target) {
    return TargetControlState.fromTarget(
      target,
      ref.read(debugDevicesProvider).devices,
    );
  }

  Future<List<CommandResult>> dispatch(
    LightingTarget target,
    LightingCommand command,
  ) async {
    return _send(target, command);
  }

  /// Samples drag input at 10 Hz and drops stale intermediate values. Gesture
  /// preview remains in the widget; accepted writes update the shared per-device
  /// local state through the device controller.
  void queueReplaceable(LightingTarget target, LightingCommand command) {
    final ticker = _liveTickers.putIfAbsent(
      target.id,
      () => ReplaceableCommandTicker<_LiveCommand>(
        onEmit: (pending) async {
          await _send(pending.target, pending.command);
        },
      ),
    );
    ticker.push(_LiveCommand(target, command));
  }

  /// Called on gesture release so the final drag value is not delayed by the
  /// sampling interval.
  Future<void> flushReplaceable(String targetId) async {
    await _liveTickers[targetId]?.flush();
  }

  /// Drops a pending preview when an ephemeral editor closes. This prevents a
  /// late command from being emitted after its temporary mapping was removed.
  void cancelReplaceable(String targetId) {
    _liveTickers.remove(targetId)?.dispose();
  }

  Future<List<CommandResult>> _send(
    LightingTarget target,
    LightingCommand command,
  ) async {
    if (target.memberDeviceIds.isEmpty) {
      return <CommandResult>[
        CommandResult.rejected(command, 'This group has no available devices.'),
      ];
    }
    final results = await ref
        .read(debugDevicesProvider.notifier)
        .executeForDevices(target.memberDeviceIds, command);
    return results;
  }
}

class _LiveCommand {
  const _LiveCommand(this.target, this.command);

  final LightingTarget target;
  final LightingCommand command;
}
