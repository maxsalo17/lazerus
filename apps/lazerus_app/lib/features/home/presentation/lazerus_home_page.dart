import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../control/presentation/controls_page.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../diagnostics/presentation/logs_page.dart';
import '../../devices/presentation/devices_page.dart';
import '../../groups/presentation/groups_page.dart';
import '../../macros/application/macro_library_controller.dart';
import '../../macros/presentation/macro_library_page.dart';
import '../../scenes/presentation/scenes_page.dart';
import '../../scenes/presentation/scene_macro_references.dart';

class LazerusHomePage extends ConsumerStatefulWidget {
  const LazerusHomePage({super.key});

  @override
  ConsumerState<LazerusHomePage> createState() => _LazerusHomePageState();
}

class _LazerusHomePageState extends ConsumerState<LazerusHomePage> {
  var _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Discovery starts once for the application surface. Matching endpoints
    // connect automatically; manually disconnected devices stay disconnected
    // until the user explicitly reconnects them.
    unawaited(ref.read(debugDevicesProvider.notifier).startDiscovery());
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DevicesPage(),
      GroupsPage(),
      ControlsPage(),
      ScenesPage(
        macroReferencesEditor: MacroLibraryPage.selectForScene,
        macroReferenceResolver: _resolveMacroReference,
      ),
      const MacroLibraryPage(),
      LogsPage(),
    ];
    final destinations = const <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.devices_outlined),
        label: 'Девайси',
      ),
      NavigationDestination(
        icon: Icon(Icons.group_work_outlined),
        label: 'Групи',
      ),
      NavigationDestination(
        icon: Icon(Icons.tune_outlined),
        label: 'Керування',
      ),
      NavigationDestination(
        icon: Icon(Icons.auto_awesome_motion_outlined),
        label: 'Scenes',
      ),
      NavigationDestination(
        icon: Icon(Icons.account_tree_outlined),
        label: 'Macros',
      ),
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'Logs',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 760;
        if (!useRail) {
          return Scaffold(
            body: SafeArea(
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: destinations,
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 24),
                    child: Icon(Icons.lightbulb, size: 30),
                  ),
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.devices_outlined),
                      selectedIcon: Icon(Icons.devices),
                      label: Text('Девайси'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.group_work_outlined),
                      selectedIcon: Icon(Icons.group_work),
                      label: Text('Групи'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: Text('Керування'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.auto_awesome_motion_outlined),
                      selectedIcon: Icon(Icons.auto_awesome_motion),
                      label: Text('Scenes'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.account_tree_outlined),
                      selectedIcon: Icon(Icons.account_tree),
                      label: Text('Macros'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: Text('Logs'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(index: _selectedIndex, children: pages),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<SceneMacroReferenceResolution> _resolveMacroReference(
    SceneMacroReference reference,
  ) async {
    final library = ref.read(macroLibraryProvider);
    if (library.isLoading || library.error != null) {
      return const SceneMacroReferenceResolution(
        status: SceneMacroReferenceStatus.unknown,
        detail: 'Macro library is still loading.',
      );
    }
    final macro = library.byId(reference.macroId);
    return macro == null
        ? const SceneMacroReferenceResolution(
            status: SceneMacroReferenceStatus.missing,
            detail:
                'Macro file is unavailable. Choose another macro or remove this reference.',
          )
        : SceneMacroReferenceResolution(
            status: SceneMacroReferenceStatus.available,
            label: macro.name,
          );
  }
}
