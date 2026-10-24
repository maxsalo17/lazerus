import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import 'replaceable_command_ticker.dart';

final deviceControlsProvider = NotifierProvider<DeviceControlsController, Map<String, DeviceControlState>>(
  DeviceControlsController.new,
);

/// Locally tracked desired state for one physical device.
final class DeviceControlState {
  DeviceControlState({this.power, RgbColor? color, this.brightness = 1}) : color = color ?? RgbColor(255, 0, 0);

  final bool? power;
  final RgbColor color;
  final double brightness;

  factory DeviceControlState.fromDevice(DebugDevice? device) {
    final desired = device?.lastKnownState;
    return DeviceControlState(power: desired?.power, color: desired?.color, brightness: desired?.brightness ?? 1);
  }
}

/// Sends direct per-device lighting commands.
///
/// Calibration may use one operation ID for several explicitly selected
/// devices, but this controller has no persisted or derived multi-device
/// abstraction.
final class DeviceControlsController extends Notifier<Map<String, DeviceControlState>> {
  final Map<String, ReplaceableCommandTicker<_LiveCommand>> _liveTickers = <String, ReplaceableCommandTicker<_LiveCommand>>{};

  @override
  Map<String, DeviceControlState> build() {
    ref.onDispose(() {
      for (final ticker in _liveTickers.values) {
        ticker.dispose();
      }
      _liveTickers.clear();
    });
    return const <String, DeviceControlState>{};
  }

  DeviceControlState stateFor(String appDeviceId) =>
      DeviceControlState.fromDevice(ref.read(debugDevicesProvider).devices[appDeviceId]);

  Future<List<CommandResult>> dispatch(String appDeviceId, LightingCommand command) => _send(<String>{appDeviceId}, command);

  /// Samples drag input at 10 Hz and drops stale intermediate values.
  void queueReplaceable({required String operationId, required Iterable<String> appDeviceIds, required LightingCommand command}) {
    final ticker = _liveTickers.putIfAbsent(
      operationId,
      () => ReplaceableCommandTicker<_LiveCommand>(
        onEmit: (pending) async {
          await _send(pending.appDeviceIds, pending.command);
        },
      ),
    );
    ticker.push(_LiveCommand(appDeviceIds, command));
  }

  Future<void> flushReplaceable(String operationId) async {
    await _liveTickers[operationId]?.flush();
  }

  void cancelReplaceable(String operationId) {
    _liveTickers.remove(operationId)?.dispose();
  }

  Future<List<CommandResult>> _send(Iterable<String> appDeviceIds, LightingCommand command) async {
    final deviceIds = appDeviceIds.toSet();
    if (deviceIds.isEmpty) {
      return <CommandResult>[CommandResult.rejected(command, 'No selected devices are available.')];
    }
    return ref.read(debugDevicesProvider.notifier).executeForDevices(deviceIds, command);
  }
}

final class _LiveCommand {
  _LiveCommand(Iterable<String> appDeviceIds, this.command) : appDeviceIds = Set<String>.unmodifiable(appDeviceIds);

  final Set<String> appDeviceIds;
  final LightingCommand command;
}
