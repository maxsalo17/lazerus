import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/control/presentation/compact_control_card.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  testWidgets('a five-pixel control drag does not open card details', (
    tester,
  ) async {
    final target = LightingTarget(
      id: 'device-a',
      name: 'Desk strip',
      kind: LightingTargetKind.device,
      memberDeviceIds: const <String>{'device-a'},
    );
    var opened = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          debugDevicesProvider.overrideWith(
            () => _StaticDebugDevicesController(<String, DebugDevice>{
              'device-a': _device(),
            }),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CompactControlCard(
              target: target,
              onOpen: () => opened = true,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('device-a-hold-brightness'))),
    );
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump();
    expect(find.byKey(const Key('hold-value-popup')), findsOneWidget);

    await gesture.up();
    await tester.pump();

    expect(opened, isFalse);
  });
}

DebugDevice _device() {
  return DebugDevice(
    appDeviceId: 'device-a',
    endpoint: TransportEndpoint(
      id: 'device-a',
      transport: TransportKind.ble,
      displayName: 'Desk strip',
    ),
    protocolId: 'lotus',
    matchConfidence: 100,
    matchReason: 'test',
    status: DebugDeviceConnectionStatus.connected,
  );
}

class _StaticDebugDevicesController extends DebugDevicesController {
  _StaticDebugDevicesController(this._devices);

  final Map<String, DebugDevice> _devices;

  @override
  DebugModuleState build() => DebugModuleState(devices: _devices);
}
