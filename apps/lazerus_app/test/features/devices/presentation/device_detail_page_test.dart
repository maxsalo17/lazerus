import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/devices/presentation/device_detail_page.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  testWidgets('renames a device from its details view', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          debugDevicesProvider.overrideWith(_RenameTestDevicesController.new),
        ],
        child: const MaterialApp(
          home: DeviceDetailPage(appDeviceId: 'device-1'),
        ),
      ),
    );

    expect(find.text('ELK-BLEDDM'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rename-device')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('device-name-field')),
      'Спальня',
    );
    await tester.tap(find.byKey(const Key('save-device-name')));
    await tester.pumpAndSettle();

    expect(find.text('Спальня'), findsOneWidget);
    expect(find.text('Назву девайса збережено.'), findsOneWidget);
  });
}

class _RenameTestDevicesController extends DebugDevicesController {
  @override
  DebugModuleState build() {
    return DebugModuleState(
      devices: <String, DebugDevice>{
        'device-1': DebugDevice(
          appDeviceId: 'device-1',
          endpoint: TransportEndpoint(
            id: 'peripheral-1',
            transport: TransportKind.ble,
            displayName: 'ELK-BLEDDM',
          ),
          protocolId: 'lotus-lamp-x',
          matchConfidence: 100,
          matchReason: 'Test device',
          status: DebugDeviceConnectionStatus.disconnected,
        ),
      },
    );
  }

  @override
  Future<void> renameDevice(String appDeviceId, String userDefinedName) async {
    final device = state.devices[appDeviceId]!;
    state = state.copyWith(
      devices: <String, DebugDevice>{
        ...state.devices,
        appDeviceId: device.copyWith(userDefinedName: userDefinedName.trim()),
      },
    );
  }
}
