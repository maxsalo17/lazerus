import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_app/features/groups/domain/lighting_group.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  final lotus = 'lazerus.protocol.lotus_lamp_x';
  const other = 'lazerus.protocol.future';

  DebugDevice device(String id, String protocol) {
    return DebugDevice(
      appDeviceId: id,
      endpoint: TransportEndpoint(
        id: 'endpoint-$id',
        transport: TransportKind.ble,
        displayName: id,
      ),
      protocolId: protocol,
      matchConfidence: 80,
      matchReason: 'test',
      status: DebugDeviceConnectionStatus.connected,
    );
  }

  test('common groups derive their immutable membership from protocol', () {
    final groups = protocolGroupTargets(<DebugDevice>[
      device('one', lotus),
      device('two', lotus),
      device('three', other),
    ]);

    final lotusGroup = groups.singleWhere((group) => group.protocolId == lotus);
    expect(lotusGroup.isEditable, isFalse);
    expect(lotusGroup.memberDeviceIds, <String>{'one', 'two'});
  });

  test(
    'custom auto-add membership combines protocol matches and manual devices',
    () {
      final groups = customGroupTargets(
        <CustomLightingGroup>[
          CustomLightingGroup(
            id: 'studio',
            name: 'Studio',
            memberDeviceIds: const <String>['three'],
            autoAddProtocolId: lotus,
          ),
        ],
        <DebugDevice>[
          device('one', lotus),
          device('two', lotus),
          device('three', other),
        ],
      );

      expect(groups.single.memberDeviceIds, <String>{'one', 'two', 'three'});
    },
  );
}
