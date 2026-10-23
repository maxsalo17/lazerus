import 'dart:typed_data';

import 'lotus_lamp_x_identifiers.dart';

/// Plain E1 frame encoder inferred from LotusLampX's BLE protocol module.
///
/// It deliberately does not enable encrypted framing. That path remains
/// unverified for the initial Lazerus hardware profile.
abstract final class LotusLampXFrameCodec {
  static const int _frameLength = 9;
  static const int _frameStart = 0x7e;
  static const int _frameEnd = 0xef;
  static const int _applicationType = 0x02;
  static const int _applicationVersion = 0x01;
  static const int _rgbLampType = 0x01;

  static Uint8List buildE1Frame(
    LotusLampXCommand command,
    Iterable<int> parameters,
  ) {
    final values = parameters.toList(growable: false);
    if (values.length > 5) {
      throw ArgumentError.value(
        parameters,
        'parameters',
        'An E1 frame accepts at most five parameter bytes.',
      );
    }
    for (final value in values) {
      _requireByte(value);
    }

    final frame = Uint8List(_frameLength)
      ..[0] = _frameStart
      ..[1] = command == LotusLampXCommand.brightness ? 0x04 : 0x07
      ..[2] = command.value
      ..[3] = 0xff
      ..[4] = 0xff
      ..[5] = 0xff
      ..[6] = 0xff
      ..[7] = 0x00
      ..[8] = _frameEnd;

    for (var index = 0; index < values.length; index++) {
      frame[3 + index] = values[index];
    }
    return frame;
  }

  static Uint8List power(bool enabled, {int lampType = _rgbLampType}) {
    _requireByte(lampType);
    return buildE1Frame(LotusLampXCommand.power, <int>[
      enabled ? 0xff : 0x00,
      lampType,
      enabled ? 0x01 : 0x00,
      _applicationType,
      _applicationVersion,
    ]);
  }

  static Uint8List brightness(int value) {
    _requireByte(value);
    return buildE1Frame(LotusLampXCommand.brightness, <int>[value]);
  }

  static Uint8List color(int red, int green, int blue) {
    _requireByte(red);
    _requireByte(green);
    _requireByte(blue);
    return buildE1Frame(LotusLampXCommand.color, <int>[
      0x03,
      red,
      green,
      blue,
      0x10,
    ]);
  }

  static Uint8List nativeEffect(LotusLampXNativeEffect effect) {
    return buildE1Frame(LotusLampXCommand.mode, <int>[effect.modeId, 0x03]);
  }

  static int normalizedBrightnessToByte(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'Must be between 0 and 1.');
    }
    return (value * 255).round();
  }

  static void _requireByte(int value) {
    if (value < 0 || value > 0xff) {
      throw RangeError.range(value, 0, 0xff, 'value');
    }
  }
}
