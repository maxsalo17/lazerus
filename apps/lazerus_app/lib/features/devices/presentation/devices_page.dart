import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calibration/presentation/calibration_page.dart';
import '../../control/presentation/target_detail_page.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/group_targets.dart';
import 'device_display.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  final Set<String> _selectedDeviceIds = <String>{};
  String? _selectedProtocolId;

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(debugDevicesProvider);
    final controller = ref.read(debugDevicesProvider.notifier);
    final devices = deviceState.sortedDevices;
    final selectedDevices = devices
        .where((device) => _selectedDeviceIds.contains(device.appDeviceId))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Девайси'),
        actions: <Widget>[
          if (selectedDevices.isNotEmpty) ...<Widget>[
            TextButton.icon(
              key: const Key('open-calibration'),
              onPressed: () => _openCalibration(selectedDevices),
              icon: const Icon(Icons.tune),
              label: Text('Калібрувати (${selectedDevices.length})'),
            ),
            IconButton(
              tooltip: 'Зняти вибір',
              onPressed: _clearSelection,
              icon: const Icon(Icons.clear),
            ),
          ],
          IconButton(
            key: const Key('scan-devices'),
            tooltip: deviceState.isScanning ? 'Сканування триває' : 'Сканувати',
            onPressed: deviceState.isScanning
                ? null
                : () => unawaited(controller.startDiscovery()),
            icon: deviceState.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.startDiscovery,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            if (deviceState.isScanning)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(),
              ),
            if (deviceState.scanError case final error? when error.isNotEmpty)
              _DeviceError(message: error),
            if (devices.isEmpty)
              const _NoDevices()
            else
              ...devices.map(
                (device) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CompactDeviceTile(
                    device: device,
                    selected: _selectedDeviceIds.contains(device.appDeviceId),
                    selectionEnabled:
                        _selectedProtocolId == null ||
                        _selectedProtocolId == device.protocolId ||
                        _selectedDeviceIds.contains(device.appDeviceId),
                    onSelectionChanged: (selected) =>
                        _toggleSelection(device, selected),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleSelection(DebugDevice device, bool selected) {
    if (selected &&
        _selectedProtocolId != null &&
        _selectedProtocolId != device.protocolId) {
      return;
    }
    setState(() {
      if (selected) {
        _selectedDeviceIds.add(device.appDeviceId);
        _selectedProtocolId ??= device.protocolId;
      } else {
        _selectedDeviceIds.remove(device.appDeviceId);
        if (_selectedDeviceIds.isEmpty) {
          _selectedProtocolId = null;
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDeviceIds.clear();
      _selectedProtocolId = null;
    });
  }

  Future<void> _openCalibration(List<DebugDevice> selectedDevices) async {
    final protocolId = _selectedProtocolId;
    if (protocolId == null || selectedDevices.isEmpty) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CalibrationPage(
          deviceIds: selectedDevices
              .map((device) => device.appDeviceId)
              .toSet(),
          protocolId: protocolId,
          deviceNames: selectedDevices
              .map((device) => device.endpoint.displayName ?? 'Без назви')
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _CompactDeviceTile extends ConsumerWidget {
  const _CompactDeviceTile({
    required this.device,
    required this.selected,
    required this.selectionEnabled,
    required this.onSelectionChanged,
  });

  final DebugDevice device;
  final bool selected;
  final bool selectionEnabled;
  final ValueChanged<bool> onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(debugDevicesProvider.notifier);
    final connected = device.status == DebugDeviceConnectionStatus.connected;
    final connecting = device.status == DebugDeviceConnectionStatus.connecting;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey<String>('device-${device.appDeviceId}'),
        leading: SizedBox(
          width: 72,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                key: Key('select-device-${device.appDeviceId}'),
                value: selected,
                onChanged: selectionEnabled
                    ? (value) => onSelectionChanged(value ?? false)
                    : null,
              ),
              Icon(
                deviceStatusIcon(device.status),
                color: deviceStatusColor(context, device.status),
                size: 20,
              ),
            ],
          ),
        ),
        title: Text(device.endpoint.displayName ?? 'Без назви'),
        subtitle: Text(
          '${protocolDisplayName(device.protocolId)} · ${deviceStatusLabel(device.status)}'
          '${device.endpoint.metadata['rssi'] == null ? '' : ' · ${device.endpoint.metadata['rssi']} dBm'}',
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => TargetDetailPage(
              target: LightingTarget(
                id: device.appDeviceId,
                name: device.endpoint.displayName ?? 'Без назви',
                kind: LightingTargetKind.device,
                memberDeviceIds: <String>{device.appDeviceId},
                protocolId: device.protocolId,
              ),
            ),
          ),
        ),
        trailing: connecting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: connected
                    ? () => unawaited(controller.disconnect(device.appDeviceId))
                    : () => unawaited(
                        controller.connectDevice(device.appDeviceId),
                      ),
                child: Text(connected ? 'Від’єднати' : 'Підключити'),
              ),
      ),
    );
  }
}

class _NoDevices extends StatelessWidget {
  const _NoDevices();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 72),
      child: Center(
        child: Column(
          children: <Widget>[
            Icon(Icons.devices_other, size: 54),
            SizedBox(height: 12),
            Text('Сумісні девайси ще не знайдено.'),
            SizedBox(height: 4),
            Text('Потягніть для оновлення або запустіть сканування.'),
          ],
        ),
      ),
    );
  }
}

class _DeviceError extends StatelessWidget {
  const _DeviceError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
      ),
    );
  }
}
