import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../application/custom_groups_controller.dart';
import '../application/group_targets.dart';
import 'group_detail_page.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(debugDevicesProvider).sortedDevices;
    final groupsState = ref.watch(customGroupsProvider);
    final protocolGroups = protocolGroupTargets(devices);
    final customGroups = customGroupTargets(groupsState.groups, devices);

    return Scaffold(
      appBar: AppBar(title: const Text('Групи')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-group'),
        onPressed: () => unawaited(_createGroup(context, ref, devices)),
        icon: const Icon(Icons.add),
        label: const Text('Створити'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Common groups', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Створюються автоматично для кожного спільного протоколу й не редагуються.',
          ),
          const SizedBox(height: 8),
          if (protocolGroups.isEmpty)
            const _EmptyGroupSection(
              text: 'З’являться після виявлення сумісних девайсів.',
            )
          else
            ...protocolGroups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GroupTile(target: group, locked: true),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Кастомні групи',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (groupsState.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (customGroups.isEmpty)
            const _EmptyGroupSection(
              text: 'Створіть групу та додайте девайси вручну.',
            )
          else
            ...customGroups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GroupTile(target: group),
              ),
            ),
          if (groupsState.error case final error? when error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }

  Future<void> _createGroup(
    BuildContext context,
    WidgetRef ref,
    List<DebugDevice> devices,
  ) async {
    final protocols =
        devices.map((device) => device.protocolId).toSet().toList()..sort();
    final draft = await showDialog<_NewGroupDraft>(
      context: context,
      builder: (_) => _CreateGroupDialog(protocols: protocols),
    );
    if (!context.mounted || draft == null) {
      return;
    }
    final group = await ref
        .read(customGroupsProvider.notifier)
        .create(name: draft.name, autoAddProtocolId: draft.autoAddProtocolId);
    if (!context.mounted || group == null) {
      return;
    }
    final target = customGroupTargets([group], devices).single;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GroupDetailPage(target: target)),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.target, this.locked = false});

  final LightingTarget target;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: ValueKey<String>('group-${target.id}'),
        leading: Icon(locked ? Icons.lock_outline : Icons.group_outlined),
        title: Text(target.name),
        subtitle: Text(
          '${target.memberDeviceIds.length} девайсів'
          '${target.customGroup?.automaticallyAddsSimilarDevices == true ? ' · автододавання' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => GroupDetailPage(target: target),
          ),
        ),
      ),
    );
  }
}

class _EmptyGroupSection extends StatelessWidget {
  const _EmptyGroupSection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}

class _NewGroupDraft {
  const _NewGroupDraft({required this.name, this.autoAddProtocolId});

  final String name;
  final String? autoAddProtocolId;
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog({required this.protocols});

  final List<String> protocols;

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final TextEditingController _nameController = TextEditingController();
  var _autoAdd = false;
  String? _protocolId;

  @override
  void initState() {
    super.initState();
    _protocolId = widget.protocols.isEmpty ? null : widget.protocols.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Нова група'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Назва'),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Автоматично додавати подібні девайси'),
            subtitle: const Text('Лише для вибраного протоколу.'),
            value: _autoAdd,
            onChanged: widget.protocols.isEmpty
                ? null
                : (value) => setState(() => _autoAdd = value),
          ),
          if (_autoAdd)
            DropdownButtonFormField<String>(
              initialValue: _protocolId,
              decoration: const InputDecoration(labelText: 'Протокол'),
              items: widget.protocols
                  .map(
                    (protocol) => DropdownMenuItem<String>(
                      value: protocol,
                      child: Text(protocolDisplayName(protocol)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _protocolId = value),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _NewGroupDraft(
              name: _nameController.text,
              autoAddProtocolId: _autoAdd ? _protocolId : null,
            ),
          ),
          child: const Text('Створити'),
        ),
      ],
    );
  }
}
