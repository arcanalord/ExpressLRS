import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/settings_registry.dart';
import '../../application/mesh_app_controller.dart';
import '../contacts/contact_share_dialog.dart';

const _meshAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.6.0-secure-core-rc2',
);
const _meshAppBuild = String.fromEnvironment(
  'APP_BUILD',
  defaultValue: '26092902',
);

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.controller, super.key});

  final MeshAppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _transportId = 'lr24';

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    if (controller.lr24Connected) {
      _transportId = 'lr24';
    } else if (controller.ep2Connected) {
      _transportId = 'm03';
    } else if (controller.radioConnected) {
      _transportId = 'meshtastic';
    }
    controller.addListener(_refresh);
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
        const SizedBox(height: 14),
        _IdentityPanel(controller: controller),
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
                'Тесты, подробная диагностика и инженерные параметры.',
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
                'Настройки связи',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'lr24',
                    icon: Icon(Icons.cable_outlined),
                    label: Text('LR24'),
                  ),
                  ButtonSegment(
                    value: 'm03',
                    icon: Icon(Icons.usb),
                    label: Text('M03'),
                  ),
                  ButtonSegment(
                    value: 'meshtastic',
                    icon: Icon(Icons.bluetooth),
                    label: Text('Meshtastic'),
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
        const _PlannedSettingsPanel(),
        const SizedBox(height: 12),
        const _AboutPanel(),
        const SizedBox(height: 12),
        for (final entry in groups.entries) ...[
          _SettingsGroup(
            title: entry.key,
            definitions: entry.value,
            deviceBindingReady: false,
            showTechnicalDetails: controller.advancedMode,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({required this.controller});

  final MeshAppController controller;

  @override
  Widget build(BuildContext context) {
    final label = controller.ownDeviceLabel.trim().isEmpty
        ? 'Mesh Messenger'
        : controller.ownDeviceLabel.trim();

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'MM-ID',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SelectableText(controller.ownMmId),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showOwnContactCardDialog(context, controller),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Показать QR'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: controller.ownMmId),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('MM-ID скопирован')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Копировать MM-ID'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return const _GlassPanel(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('О приложении', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Версия $_meshAppVersion ($_meshAppBuild)'),
      ),
    );
  }
}

class _PlannedSettingsPanel extends StatelessWidget {
  const _PlannedSettingsPanel();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text(
          'Планируемые разделы',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Будут включаться по мере готовности'),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: const [
          _PlannedSettingTile(
            icon: Icons.notifications_outlined,
            label: 'Уведомления',
          ),
          _PlannedSettingTile(
            icon: Icons.photo_outlined,
            label: 'Файлы и медиа',
          ),
          _PlannedSettingTile(
            icon: Icons.security_outlined,
            label: 'Конфиденциальность и безопасность',
          ),
          _PlannedSettingTile(
            icon: Icons.public_outlined,
            label: 'Интернет и ретрансляция',
          ),
          _PlannedSettingTile(
            icon: Icons.storage_outlined,
            label: 'Хранилище',
          ),
          _PlannedSettingTile(
            icon: Icons.palette_outlined,
            label: 'Внешний вид',
          ),
          _PlannedSettingTile(
            icon: Icons.backup_outlined,
            label: 'Резервная копия и перенос',
          ),
        ],
      ),
    );
  }
}

class _PlannedSettingTile extends StatelessWidget {
  const _PlannedSettingTile({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: const _StatusPill(label: 'Скоро'),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
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
            label + ' · ' + (ready ? 'подключено' : detail),
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
    required this.showTechnicalDetails,
  });

  final String title;
  final List<SettingDefinition> definitions;
  final bool deviceBindingReady;
  final bool showTechnicalDetails;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(
          _friendlyGroupTitle(title),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(definitions.length.toString() + ' параметров'),
        children: [
          for (final definition in definitions)
            _SettingTile(
              definition: definition,
              enabled: deviceBindingReady,
              showTechnicalDetails: showTechnicalDetails,
            ),
        ],
      ),
    );
  }
}

String _friendlyGroupTitle(String title) => switch (title) {
      'Device' => 'Устройство',
      'Radio' => 'Радио',
      'LoRa' => 'LoRa',
      'Bluetooth' => 'Bluetooth',
      'Network' => 'Сеть',
      'Power' => 'Питание',
      _ => title,
    };

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.definition,
    required this.enabled,
    required this.showTechnicalDetails,
  });

  final SettingDefinition definition;
  final bool enabled;
  final bool showTechnicalDetails;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final constraints = <String>[
      if (definition.minimum != null) 'min ' + definition.minimum.toString(),
      if (definition.maximum != null) 'max ' + definition.maximum.toString(),
      if (definition.sinceFirmware != null)
        'fw ≥ ' + definition.sinceFirmware.toString(),
      if (definition.untilFirmware != null)
        'fw ≤ ' + definition.untilFirmware.toString(),
      if (definition.requiresCapability != null)
        'cap: ' + definition.requiresCapability.toString(),
    ];
    final details = <String>[
      definition.fieldPath,
      if (constraints.isNotEmpty) constraints.join(' · '),
    ].join('\n');

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        enabled: enabled,
        leading: Icon(_iconFor(definition.valueType)),
        title: Text(definition.label),
        subtitle: showTechnicalDetails ? Text(details) : null,
        isThreeLine: showTechnicalDetails && constraints.isNotEmpty,
        trailing: showTechnicalDetails
            ? _ValueTypeBadge(type: definition.valueType)
            : const Icon(Icons.lock_outline, size: 18),
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
