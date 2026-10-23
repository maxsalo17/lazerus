import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import 'compact_control_card.dart';
import 'target_detail_page.dart';

class ControlsPage extends ConsumerWidget {
  const ControlsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(debugDevicesProvider).sortedDevices;
    final customGroups = ref.watch(customGroupsProvider);
    final groups = <LightingTarget>[
      ...protocolGroupTargets(devices),
      ...customGroupTargets(customGroups.groups, devices),
    ];
    final deviceTargets = devices
        .map(
          (device) => LightingTarget(
            id: device.appDeviceId,
            name: device.endpoint.displayName ?? 'Без назви',
            kind: LightingTargetKind.device,
            memberDeviceIds: <String>{device.appDeviceId},
            protocolId: device.protocolId,
          ),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Керування')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Групи', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (customGroups.isLoading && groups.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (groups.isEmpty)
            const _EmptyControlSection(
              text: 'Групи з’являться після виявлення сумісних девайсів.',
            )
          else
            ...groups.expand(
              (target) => <Widget>[
                CompactControlCard(
                  key: ValueKey<String>('control-${target.id}'),
                  target: target,
                  onOpen: () => _openDetails(context, target),
                ),
                const SizedBox(height: 8),
              ],
            ),
          const SizedBox(height: 18),
          Text('Девайси', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (deviceTargets.isEmpty)
            const _EmptyControlSection(
              text: 'Девайси з’являться тут після BLE-сканування.',
            )
          else
            ...deviceTargets.expand(
              (target) => <Widget>[
                CompactControlCard(
                  key: ValueKey<String>('control-${target.id}'),
                  target: target,
                  onOpen: () => _openDetails(context, target),
                ),
                const SizedBox(height: 8),
              ],
            ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, LightingTarget target) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => TargetDetailPage(target: target)),
    );
  }
}

class _EmptyControlSection extends StatelessWidget {
  const _EmptyControlSection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}
