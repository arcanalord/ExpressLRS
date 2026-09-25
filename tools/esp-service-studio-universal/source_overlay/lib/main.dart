import 'dart:async';

import 'package:flutter/material.dart';

import 'data/profile_repository.dart';
import 'models/service_models.dart';
import 'services/native_usb_service.dart';

const appBuildLabel = 'v0.9.0-alpha.5 · Pixel 7a';

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

class _ServiceHomePageState extends State<ServiceHomePage>
    with WidgetsBindingObserver {
  final _profiles = ProfileRepository();
  final _usb = NativeUsbService();

  List<DeviceProfile> profiles = const [];
  List<UsbDeviceInfo> usbDevices = const [];
  DeviceProfile? selected;

  bool loading = true;
  bool probing = false;
  bool _usbRefreshInFlight = false;

  String? error;
  EspRomProbeResult? probeResult;

  StreamSubscription<UsbSnapshot>? _usbSub;
  Timer? _usbPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _usbSub = _usb.watchDevices().listen(
      (snapshot) {
        if (!mounted) return;
        _applyUsbDevices(snapshot.devices);
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          _refreshUsbOnly,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => error = 'USB: $e');
      },
    );

    _startUsbPolling();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usbPollTimer?.cancel();
    _usbSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startUsbPolling();
      _refreshUsbOnly();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _usbPollTimer?.cancel();
      _usbPollTimer = null;
    }
  }

  void _startUsbPolling() {
    _usbPollTimer?.cancel();
    _usbPollTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _refreshUsbOnly(),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final p = await _profiles.load();
      final u = await _usb.listDevices();

      if (!mounted) return;

      setState(() {
        profiles = p;
        usbDevices = u;
        selected ??= p.isEmpty ? null : p.first;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _refreshUsbOnly() async {
    if (_usbRefreshInFlight) return;
    _usbRefreshInFlight = true;

    try {
      final u = await _usb.listDevices();
      if (!mounted) return;
      _applyUsbDevices(u);
      if (error?.startsWith('USB:') ?? false) {
        setState(() => error = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'USB: $e');
    } finally {
      _usbRefreshInFlight = false;
    }
  }

  void _applyUsbDevices(List<UsbDeviceInfo> next) {
    if (_sameUsbList(usbDevices, next)) return;

    setState(() {
      usbDevices = next;
      if (next.isEmpty) {
        probeResult = null;
        probing = false;
      }
    });
  }

  bool _sameUsbList(List<UsbDeviceInfo> a, List<UsbDeviceInfo> b) {
    if (a.length != b.length) return false;

    String key(UsbDeviceInfo d) =>
        '${d.deviceName}|${d.vendorId}|${d.productId}|${d.interfaceCount}|${d.hasPermission}';

    final aa = a.map(key).toList()..sort();
    final bb = b.map(key).toList()..sort();

    for (var i = 0; i < aa.length; i++) {
      if (aa[i] != bb[i]) return false;
    }

    return true;
  }

  Future<void> _probe() async {
    if (probing) return;

    final device = usbDevices.firstOrNull;
    if (device == null) {
      setState(() {
        probeResult = const EspRomProbeResult(
          status: 'no_device',
          message: 'Сначала подключите USB-UART',
        );
      });
      return;
    }

    setState(() {
      probing = true;
      probeResult = null;
      error = null;
    });

    try {
      final r = await _usb.probeEspRom(
        deviceName: device.deviceName,
      );

      if (!mounted) return;

      setState(() => probeResult = r);

      await _refreshUsbOnly();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        probeResult = EspRomProbeResult(
          status: 'probe_error',
          message: 'Ошибка проверки: $e',
        );
      });
    } finally {
      if (mounted) setState(() => probing = false);
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
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              appBuildLabel,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Контроллер и радиочип обслуживаются независимо. '
              'Сначала определяем подключение и проверяем устройство.',
            ),
            const SizedBox(height: 18),
            _Section(
              title: '1. Подключение',
              child: usbDevices.isEmpty
                  ? const _UsbEmpty()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...usbDevices.map(
                          (d) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.usb,
                              color: Colors.lightGreenAccent,
                            ),
                            title: Text(
                              '${d.familyLabel}  ${d.vidPid}',
                            ),
                            subtitle: Text(
                              [
                                d.product,
                                d.manufacturer,
                                d.deviceName,
                              ]
                                  .whereType<String>()
                                  .where((e) => e.isNotEmpty)
                                  .join(' · '),
                            ),
                            trailing: d.hasPermission
                                ? const Icon(
                                    Icons.lock_open,
                                    size: 18,
                                  )
                                : null,
                          ),
                        ),
                        const Text(
                          'Состояние USB обновляется автоматически.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
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
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (p) => setState(() {
                  selected = p;
                  probeResult = null;
                }),
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
                    onPressed:
                        usbDevices.isEmpty || probing ? null : _probe,
                    icon: probing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      probing
                          ? 'Проверяю USB и ESP ROM…'
                          : 'Определить и проверить',
                    ),
                  ),
                  if (probeResult != null) ...[
                    const SizedBox(height: 12),
                    _ProbeResultCard(result: probeResult!),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _notYet(
                      'Обновление пакетом',
                    ),
                    icon: const Icon(Icons.system_update_alt),
                    label: const Text('Обновить устройство'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _notYet(
                      'Диагностика радиомодуля',
                    ),
                    icon: const Icon(
                      Icons.settings_input_antenna,
                    ),
                    label: const Text('Радиомодуль'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _notYet(
                      'Режим восстановления',
                    ),
                    icon: const Icon(
                      Icons.build_circle_outlined,
                    ),
                    label: const Text(
                      'Восстановление / ручной режим',
                    ),
                  ),
                ],
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            if (loading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  void _notYet(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$name: будет подключено после проверки USB-Serial',
        ),
      ),
    );
  }
}

