import 'dart:async';

import 'package:flutter/material.dart';

import 'data/profile_repository.dart';
import 'models/service_models.dart';
import 'services/native_usb_service.dart';

void main() => runApp(const ServiceStudioApp());

class ServiceStudioApp extends StatelessWidget {
  const ServiceStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP Service Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const ServiceHomePage(),
    );
  }
}

class ServiceHomePage extends StatefulWidget {
  const ServiceHomePage({super.key});

  @override
  State<ServiceHomePage> createState() => _ServiceHomePageState();
}

class _ServiceHomePageState extends State<ServiceHomePage> with WidgetsBindingObserver {
  final _profiles = ProfileRepository();
  final _usb = NativeUsbService();

  List<DeviceProfile> profiles = const [];
  List<UsbDeviceInfo> usbDevices = const [];
  DeviceProfile? selected;
  bool loading = true;
  String? error;
  StreamSubscription<UsbSnapshot>? _usbSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usbSub = _usb.watchDevices().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          usbDevices = snapshot.devices;
          error = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => error = 'USB: $e');
      },
    );
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usbSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshUsbOnly();
    }
  }

  Future<void> _refreshUsbOnly() async {
    try {
      final u = await _usb.listDevices();
      if (!mounted) return;
      setState(() {
        usbDevices = u;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'USB: $e');
    }
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await _profiles.load();
      final u = await _usb.listDevices();
      setState(() {
        profiles = p;
        usbDevices = u;
        selected ??= p.isEmpty ? null : p.first;
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP Service Studio'),
        actions: [
          IconButton(
            tooltip: 'Справка',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const _HelpSheet(),
            ),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Универсальное обслуживание устройств',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Контроллер и радиочип обслуживаются независимо. '
              'Для Mesh Messenger сначала определяется профиль устройства и его возможности.',
            ),
            const SizedBox(height: 18),
            _Section(
              title: '1. Подключение',
              child: usbDevices.isEmpty
                  ? const Text('USB-устройство не найдено')
                  : Column(
                      children: usbDevices
                          .map(
                            (d) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.usb),
                              title: Text('${d.familyLabel}  ${d.vidPid}'),
                              subtitle: Text(
                                [d.product, d.manufacturer, d.deviceName]
                                    .whereType<String>()
                                    .where((e) => e.isNotEmpty)
                                    .join(' · '),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            _Section(
              title: '2. Что обслуживаем',
              child: DropdownButtonFormField<DeviceProfile>(
                initialValue: profile,
                isExpanded: true,
                items: profiles
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (p) => setState(() => selected = p),
                decoration: const InputDecoration(
                  labelText: 'Профиль устройства',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (profile != null) _ProfileCard(profile: profile),
            _Section(
              title: '3. Действие',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => _notYet('Определение устройства'),
                    icon: const Icon(Icons.search),
                    label: const Text('Определить и проверить'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _notYet('Обновление пакетом'),
                    icon: const Icon(Icons.system_update_alt),
                    label: const Text('Обновить устройство'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _notYet('Диагностика радиомодуля'),
                    icon: const Icon(Icons.settings_input_antenna),
                    label: const Text('Радиомодуль'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _notYet('Режим восстановления'),
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('Восстановление / ручной режим'),
                  ),
                ],
              ),
            ),
            if (error != null)
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (loading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  void _notYet(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name: каркас готов, аппаратный адаптер подключается следующим этапом')),
    );
  }

  String _serviceLabel(String raw) {
    switch (raw) {
      case 'register_service':
        return 'настройка и диагностика по SPI';
      case 'microcode_if_supported':
        return 'обновление микрокода, если поддерживается';
      case 'capability_driven':
        return 'по возможностям устройства';
      case 'probe_first':
        return 'сначала безопасное определение';
      default:
        return raw;
    }
  }

  String _accessLabel(String raw) {
    switch (raw) {
      case 'controller_spi_or_service_bridge':
        return 'через контроллер или Service Bridge';
      case 'service_bridge_spi':
        return 'через ESP32-S3 Service Bridge';
      default:
        return raw;
    }
  }

  String _protocolLabel(String raw) {
    switch (raw) {
      case 'ep2_link_ascii':
        return 'EP2 LINK';
      case 'crsf_diagnostics':
        return 'CRSF (диагностика)';
      case 'mm_uart_1':
        return 'MM-UART/1';
      case 'ss_bridge_1':
        return 'SS-BRIDGE/1';
      default:
        return raw;
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final DeviceProfile profile;

  @override
  Widget build(BuildContext context) {
    final controller = profile.controller;
    final radio = profile.radio;
    return _Section(
      title: 'Профиль',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Line('Устройство', profile.name),
          _Line('Контроллер', controller?['family']?.toString() ?? 'нет'),
          _Line('Радиочип', radio['family']?.toString() ?? 'неизвестно'),
          _Line('Сервис радио', _serviceLabel(radio['serviceKind']?.toString() ?? '-')),
          _Line('Доступ к радио', _accessLabel(radio['access']?.toString() ?? '-')),
          _Line('Протоколы', profile.hostProtocols.map(_protocolLabel).join(', ')),
          const SizedBox(height: 10),
          ...profile.notes.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $n'),
              )),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.name, this.value);
  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(name, style: const TextStyle(color: Colors.white60))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: const [
        Text('Как устроена программа', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        SizedBox(height: 12),
        Text(
          'Обычный режим работает по профилю устройства. Программа сама должна знать, '
          'какой контроллер, радиочип, способ входа в загрузчик и какие операции допустимы.',
        ),
        SizedBox(height: 12),
        Text(
          'Контроллер ESP и радиочип SX/LR — разные объекты. '
          'ESP получает основную прошивку. SX1276/SX1262/SX1280 обычно обслуживаются '
          'по SPI без отдельного firmware.bin. Для LR-семейств отдельное обновление '
          'радиочипа разрешается только если это подтверждено его профилем и возможностями.',
        ),
        SizedBox(height: 12),
        Text(
          'Голый радиомодуль подключается через ESP32-S3 Service Bridge: '
          'телефон → USB → Service Bridge → SPI → радиомодуль.',
        ),
        SizedBox(height: 12),
        Text(
          'Для Mesh Messenger целевой host-протокол — MM-UART/1. '
          'EP2 LINK ASCII остаётся совместимым режимом для текущего железа.',
        ),
      ],
    );
  }
}
