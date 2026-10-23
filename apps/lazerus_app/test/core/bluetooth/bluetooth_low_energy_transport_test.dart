import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/bluetooth/bluetooth_low_energy_transport.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'waits for the adapter to become powered on before first discovery',
    () async {
      final manager = _FakeCentralManager();
      final transport = BluetoothLowEnergyTransport(manager: manager);
      final subscription = transport
          .discover(
            DiscoveryRequest(
              timeout: const Duration(seconds: 1),
              includeUnidentified: true,
            ),
          )
          .listen((_) {});

      await _settle();
      expect(manager.startDiscoveryCalls, 0);

      manager.setState(BluetoothLowEnergyState.poweredOn);
      await _settle();
      expect(manager.startDiscoveryCalls, 1);

      await subscription.cancel();
      await manager.dispose();
    },
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeCentralManager implements CentralManager {
  final StreamController<BluetoothLowEnergyStateChangedEventArgs> _states =
      StreamController<BluetoothLowEnergyStateChangedEventArgs>.broadcast();
  final StreamController<DiscoveredEventArgs> _discoveries =
      StreamController<DiscoveredEventArgs>.broadcast();
  var _state = BluetoothLowEnergyState.unknown;
  var startDiscoveryCalls = 0;

  @override
  BluetoothLowEnergyState get state => _state;

  @override
  Stream<BluetoothLowEnergyStateChangedEventArgs> get stateChanged =>
      _states.stream;

  @override
  Stream<DiscoveredEventArgs> get discovered => _discoveries.stream;

  void setState(BluetoothLowEnergyState value) {
    _state = value;
    _states.add(BluetoothLowEnergyStateChangedEventArgs(value));
  }

  @override
  Future<void> startDiscovery({List<UUID>? serviceUUIDs}) async {
    startDiscoveryCalls++;
  }

  @override
  Future<void> stopDiscovery() async {}

  Future<void> dispose() async {
    await _states.close();
    await _discoveries.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
