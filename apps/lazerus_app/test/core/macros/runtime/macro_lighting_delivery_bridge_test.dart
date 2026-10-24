import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/runtime/macro_lighting_delivery_bridge.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'drops newer values while a write is in flight and accepts a later value',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final gateway = _BlockingGateway(firstStarted, releaseFirst);
      final bridge = MacroLightingDeliveryBridge(
        targetResolver: const _Resolver(<String>{'device-a'}),
        deviceGateway: gateway,
      );
      final statuses = <MacroLightingDeliveryStatus>[];
      final subscription = bridge.statuses.listen(statuses.add);

      bridge.submit(_brightnessIntent(0.1, sequence: 1));
      await firstStarted.future;
      bridge.submit(_brightnessIntent(0.4, sequence: 2));
      bridge.submit(_brightnessIntent(0.8, sequence: 3));
      releaseFirst.complete();
      await bridge.drain();
      bridge.submit(_brightnessIntent(0.9, sequence: 4));
      await bridge.drain();

      expect(
        gateway.commands.map((command) => command.state.brightness),
        <double?>[0.1, 0.9],
      );
      expect(
        statuses.where(
          (status) => status.outcome == MacroLightingDeliveryOutcome.dropped,
        ),
        hasLength(2),
      );
      final transmitted = statuses.lastWhere(
        (status) => status.outcome == MacroLightingDeliveryOutcome.transmitted,
      );
      expect(transmitted.transportOutcome, CommandOutcome.transmitted);
      // The bridge intentionally exposes the transport boundary, not a claim
      // that the controller applied the command.
      expect(transmitted.outcome, MacroLightingDeliveryOutcome.transmitted);

      await subscription.cancel();
      await bridge.close();
    },
  );

  test(
    'releases the device after failure without reviving dropped values',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final gateway = _BlockingGateway(
        firstStarted,
        releaseFirst,
        firstOutcome: CommandOutcome.failed,
      );
      final bridge = MacroLightingDeliveryBridge(
        targetResolver: const _Resolver(<String>{'device-a'}),
        deviceGateway: gateway,
      );
      final statuses = <MacroLightingDeliveryStatus>[];
      final subscription = bridge.statuses.listen(statuses.add);

      bridge.submit(_brightnessIntent(0.1, sequence: 1));
      await firstStarted.future;
      bridge.submit(_brightnessIntent(0.4, sequence: 2));
      releaseFirst.complete();
      await bridge.drain();
      bridge.submit(_brightnessIntent(0.9, sequence: 3));
      await bridge.drain();

      expect(
        gateway.commands.map((command) => command.state.brightness),
        <double?>[0.1, 0.9],
      );
      expect(
        statuses.where(
          (status) => status.outcome == MacroLightingDeliveryOutcome.dropped,
        ),
        hasLength(1),
      );
      expect(
        statuses.where(
          (status) => status.outcome == MacroLightingDeliveryOutcome.failed,
        ),
        hasLength(1),
      );

      await subscription.cancel();
      await bridge.close();
    },
  );

  test(
    'maps a typed HSV color intent to the common RGB lighting state',
    () async {
      final gateway = _ImmediateGateway();
      final bridge = MacroLightingDeliveryBridge(
        targetResolver: const _Resolver(<String>{'device-a'}),
        deviceGateway: gateway,
      );

      bridge.submit(
        MacroLightingIntent(
          macroId: 'macro',
          bindingId: 'color',
          targetKind: MacroTargetKind.device,
          targetId: 'device-a',
          parameter: MacroTargetParameter.color,
          value: TriggerHsvValue(hue: 0, saturation: 1, value: 1),
          timestamp: Duration.zero,
          sequence: 0,
        ),
      );
      await bridge.drain();

      expect(gateway.commands.single.state.color, RgbColor(255, 0, 0));
      await bridge.close();
    },
  );

  test(
    'restores the pre-macro desired state only for a changed device',
    () async {
      final beforeMacro = DesiredLightingState(
        power: true,
        color: RgbColor(0, 120, 255),
        brightness: 0.35,
      );
      final gateway = _ImmediateGateway(currentState: beforeMacro);
      final bridge = MacroLightingDeliveryBridge(
        targetResolver: const _Resolver(<String>{'device-a'}),
        deviceGateway: gateway,
      );
      bridge.captureStatesBeforeMacroWrites(<MacroTargetBinding>[
        MacroTargetBinding(
          id: 'brightness-binding',
          sourcePortId: 'source.level',
          targetKind: MacroTargetKind.device,
          targetId: 'device-a',
          parameter: MacroTargetParameter.brightness,
        ),
      ]);

      bridge.submit(_brightnessIntent(0.9, sequence: 1));
      await bridge.drain();
      await bridge.restoreChangedDeviceStates();

      expect(gateway.commands, hasLength(2));
      expect(gateway.commands.first.state.brightness, 0.9);
      expect(gateway.commands.last.state.power, beforeMacro.power);
      expect(gateway.commands.last.state.color, beforeMacro.color);
      expect(gateway.commands.last.state.brightness, beforeMacro.brightness);
      await bridge.close();
    },
  );
}

MacroLightingIntent _brightnessIntent(double value, {required int sequence}) =>
    MacroLightingIntent(
      macroId: 'macro',
      bindingId: 'brightness',
      targetKind: MacroTargetKind.device,
      targetId: 'device-a',
      parameter: MacroTargetParameter.brightness,
      value: TriggerLevelValue(value),
      timestamp: Duration(milliseconds: sequence),
      sequence: sequence,
    );

final class _Resolver implements MacroLightingTargetResolver {
  const _Resolver(this.deviceIds);

  final Set<String> deviceIds;

  @override
  Iterable<String> resolve({
    required MacroTargetKind targetKind,
    required String targetId,
  }) => deviceIds;
}

final class _BlockingGateway implements MacroLightingDeviceGateway {
  _BlockingGateway(
    this.firstStarted,
    this.releaseFirst, {
    this.firstOutcome = CommandOutcome.transmitted,
  });

  final Completer<void> firstStarted;
  final Completer<void> releaseFirst;
  final CommandOutcome firstOutcome;
  final List<ApplyLightingState> commands = <ApplyLightingState>[];

  @override
  DesiredLightingState? currentDesiredState(String appDeviceId) => null;

  @override
  bool canDispatch(String appDeviceId, DesiredLightingState state) => true;

  @override
  Future<CommandResult> dispatch(
    String appDeviceId,
    ApplyLightingState command,
  ) async {
    commands.add(command);
    if (commands.length == 1) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    return CommandResult(
      command: command,
      outcome: commands.length == 1 ? firstOutcome : CommandOutcome.transmitted,
    );
  }
}

final class _ImmediateGateway implements MacroLightingDeviceGateway {
  _ImmediateGateway({this.currentState});

  final DesiredLightingState? currentState;
  final List<ApplyLightingState> commands = <ApplyLightingState>[];

  @override
  DesiredLightingState? currentDesiredState(String appDeviceId) => currentState;

  @override
  bool canDispatch(String appDeviceId, DesiredLightingState state) => true;

  @override
  Future<CommandResult> dispatch(
    String appDeviceId,
    ApplyLightingState command,
  ) async {
    commands.add(command);
    return CommandResult(command: command, outcome: CommandOutcome.transmitted);
  }
}
