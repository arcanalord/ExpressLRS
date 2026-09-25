import 'dart:async';

import 'package:flutter/material.dart';

import 'data/profile_repository.dart';
import 'models/service_models.dart';
import 'services/native_usb_service.dart';

const appBuildLabel = 'v0.9.0-alpha.10 · Pixel 7a';

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
  final _search = TextEditingController();
  final _bindingPhrase = TextEditingController();
  final _wifiSsid = TextEditingController();
  final _wifiPassword = TextEditingController();
  final _autoWifiSeconds = TextEditingController();
  final _rxUartBaud = TextEditingController();

  List<DeviceProfile> profiles = const [];
  List<UsbDeviceInfo> usbDevices = const [];
  DeviceProfile? selectedCustom;

  bool loading = true;
  bool probing = false;
  bool loadingElrsIndex = false;
  bool loadingElrsTarget = false;
  bool preparingElrs = false;
  bool flashingEsp = false;
  bool _usbRefreshInFlight = false;

  String? error;
  String? regulatoryDomain;
  String lockMode = 'default';
  EspRomProbeResult? probeResult;
  ElrsCatalogIndex? elrsIndex;
  ElrsTargetInfo? selectedElrsTarget;
  ElrsCatalogResult? elrsCatalog;
  ElrsPreparedFirmware? preparedElrs;
  EspFlashResult? flashResult;

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
    _search.dispose();
    _bindingPhrase.dispose();
    _wifiSsid.dispose();
    _wifiPassword.dispose();
    _autoWifiSeconds.dispose();
    _rxUartBaud.dispose();
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
        final selectedId = selectedCustom?.id;
        selectedCustom = selectedId == null
            ? null
            : p.where((item) => item.id == selectedId).firstOrNull;
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
        selectedElrsTarget = null;
        elrsCatalog = null;
        preparedElrs = null;
        flashResult = null;
        regulatoryDomain = null;
        lockMode = 'default';
        _bindingPhrase.clear();
        _wifiSsid.clear();
        _wifiPassword.clear();
        _autoWifiSeconds.clear();
        _rxUartBaud.clear();
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
      selectedElrsTarget = null;
      elrsCatalog = null;
      preparedElrs = null;
      flashResult = null;
      regulatoryDomain = null;
    });

    try {
      final r = await _usb.probeEspRom(deviceName: device.deviceName);
      if (!mounted) return;
      setState(() => probeResult = r);
      if (r.ok) {
        await _fetchElrsIndex();
      }
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

  String? get _detectedPlatform {
    final d = probeResult?.chipDescription?.toLowerCase() ?? '';
    if (d.startsWith('esp8285')) return 'esp8285';
    if (d == 'esp8266ex') return 'esp8266';
    if (d.contains('esp8266 / esp8285')) return null;
    if (d.contains('esp32-s2')) return 'esp32s2';
    if (d.contains('esp32')) return 'esp32';
    return null;
  }

  List<ElrsTargetInfo> get _filteredTargets {
    final index = elrsIndex;
    if (index == null || !index.ok) return const [];
    final platform = _detectedPlatform;
    final q = _search.text.trim().toLowerCase();

    final targets = index.targets.where((t) {
      if (t.role != 'RX') return false;
      if (!t.supportsUart || !t.stableCompatible) return false;
      if (platform != null && t.platform != platform) return false;
      if (q.isEmpty) return true;
      final haystack =
          '${t.productName} ${t.vendor} ${t.band} ${t.targetPath}'.toLowerCase();
      return haystack.contains(q);
    }).toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));
    return targets;
  }

  Future<void> _fetchElrsIndex() async {
    if (loadingElrsIndex) return;
    setState(() => loadingElrsIndex = true);
    try {
      final result = await _usb.fetchOfficialElrsCatalogIndex();
      if (!mounted) return;
      setState(() => elrsIndex = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        elrsIndex = ElrsCatalogIndex(
          status: 'error',
          message: 'Ошибка каталога ExpressLRS: $e',
          targets: const [],
        );
      });
    } finally {
      if (mounted) setState(() => loadingElrsIndex = false);
    }
  }

  Future<void> _selectElrsTarget(ElrsTargetInfo? target) async {
    setState(() {
      selectedElrsTarget = target;
      elrsCatalog = null;
      preparedElrs = null;
      regulatoryDomain = null;
      lockMode = 'default';
      _bindingPhrase.clear();
      _wifiSsid.clear();
      _wifiPassword.clear();
      _autoWifiSeconds.clear();
      _rxUartBaud.clear();
    });
    if (target == null) return;
    await _fetchElrsTarget(target);
  }

  Future<void> _fetchElrsTarget(ElrsTargetInfo target) async {
    if (loadingElrsTarget) return;
    setState(() => loadingElrsTarget = true);
    try {
      final result = await _usb.fetchOfficialElrsTarget(
        targetPath: target.targetPath,
        expectedProductName: target.productName,
        expectedPlatform: target.platform,
        expectedFirmware: target.firmware,
        expectedCommitSha: elrsIndex?.commitSha ?? '',
      );
      if (!mounted) return;
      setState(() => elrsCatalog = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        elrsCatalog = ElrsCatalogResult(
          status: 'error',
          message: 'Ошибка проверки target: $e',
        );
      });
    } finally {
      if (mounted) setState(() => loadingElrsTarget = false);
    }
  }

  Future<void> _prepareElrsFirmware() async {
    final region = regulatoryDomain;
    final target = selectedElrsTarget;
    if (region == null || target == null || preparingElrs) return;

    setState(() {
      preparingElrs = true;
      preparedElrs = null;
      flashResult = null;
    });
    try {
      final result = await _usb.prepareOfficialElrsTarget(
        targetPath: target.targetPath,
        expectedProductName: target.productName,
        expectedPlatform: target.platform,
        expectedFirmware: target.firmware,
        expectedCommitSha: elrsIndex?.commitSha ?? '',
        regulatoryDomain: region,
        bindingPhrase: _bindingPhrase.text.trim().isEmpty
            ? null
            : _bindingPhrase.text.trim(),
        wifiSsid:
            _wifiSsid.text.trim().isEmpty ? null : _wifiSsid.text.trim(),
        wifiPassword:
            _wifiPassword.text.isEmpty ? null : _wifiPassword.text,
        autoWifiSeconds: int.tryParse(_autoWifiSeconds.text.trim()),
        rxUartBaud: int.tryParse(_rxUartBaud.text.trim()),
        lockOnFirstConnection: switch (lockMode) {
          'on' => true,
          'off' => false,
          _ => null,
        },
      );
      if (!mounted) return;
      setState(() => preparedElrs = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        preparedElrs = ElrsPreparedFirmware(
          status: 'error',
          message: 'Ошибка подготовки прошивки: $e',
        );
      });
    } finally {
      if (mounted) setState(() => preparingElrs = false);
    }
  }

  Future<void> _flashPreparedEsp8285() async {
    final device = usbDevices.firstOrNull;
    final target = selectedElrsTarget;
    final prepared = preparedElrs;

    if (device == null ||
        target == null ||
        prepared == null ||
        !prepared.ok ||
        !prepared.hardwarePinned ||
        prepared.manifestPath == null ||
        prepared.sha256 == null ||
        flashingEsp) {
      return;
    }

    final chip = probeResult?.chipDescription ?? '';
    if (!chip.startsWith('ESP8285')) {
      setState(() {
        flashResult = const EspFlashResult(
          status: 'flash_error',
          message: 'Перед записью нужно определить ESP8285 через ROM.',
        );
      });
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Записать прошивку?'),
        content: Text(
          'Модель: ${target.productName}\n'
          'Target: ${target.targetPath}\n'
          'Версия: ${prepared.version ?? '-'}\n'
          'Регион: ${prepared.regulatoryDomain ?? '-'}\n'
          'Адрес: ${prepared.writeOffset ?? '0x0'}\n'
          'Размер: ${prepared.fileSize ?? 0} Б\n\n'
          'Во время записи не отключайте питание и USB. '
          'Проверка alpha.10 подтверждает каждый блок ROM, '
          'но полный readback содержимого пока не выполняется.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Записать'),
          ),
        ],
      ),
    );

    if (approved != true || !mounted) return;

    setState(() {
      flashingEsp = true;
      flashResult = null;
    });

    try {
      final result = await _usb.flashPreparedEsp8285(
        deviceName: device.deviceName,
        manifestPath: prepared.manifestPath!,
        expectedTargetPath: target.targetPath,
        expectedSha256: prepared.sha256!,
      );
      if (!mounted) return;
      setState(() => flashResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        flashResult = EspFlashResult(
          status: 'flash_error',
          message: 'Ошибка записи: $e',
        );
      });
    } finally {
      if (mounted) setState(() => flashingEsp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _filteredTargets;
    final detectedPlatform = _detectedPlatform;

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
            const SizedBox(height: 4),
            const Text(
              appBuildLabel,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
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
                            title: Text('${d.familyLabel}  ${d.vidPid}'),
                            subtitle: Text(
                              [d.product, d.manufacturer, d.deviceName]
                                  .whereType<String>()
                                  .where((e) => e.isNotEmpty)
                                  .join(' · '),
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed:
                              usbDevices.isEmpty || probing ? null : _probe,
                          icon: probing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: Text(
                            probing
                                ? 'Определяю контроллер…'
                                : 'Определить и проверить',
                          ),
                        ),
                        if (probeResult != null) ...[
                          const SizedBox(height: 12),
                          _ProbeResultCard(result: probeResult!),
                        ],
                      ],
                    ),
            ),
            _Section(
              title: '2. Официальные ExpressLRS приёмники',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    detectedPlatform == null
                        ? 'Сначала определите контроллер. Затем каталог отфильтруется автоматически.'
                        : 'Определено: $detectedPlatform. Показываются совместимые RX targets из официального ExpressLRS/Targets.',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: loadingElrsIndex ? null : _fetchElrsIndex,
                    icon: loadingElrsIndex
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      loadingElrsIndex
                          ? 'Обновляю каталог…'
                          : 'Обновить официальный каталог',
                    ),
                  ),
                  if (elrsIndex?.ok == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Stable: ${elrsIndex!.version ?? '-'} · '
                      'в каталоге ${elrsIndex!.targets.length} targets · '
                      'подходит по фильтру ${targets.length}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {
                        if (selectedElrsTarget != null &&
                            !targets.contains(selectedElrsTarget)) {
                          selectedElrsTarget = null;
                          elrsCatalog = null;
                          preparedElrs = null;
                        }
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Поиск модели',
                        hintText: 'BETAFPV, HappyModel, RadioMaster…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<ElrsTargetInfo>(
                      key: ValueKey(
                        selectedElrsTarget?.targetPath ??
                            'dynamic-elrs-target-empty',
                      ),
                      initialValue: selectedElrsTarget,
                      isExpanded: true,
                      items: targets
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                '${t.productName} · ${t.band}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _selectElrsTarget,
                      decoration: const InputDecoration(
                        labelText: 'Модель ELRS приёмника',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else if (elrsIndex != null && !elrsIndex!.ok)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(elrsIndex!.message ?? 'Ошибка каталога'),
                    ),
                ],
              ),
            ),
            if (selectedElrsTarget != null)
              _DynamicElrsTargetSection(
                target: selectedElrsTarget!,
                catalog: elrsCatalog,
                prepared: preparedElrs,
                loading: loadingElrsTarget,
                preparing: preparingElrs,
                regulatoryDomain: regulatoryDomain,
                onRegulatoryChanged: (value) {
                  setState(() {
                    regulatoryDomain = value;
                    preparedElrs = null;
                  });
                },
                onPrepare: _prepareElrsFirmware,
                bindingPhrase: _bindingPhrase,
                wifiSsid: _wifiSsid,
                wifiPassword: _wifiPassword,
                autoWifiSeconds: _autoWifiSeconds,
                rxUartBaud: _rxUartBaud,
                lockMode: lockMode,
                onLockModeChanged: (value) {
                  setState(() {
                    lockMode = value;
                    preparedElrs = null;
                    flashResult = null;
                  });
                },
                onOptionsChanged: () {
                  setState(() {
                    preparedElrs = null;
                    flashResult = null;
                  });
                },
                flashing: flashingEsp,
                flashResult: flashResult,
                onFlash: _flashPreparedEsp8285,
              ),
            _Section(
              title: '3. Собственное / сервисное железо',
              child: DropdownButtonFormField<DeviceProfile>(
                key: ValueKey(selectedCustom?.id ?? 'custom-profile-empty'),
                initialValue: selectedCustom,
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
                onChanged: (p) => setState(() => selectedCustom = p),
                decoration: const InputDecoration(
                  labelText: 'Профиль Mesh / Service Bridge',
                  hintText: 'Не нужен для обычного ELRS-приёмника',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (selectedCustom != null)
              _ProfileCard(profile: selectedCustom!),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (loading) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _DynamicElrsTargetSection extends StatelessWidget {
  const _DynamicElrsTargetSection({
    required this.target,
    required this.catalog,
    required this.prepared,
    required this.loading,
    required this.preparing,
    required this.regulatoryDomain,
    required this.onRegulatoryChanged,
    required this.onPrepare,
    required this.bindingPhrase,
    required this.wifiSsid,
    required this.wifiPassword,
    required this.autoWifiSeconds,
    required this.rxUartBaud,
    required this.lockMode,
    required this.onLockModeChanged,
    required this.onOptionsChanged,
    required this.flashing,
    required this.flashResult,
    required this.onFlash,
  });

  final ElrsTargetInfo target;
  final ElrsCatalogResult? catalog;
  final ElrsPreparedFirmware? prepared;
  final bool loading;
  final bool preparing;
  final String? regulatoryDomain;
  final ValueChanged<String?> onRegulatoryChanged;
  final Future<void> Function() onPrepare;
  final TextEditingController bindingPhrase;
  final TextEditingController wifiSsid;
  final TextEditingController wifiPassword;
  final TextEditingController autoWifiSeconds;
  final TextEditingController rxUartBaud;
  final String lockMode;
  final ValueChanged<String> onLockModeChanged;
  final VoidCallback onOptionsChanged;
  final bool flashing;
  final EspFlashResult? flashResult;
  final Future<void> Function() onFlash;

  @override
  Widget build(BuildContext context) {
    final regions = catalog?.regulatoryOptions.isNotEmpty == true
        ? catalog!.regulatoryOptions
        : target.regulatoryOptions;
    final hasWifi = target.uploadMethods.contains('wifi');
    final pinned = catalog?.hardwarePinned == true;

    return _Section(
      title: '3. Настройки и прошивка',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DiagLine('Модель', target.productName),
          _DiagLine('Платформа', target.platform),
          _DiagLine('Диапазон', target.band),
          _DiagLine('Версия', catalog?.version ?? '-'),
          _DiagLine('Методы', target.uploadMethods.join(', ')),
          if (pinned)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Прошивка, target и layout взяты из одного version-pinned '
                'официального пакета ExpressLRS.',
                style: TextStyle(color: Colors.greenAccent),
              ),
            ),
          if (!target.studioSupported)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Эта модель есть в официальном каталоге, но автоматическая '
                'запись для её контроллера пока не включена.',
                style: TextStyle(color: Colors.orangeAccent),
              ),
            ),
          if (loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (catalog != null && !catalog!.ok)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(catalog!.message ?? 'Ошибка проверки модели'),
            ),
          if (catalog?.ok == true && target.studioSupported) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'region-${target.targetPath}-${regulatoryDomain ?? 'none'}',
              ),
              initialValue: regulatoryDomain,
              decoration: const InputDecoration(
                labelText: 'Радиорегион',
                border: OutlineInputBorder(),
              ),
              items: regions
                  .map(
                    (id) => DropdownMenuItem(
                      value: id,
                      child: Text(_regionLabel(id)),
                    ),
                  )
                  .toList(),
              onChanged: onRegulatoryChanged,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Дополнительные настройки'),
              subtitle: const Text(
                'Необязательно. Оставьте пустым, если менять не нужно.',
                style: TextStyle(fontSize: 12),
              ),
              children: [
                TextField(
                  controller: bindingPhrase,
                  onChanged: (_) => onOptionsChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Binding phrase',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (hasWifi) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: wifiSsid,
                    onChanged: (_) => onOptionsChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Wi-Fi SSID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: wifiPassword,
                    obscureText: true,
                    onChanged: (_) => onOptionsChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Пароль Wi-Fi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: autoWifiSeconds,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onOptionsChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Запуск Wi-Fi через, секунд',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: rxUartBaud,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onOptionsChanged(),
                  decoration: const InputDecoration(
                    labelText: 'UART приёмника, бод',
                    hintText: 'Например 420000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: lockMode,
                  decoration: const InputDecoration(
                    labelText: 'Фиксация режима после первого соединения',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text('Не менять'),
                    ),
                    DropdownMenuItem(
                      value: 'on',
                      child: Text('Включить'),
                    ),
                    DropdownMenuItem(
                      value: 'off',
                      child: Text('Выключить'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onLockModeChanged(value);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Binding phrase и пароль Wi-Fi не выводятся в журнал.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  regulatoryDomain == null || preparing ? null : onPrepare,
              icon: preparing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.inventory_2_outlined),
              label: Text(
                preparing
                    ? 'Готовлю firmware.bin…'
                    : 'Подготовить прошивку',
              ),
            ),
          ],
          if (prepared != null) ...[
            const SizedBox(height: 10),
            if (prepared!.ok) ...[
              const Text(
                'Прошивка подготовлена.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              _DiagLine('Версия', prepared!.version ?? '-'),
              _DiagLine('Регион', _regionLabel(
                prepared!.regulatoryDomain ?? '-',
              )),
              _DiagLine('Адрес', prepared!.writeOffset ?? '-'),
              _DiagLine('Размер', '${prepared!.fileSize ?? 0} Б'),
              _DiagLine('SHA-256', prepared!.sha256 ?? '-'),
              if (prepared!.hardwarePinned)
                const _DiagLine('Пакет', 'firmware + hardware одной версии'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed:
                    flashing || !prepared!.hardwarePinned ? null : onFlash,
                icon: flashing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.memory),
                label: Text(
                  flashing ? 'Записываю…' : 'Записать в контроллер',
                ),
              ),
            ] else
              Text(prepared!.message ?? 'Ошибка подготовки'),
          ],
          if (flashResult != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: flashResult!.ok
                      ? Colors.greenAccent.withValues(alpha: 0.45)
                      : Colors.redAccent.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    flashResult!.ok ? 'Запись завершена' : 'Ошибка записи',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(flashResult!.message),
                  if (flashResult!.ok) ...[
                    const SizedBox(height: 8),
                    _DiagLine(
                      'Блоки',
                      '${flashResult!.blocksWritten ?? 0}',
                    ),
                    _DiagLine(
                      'Проверка',
                      flashResult!.verification == 'rom_block_ack'
                          ? 'подтверждение каждого блока ROM'
                          : (flashResult!.verification ?? '-'),
                    ),
                    if (flashResult!.needsPowerCycle)
                      const Text(
                        'Отключите питание, уберите BOOT→GND и включите '
                        'приёмник обычным способом.',
                        style: TextStyle(color: Colors.greenAccent),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _regionLabel(String id) {
  switch (id) {
    case 'ISM_2400':
      return '2.4 ГГц — ISM';
    case 'EU_CE_2400':
      return '2.4 ГГц — EU CE / LBT';
    case 'FCC_915':
      return '915 МГц — FCC';
    case 'AU_915':
      return '915 МГц — Австралия';
    case 'EU_868':
      return '868 МГц — Европа';
    case 'IN_866':
      return '866 МГц — Индия';
    case 'US_433':
      return '433 МГц — США';
    case 'US_433_WIDE':
      return '433 МГц — США, wide';
    case 'EU_433':
      return '433 МГц — Европа';
    case 'AU_433':
      return '433 МГц — Австралия';
    default:
      return id;
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
          if (profile.elrsTargetPath != null)
            _Line('ELRS target', profile.elrsTargetPath!),
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
          'Как пользоваться',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '1. Подключите USB-UART к UART приёмника: TX → RX, RX → TX, GND → GND.',
        ),
        SizedBox(height: 8),
        Text(
          '2. Введите ESP-приёмник в ROM-загрузчик его штатным способом. '
          'Для многих ESP8285 это BOOT pad → GND при подаче питания.',
        ),
        SizedBox(height: 8),
        Text(
          '3. Нажмите «Определить и проверить». Android при необходимости запросит '
          'разрешение на USB. Программа откроет UART 115200 и отправит безопасную '
          'команду ESP ROM SYNC. Флеш-память при этой проверке не изменяется.',
        ),
        SizedBox(height: 12),
        Text(
          'После определения контроллера программа загружает официальный каталог '
          'ExpressLRS Targets и оставляет совместимые приёмники. '
          'Для пустой платы конкретную модель всё равно нужно выбрать вручную.',
        ),
      ],
    );
  }
}
