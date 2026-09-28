import 'package:flutter/material.dart';

import '../../../core/settings_registry.dart';
import '../../application/mesh_app_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});

  final MeshAppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _transportId = 'meshtastic';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    final definitions = settingsRegistry.definitions
        .where((item) => item.supportedTransports.contains(_transportId))
        .toList(growable: false);
    final groups = <String, List<SettingDefinition>>{};
    for (final definition in definitions) {
      groups.putIfAbsent(definition.group, () => <SettingDefinition>[]);
      groups[definition.group]!.add(definition);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text(
          'Настройки',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Тёмная основа · полупрозрачные панели · настройки из общего Registry',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Интерфейс',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Прозрачность используется для панелей и навигации. '
                'Текст и поля ввода остаются контрастными; постоянный blur '
                'на всём экране не используется, чтобы не нагружать телефон.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _InfoChip(icon: Icons.dark_mode_outlined, label: 'Dark'),
                  _InfoChip(icon: Icons.layers_outlined, label: 'Glass panels'),
                  _InfoChip(icon: Icons.speed_outlined, label: 'Low overhead'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GlassPanel(
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.advancedMode,
              onChanged: controller.setAdvancedMode,
              secondary: const Icon(Icons.build_circle_outlined),
              title: const Text(
                'Расширенный режим',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Показывает тесты 100/1000, подробные логи, BLE/USB диагностику '
                'и инженерные параметры. Обычный режим оставляет только '
                'основные действия подключения.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Модуль',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'meshtastic',
                    icon: Icon(Icons.bluetooth),
                    label: Text('Meshtastic'),
                  ),
                  ButtonSegment(
                    value: 'm03',
                    icon: Icon(Icons.usb),
                    label: Text('M03'),
                  ),
                  ButtonSegment(
                    value: 'lr24',
                    icon: Icon(Icons.cable_outlined),
                    label: Text('LR24'),
                  ),
                ],
                selected: {_transportId},
                onSelectionChanged: (values) {
                  if (values.isEmpty) return;
                  setState(() => _transportId = values.first);
                },
              ),
              const SizedBox(height: 12),
              _TransportStatus(
                transportId: _transportId,
                controller: controller,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in groups.entries) ...[
          _SettingsGroup(
            title: entry.key,
            definitions: entry.value,
            deviceBindingReady: false,
          ),
          const SizedBox(height: 10),
        ],
        if (_transportId == 'meshtastic')
          _GlassPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Схема настроек уже подключена к Registry. '
                    'Редактирование реального устройства останется заблокировано, '
                    'пока существующий BLE bridge не будет связан с '
                    'Config/ModuleConfig adapter. Значения здесь не подменяются '
                    'локальными фиктивными данными.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TransportStatus extends StatelessWidget {
  const _TransportStatus({
    required this.transportId,
    required this.controller,
  });

  final String transportId;
  final MeshAppController controller;

  @override
  Widget build(BuildContext context) {
    final (label, ready, detail) = switch (transportId) {
      'meshtastic' => (
          'Meshtastic',
          controller.radioConnected,
          controller.radioState,
        ),
      'm03' => (
          'M03 / ELRS',
          controller.ep2Connected,
          controller.ep2State,
        ),
      'lr24' => (
          'MicoAir LR24-F',
          controller.lr24Connected,
          controller.lr24State,
        ),
      _ => ('Модуль', false, 'unknown'),
    };
    final scheme = Theme.of(context).colorScheme;
    final color = ready ? scheme.primary : scheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label · ${ready ? 'подключено' : detail}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.definitions,
    required this.deviceBindingReady,
  });

  final String title;
  final List<SettingDefinition> definitions;
  final bool deviceBindingReady;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded:
            title == 'Device' || title == 'Radio' || title == 'LoRa',
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${definitions.length} параметров'),
        children: [
          for (final definition in definitions)
            _SettingTile(
              definition: definition,
              enabled: deviceBindingReady,
            ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.definition,
    required this.enabled,
  });

  final SettingDefinition definition;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final constraints = <String>[
      if (definition.minimum != null) 'min ${definition.minimum}',
      if (definition.maximum != null) 'max ${definition.maximum}',
      if (definition.sinceFirmware != null)
        'fw ≥ ${definition.sinceFirmware}',
      if (definition.untilFirmware != null)
        'fw ≤ ${definition.untilFirmware}',
      if (definition.requiresCapability != null)
        'cap: ${definition.requiresCapability}',
    ];
    final details = [
      definition.fieldPath,
      if (constraints.isNotEmpty) constraints.join(' · '),
    ].join('\n');

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        enabled: enabled,
        leading: Icon(_iconFor(definition.valueType)),
        title: Text(definition.label),
        subtitle: Text(details),
        isThreeLine: constraints.isNotEmpty,
        trailing: _ValueTypeBadge(type: definition.valueType),
        textColor: enabled ? null : scheme.onSurfaceVariant,
        iconColor: enabled ? null : scheme.onSurfaceVariant,
      ),
    );
  }

  IconData _iconFor(SettingValueType type) => switch (type) {
        SettingValueType.boolean => Icons.toggle_on_outlined,
        SettingValueType.integer => Icons.numbers_outlined,
        SettingValueType.decimal => Icons.calculate_outlined,
        SettingValueType.text => Icons.text_fields_outlined,
        SettingValueType.enumeration => Icons.list_alt_outlined,
        SettingValueType.secret => Icons.key_outlined,
      };
}

class _ValueTypeBadge extends StatelessWidget {
  const _ValueTypeBadge({required this.type});

  final SettingValueType type;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      SettingValueType.boolean => 'ON/OFF',
      SettingValueType.integer => 'INT',
      SettingValueType.decimal => 'NUM',
      SettingValueType.text => 'TEXT',
      SettingValueType.enumeration => 'LIST',
      SettingValueType.secret => 'SECRET',
    };
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.56),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
