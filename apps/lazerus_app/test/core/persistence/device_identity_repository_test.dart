import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/persistence/device_identity_repository.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'persists a user-defined name separately from BLE advertising data',
    () async {
      final repository = SharedPreferencesDeviceIdentityRepository(
        uuid: const Uuid(),
      );
      final endpoint = TransportEndpoint(
        id: 'peripheral-1',
        transport: TransportKind.ble,
        displayName: 'ELK-BLEDDM',
      );

      final identity = await repository.resolve(
        endpoint,
        protocolId: 'lotus-lamp-x',
      );
      await repository.rename(identity.appDeviceId, '  Kitchen strip  ');

      final reloaded = SharedPreferencesDeviceIdentityRepository(
        uuid: const Uuid(),
      );
      final restored = await reloaded.resolve(
        TransportEndpoint(
          id: 'peripheral-1',
          transport: TransportKind.ble,
          displayName: 'ELK-BLEDDM v2',
        ),
        protocolId: 'lotus-lamp-x',
      );

      expect(restored.appDeviceId, identity.appDeviceId);
      expect(restored.userDefinedName, 'Kitchen strip');
    },
  );
}
