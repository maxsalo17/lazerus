import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../diagnostics/presentation/logs_page.dart';
import '../../devices/presentation/devices_page.dart';
import '../../macros/presentation/macro_library_page.dart';

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
    final pages = <Widget>[DevicesPage(), const MacroLibraryPage(), LogsPage()];
    final destinations = const <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.devices_outlined),
        label: 'Девайси',
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
}
