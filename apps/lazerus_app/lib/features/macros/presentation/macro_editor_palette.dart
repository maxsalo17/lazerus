import 'package:flutter/material.dart';

import 'node_modules/macro_editor_node_module.dart';

/// Generic palette surface. It renders metadata supplied by registered node
/// modules and never imports or switches on a concrete macro-node kind.
class MacroEditorPalette extends StatelessWidget {
  const MacroEditorPalette({
    super.key,
    required this.entries,
    required this.enabled,
    required this.onAdd,
  });

  final Iterable<MacroEditorPaletteEntry> entries;
  final bool enabled;
  final ValueChanged<MacroEditorPaletteEntry> onAdd;

  @override
  Widget build(BuildContext context) {
    final grouped = <MacroEditorPaletteSection, List<MacroEditorPaletteEntry>>{
      for (final section in MacroEditorPaletteSection.values)
        section: <MacroEditorPaletteEntry>[],
    };
    for (final entry in entries) {
      grouped[entry.section]!.add(entry);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: <Widget>[
          for (final section in MacroEditorPaletteSection.values) ...<Widget>[
            if (grouped[section]!.isNotEmpty) ...<Widget>[
              if (section != MacroEditorPaletteSection.modules) const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Text(switch (section) {
                  MacroEditorPaletteSection.modules => 'Modules',
                  MacroEditorPaletteSection.devices => 'Devices',
                }, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              ...grouped[section]!.map(
                (entry) => _MacroEditorPaletteEntry(
                  entry: entry,
                  enabled: enabled && entry.enabled,
                  onAdd: onAdd,
                ),
              ),
            ],
          ],
          if (grouped[MacroEditorPaletteSection.devices]!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No discovered devices.'),
            ),
        ],
      ),
    );
  }
}

class _MacroEditorPaletteEntry extends StatelessWidget {
  const _MacroEditorPaletteEntry({
    required this.entry,
    required this.enabled,
    required this.onAdd,
  });

  final MacroEditorPaletteEntry entry;
  final bool enabled;
  final ValueChanged<MacroEditorPaletteEntry> onAdd;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      dense: true,
      enabled: enabled,
      leading: Icon(entry.icon),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: enabled ? () => onAdd(entry) : null,
    );
    if (!enabled) return tile;
    return Draggable<MacroEditorPaletteEntry>(
      data: entry,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 220,
          child: ListTile(
            dense: true,
            leading: Icon(entry.icon),
            title: Text(entry.title),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: tile),
      child: tile,
    );
  }
}
