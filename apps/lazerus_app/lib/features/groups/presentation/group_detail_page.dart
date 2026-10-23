import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../control/presentation/target_detail_page.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../devices/presentation/device_display.dart';
import '../application/custom_groups_controller.dart';
import '../application/group_targets.dart';
import '../domain/lighting_group.dart';

class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.target});

  final LightingTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(debugDevicesProvider).sortedDevices;
    final groupsState = ref.watch(customGroupsProvider);
    final currentTarget = _resolveCurrentTarget(groupsState.groups, devices);
    final customGroup = currentTarget.customGroup;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTarget.name),
        actions: <Widget>[
          if (customGroup != null)
            IconButton(
              tooltip: 'Перейменувати',
              onPressed: () => unawaited(_rename(context, ref, customGroup)),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (customGroup != null)
            IconButton(
              tooltip: 'Видалити групу',
              onPressed: () => unawaited(_delete(context, ref, customGroup)),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Детальне керування'),
              subtitle: const Text(
                'Живлення, колір та яскравість для всієї групи.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TargetDetailPage(target: currentTarget),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (customGroup == null)
            const _LockedGroupNotice()
          else ...<Widget>[
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Автоматично додавати подібні девайси'),
              subtitle: Text(
                customGroup.autoAddProtocolId == null
                    ? 'Вимкнено'
                    : protocolDisplayName(customGroup.autoAddProtocolId!),
              ),
              value: customGroup.automaticallyAddsSimilarDevices,
              onChanged: (enabled) => unawaited(
                _toggleAutoAdd(context, ref, customGroup, devices, enabled),
              ),
            ),
            const Divider(),
          ],
          const SizedBox(height: 8),
          Text('Девайси', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (devices.isEmpty)
            const Text('Немає доступних девайсів для додавання.')
          else
            ...devices.map((device) {
              final manuallyIncluded = customGroup?.memberDeviceIds.contains(
                device.appDeviceId,
              );
              final automaticallyIncluded =
                  customGroup?.autoAddProtocolId == device.protocolId;
              if (customGroup == null) {
                final included = currentTarget.memberDeviceIds.contains(
                  device.appDeviceId,
                );
                return _ReadOnlyMemberTile(device: device, included: included);
              }
              final manuallySelected = manuallyIncluded ?? false;
              return CheckboxListTile(
                key: ValueKey<String>('group-member-${device.appDeviceId}'),
                contentPadding: EdgeInsets.zero,
                value: manuallySelected,
                title: Text(device.endpoint.displayName ?? 'Без назви'),
                subtitle: Text(
                  automaticallyIncluded && !manuallySelected
                      ? '${deviceStatusLabel(device.status)} · додано автоматично'
                      : deviceStatusLabel(device.status),
                ),
                secondary: Icon(
                  deviceStatusIcon(device.status),
                  color: deviceStatusColor(context, device.status),
                ),
                onChanged: (selected) => unawaited(
                  _setManualMembership(
                    ref,
                    customGroup,
                    device.appDeviceId,
                    selected ?? false,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  LightingTarget _resolveCurrentTarget(
    List<CustomLightingGroup> customGroups,
    List<DebugDevice> devices,
  ) {
    if (target.kind == LightingTargetKind.protocolGroup) {
      return protocolGroupTargets(
        devices,
      ).firstWhere((current) => current.id == target.id, orElse: () => target);
    }
    if (target.kind == LightingTargetKind.customGroup) {
      return customGroupTargets(
        customGroups,
        devices,
      ).firstWhere((current) => current.id == target.id, orElse: () => target);
    }
    return target;
  }

  Future<void> _setManualMembership(
    WidgetRef ref,
    CustomLightingGroup group,
    String appDeviceId,
    bool selected,
  ) {
    final members = <String>{...group.memberDeviceIds};
    if (selected) {
      members.add(appDeviceId);
    } else {
      members.remove(appDeviceId);
    }
    return ref
        .read(customGroupsProvider.notifier)
        .update(group.copyWith(memberDeviceIds: members));
  }

  Future<void> _toggleAutoAdd(
    BuildContext context,
    WidgetRef ref,
    CustomLightingGroup group,
    List<DebugDevice> devices,
    bool enabled,
  ) async {
    if (!enabled) {
      await ref
          .read(customGroupsProvider.notifier)
          .update(group.copyWith(clearAutoAddProtocol: true));
      return;
    }
    final protocolId =
        group.autoAddProtocolId ??
        devices
            .where(
              (device) => group.memberDeviceIds.contains(device.appDeviceId),
            )
            .map((device) => device.protocolId)
            .firstOrNull ??
        (devices.isEmpty ? null : devices.first.protocolId);
    if (protocolId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Спочатку виявіть хоча б один девайс.')),
        );
      }
      return;
    }
    await ref
        .read(customGroupsProvider.notifier)
        .update(group.copyWith(autoAddProtocolId: protocolId));
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    CustomLightingGroup group,
  ) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Перейменувати групу'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Назва'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Зберегти'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted || name == null) {
      return;
    }
    await ref
        .read(customGroupsProvider.notifier)
        .update(group.copyWith(name: name));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CustomLightingGroup group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Видалити «${group.name}»?'),
        content: const Text('Девайси не буде видалено.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    await ref.read(customGroupsProvider.notifier).delete(group.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _LockedGroupNotice extends StatelessWidget {
  const _LockedGroupNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Це Common group. Її склад визначається протоколом і не редагується вручну.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyMemberTile extends StatelessWidget {
  const _ReadOnlyMemberTile({required this.device, required this.included});

  final DebugDevice device;
  final bool included;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        included ? Icons.check_circle_outline : Icons.remove_circle_outline,
        color: included ? Colors.green : Colors.grey,
      ),
      title: Text(device.endpoint.displayName ?? 'Без назви'),
      subtitle: Text(deviceStatusLabel(device.status)),
    );
  }
}
