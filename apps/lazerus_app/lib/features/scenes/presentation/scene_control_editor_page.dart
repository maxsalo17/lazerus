import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../application/scene_target_options.dart';
import '../domain/lighting_scene.dart';

/// Edits one stable Scene control slot. It returns a validated control; the
/// Settings page owns persistence and keeps the slot identity unchanged.
class SceneControlEditorPage extends StatefulWidget {
  const SceneControlEditorPage({
    super.key,
    required this.scene,
    required this.slot,
    required this.targetOptions,
  });

  final LightingScene scene;
  final SceneControlSlot slot;
  final List<SceneTargetOption> targetOptions;

  @override
  State<SceneControlEditorPage> createState() => _SceneControlEditorPageState();
}

class _SceneControlEditorPageState extends State<SceneControlEditorPage> {
  final TextEditingController _labelController = TextEditingController();
  late SceneControlType _type;
  late Set<SceneTargetReference> _selectedTargets;
  String? _error;

  @override
  void initState() {
    super.initState();
    final control = widget.slot.control;
    _type = control?.type ?? SceneControlType.toggle;
    _labelController.text = control?.label ?? '';
    _selectedTargets = <SceneTargetReference>{
      ...?control?.bindings.map((binding) => binding.target),
    };
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parameter = _type.parameter;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.slot.control == null ? 'Новий контрол' : 'Контрол'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            DropdownButtonFormField<SceneControlType>(
              key: const Key('scene-control-type'),
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Тип контролу',
                border: OutlineInputBorder(),
              ),
              items: SceneControlType.values
                  .map(
                    (type) => DropdownMenuItem<SceneControlType>(
                      value: type,
                      child: Text(_controlTypeLabel(type)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _setType,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('scene-control-label'),
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Назва (необов’язково)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Bindings · ${sceneParameterLabel(parameter)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Оберіть одну або більше цілей, які підтримують цей параметр. Для групи параметр має бути доступним у кожного її поточного члена.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (widget.targetOptions.isEmpty)
              const _NoBindableTargets()
            else
              ...widget.targetOptions.map((option) {
                final selected = _selectedTargets.contains(option.reference);
                final supported = option.supports(parameter);
                return CheckboxListTile(
                  key: Key(
                    'scene-control-binding-${option.reference.type.name}-${option.reference.targetId}',
                  ),
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  title: Text(option.name),
                  subtitle: Text(
                    supported
                        ? '${option.kindLabel} · ${sceneParameterLabel(parameter)}'
                        : '${option.kindLabel} · ${option.availabilityLabel}',
                  ),
                  secondary: Icon(
                    option.reference.type == SceneTargetType.group
                        ? Icons.group_outlined
                        : Icons.devices_outlined,
                  ),
                  // An unsupported existing binding stays removable, but cannot
                  // be selected again. This avoids silently saving an invalid
                  // capability assignment after a device changes.
                  onChanged: supported || selected
                      ? (value) =>
                            _toggleTarget(option.reference, value ?? false)
                      : null,
                );
              }),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _EditorError(message: _error!),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('save-scene-control'),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Зберегти контрол'),
            ),
          ],
        ),
      ),
    );
  }

  void _setType(SceneControlType? type) {
    if (type == null) {
      return;
    }
    final supportedReferences = widget.targetOptions
        .where((option) => option.supports(type.parameter))
        .map((option) => option.reference)
        .toSet();
    setState(() {
      _type = type;
      _selectedTargets = _selectedTargets.intersection(supportedReferences);
      _error = null;
    });
  }

  void _toggleTarget(SceneTargetReference reference, bool selected) {
    setState(() {
      if (selected) {
        _selectedTargets.add(reference);
      } else {
        _selectedTargets.remove(reference);
      }
      _error = null;
    });
  }

  void _save() {
    final parameter = _type.parameter;
    final optionByReference = <SceneTargetReference, SceneTargetOption>{
      for (final option in widget.targetOptions) option.reference: option,
    };
    if (_selectedTargets.isEmpty) {
      setState(() => _error = 'Оберіть хоча б одну сумісну ціль.');
      return;
    }
    if (_selectedTargets.any(
      (reference) =>
          !(optionByReference[reference]?.supports(parameter) ?? false),
    )) {
      setState(
        () => _error = 'Приберіть недоступні bindings перед збереженням.',
      );
      return;
    }
    final control = SceneCustomControl(
      id: widget.slot.control?.id ?? const Uuid().v4(),
      type: _type,
      label: _labelController.text.trim().isEmpty
          ? null
          : _labelController.text.trim(),
      bindings: _selectedTargets
          .map(
            (reference) =>
                SceneControlBinding(target: reference, parameter: parameter),
          )
          .toList(growable: false),
    );
    Navigator.of(context).pop(control);
  }

  static String _controlTypeLabel(SceneControlType type) => switch (type) {
    SceneControlType.toggle => 'Перемикач живлення',
    SceneControlType.brightnessSlider => 'Слайдер яскравості',
    SceneControlType.colorSlider => 'Слайдер кольору',
  };
}

class _NoBindableTargets extends StatelessWidget {
  const _NoBindableTargets();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'У Scene ще немає цілей. Поверніться до Settings і додайте групу або девайс.',
        ),
      ),
    );
  }
}

class _EditorError extends StatelessWidget {
  const _EditorError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}
