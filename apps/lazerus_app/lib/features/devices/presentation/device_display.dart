import 'package:flutter/material.dart';

import '../../debug/application/debug_devices_controller.dart';

String deviceStatusLabel(DebugDeviceConnectionStatus status) =>
    switch (status) {
      DebugDeviceConnectionStatus.discovered => 'Знайдено',
      DebugDeviceConnectionStatus.connecting => 'Підключення',
      DebugDeviceConnectionStatus.connected => 'Підключено',
      DebugDeviceConnectionStatus.disconnected => 'Від’єднано',
      DebugDeviceConnectionStatus.unsupported => 'Не підтримується',
      DebugDeviceConnectionStatus.error => 'Помилка',
    };

Color deviceStatusColor(
  BuildContext context,
  DebugDeviceConnectionStatus status,
) {
  return switch (status) {
    DebugDeviceConnectionStatus.connected => Colors.green,
    DebugDeviceConnectionStatus.connecting => Colors.orange,
    DebugDeviceConnectionStatus.error => Theme.of(context).colorScheme.error,
    DebugDeviceConnectionStatus.unsupported ||
    DebugDeviceConnectionStatus.disconnected => Colors.grey,
    DebugDeviceConnectionStatus.discovered => Colors.blueGrey,
  };
}

IconData deviceStatusIcon(DebugDeviceConnectionStatus status) =>
    switch (status) {
      DebugDeviceConnectionStatus.connected => Icons.bluetooth_connected,
      DebugDeviceConnectionStatus.connecting => Icons.bluetooth_searching,
      DebugDeviceConnectionStatus.disconnected ||
      DebugDeviceConnectionStatus.unsupported ||
      DebugDeviceConnectionStatus.error => Icons.bluetooth_disabled,
      DebugDeviceConnectionStatus.discovered => Icons.bluetooth,
    };

String protocolDisplayName(String protocolId) {
  if (protocolId.endsWith('lotus_lamp_x')) return 'Lotus Lamp X';
  return protocolId;
}