class _ProbeResultCard extends StatelessWidget {
  const _ProbeResultCard({required this.result});

  final EspRomProbeResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.ok;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok
              ? Colors.greenAccent.withValues(alpha: 0.45)
              : Colors.orangeAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.info_outline,
                color: ok
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok ? 'ESP ROM отвечает' : 'Проверка не завершена',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.message),
          if (result.ok) ...[
            const SizedBox(height: 10),
            if (result.chipDescription != null)
              _DiagLine('Контроллер', result.chipDescription!),
            if (result.chipMagic != null)
              _DiagLine('ROM magic', result.chipMagic!),
            if (result.chipId != null)
              _DiagLine('Chip ID', result.chipId!),
            if (result.mac != null)
              _DiagLine('MAC', result.mac!),
            if (result.flashId != null)
              _DiagLine('Flash ID', result.flashId!),
            if (result.flashSize != null)
              _DiagLine('Flash', result.flashSize!),
            if (result.flashEmbedded == true)
              const _DiagLine('Flash', 'встроена в ESP8285'),
          ],
          if (result.driver != null) ...[
            const SizedBox(height: 8),
            Text(
              'USB: ${result.driver} · '
              '${result.baudRate ?? 115200} бод · '
              'получено ${result.bytesRead ?? 0} Б',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagLine extends StatelessWidget {
  const _DiagLine(this.name, this.value);

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              name,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsbEmpty extends StatelessWidget {
  const _UsbEmpty();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.usb_off,
          color: Colors.white54,
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'USB-устройство не найдено. '
            'Подключите адаптер — список обновится автоматически.',
          ),
        ),
      ],
    );
  }
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

String _controllerLabel(String raw) {
  switch (raw.toLowerCase()) {
    case 'esp8285':
      return 'ESP8285';
    case 'esp32s3':
      return 'ESP32-S3';
    default:
      return raw.toUpperCase();
  }
}

String _radioLabel(String raw) {
  switch (raw.toLowerCase()) {
    case 'sx1280':
      return 'SX1280';
    case 'sx1280_family':
      return 'SX1280 / SX1281';
    case 'lr1121':
      return 'LR1121';
    case 'lr2021':
      return 'LR2021';
    case 'auto':
      return 'автоопределение';
    default:
      return raw.toUpperCase();
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
          _Line(
            'Контроллер',
            controller == null
                ? 'нет'
                : _controllerLabel(
                    controller['family']?.toString() ?? '-',
                  ),
          ),
          _Line(
            'Радиочип',
            _radioLabel(
              radio['family']?.toString() ?? 'неизвестно',
            ),
          ),
          _Line(
            'Сервис радио',
            _serviceLabel(
              radio['serviceKind']?.toString() ?? '-',
            ),
          ),
          _Line(
            'Доступ к радио',
            _accessLabel(
              radio['access']?.toString() ?? '-',
            ),
          ),
          _Line(
            'Протоколы',
            profile.hostProtocols
                .map(_protocolLabel)
                .join(', '),
          ),
          const SizedBox(height: 10),
          ...profile.notes.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $n'),
            ),
          ),
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
          SizedBox(
            width: 110,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white60,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
  });

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
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        28,
      ),
      children: const [
        Text(
          'Как проверить EP2',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '1. TX USB-UART подключите к RX EP2, RX — к TX, GND — к GND.',
        ),
        SizedBox(height: 8),
        Text(
          '2. Для входа в ROM-загрузчик замкните BOOT pad на GND и подайте питание. '
          'После включения перемычку можно убрать.',
        ),
        SizedBox(height: 8),
        Text(
          '3. Нажмите «Определить и проверить». Android при необходимости запросит '
          'разрешение на USB. Программа откроет UART 115200 и отправит безопасную '
          'команду ESP ROM SYNC. Флеш-память при этой проверке не изменяется.',
        ),
        SizedBox(height: 12),
        Text(
          'Успех означает, что цепочка Pixel → USB-UART → ESP ROM работает. '
          'SX1280 при этой операции не прошивается и не изменяется.',
        ),
      ],
    );
  }
}
