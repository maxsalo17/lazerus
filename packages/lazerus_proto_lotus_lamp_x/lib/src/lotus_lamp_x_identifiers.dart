import 'package:lazerus_core/lazerus_core.dart';

/// BLE identifiers used by the initial Lotus Lamp X reference implementation.
abstract final class LotusLampXBleIdentifiers {
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String writeCharacteristicUuid =
      '0000fff3-0000-1000-8000-00805f9b34fb';
  static const String notifyCharacteristicUuid =
      '0000fff4-0000-1000-8000-00805f9b34fb';

  static const Set<String> namePrefixes = <String>{'elk', 'melk'};
}

/// Command identifiers inferred from the LotusLampX reference implementation.
enum LotusLampXCommand {
  brightness(0x01),
  speed(0x02),
  mode(0x03),
  power(0x04),
  color(0x05),
  microphoneSensitivity(0x06),
  microphonePower(0x07),
  timer(0x0d),
  humanSensor(0x12),
  scene(0x31),
  warmCold(0x40),
  offTimer(0x76),
  factoryReset(0x87);

  const LotusLampXCommand(this.value);

  final int value;
}

/// Native effect IDs exposed through the first Lotus Lamp X adapter.
enum LotusLampXNativeEffect {
  jump(1, 'lotus_lamp_x.jump', 'Jump'),
  strobe(2, 'lotus_lamp_x.strobe', 'Strobe'),
  breathe(3, 'lotus_lamp_x.breathe', 'Breathe'),
  warning(4, 'lotus_lamp_x.warning', 'Warning');

  const LotusLampXNativeEffect(this.modeId, this.effectId, this.displayName);

  final int modeId;
  final String effectId;
  final String displayName;

  DeviceEffect toDeviceEffect() {
    return DeviceEffect(id: effectId, displayName: displayName);
  }

  static LotusLampXNativeEffect? fromDeviceEffect(DeviceEffect effect) {
    for (final nativeEffect in values) {
      if (nativeEffect.effectId == effect.id) {
        return nativeEffect;
      }
    }
    return null;
  }
}
