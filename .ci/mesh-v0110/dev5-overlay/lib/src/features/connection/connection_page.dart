import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../application/mesh_app_controller.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({required this.controller, super.key});

  final MeshAppController controller;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ConnectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  String _deliveryState(DeliveryState state) => switch (state) {
    DeliveryState.queued => 'В очереди',
    DeliveryState.sending => 'Отправка',
    DeliveryState.waitingAck => 'Ждём ACK',
    DeliveryState.noRoute => 'Нет маршрута',
    DeliveryState.retryWait => 'Ожидание повтора',
    DeliveryState.delivered => 'Доставлено',
    DeliveryState.expired => 'Истёк TTL',
    DeliveryState.failed => 'Ошибка',
    DeliveryState.cancelled => 'Отменено',
  };

  String _transportState(String state) => switch (state) {
    'ready' => 'Готово',
    'connected' => 'Подключено',
    'connecting' || 'starting' => 'Подключение…',
    'handshaking' || 'probing' => 'Проверка радиомодуля…',
    'crsf' => 'ELRS / CRSF',
    'unknown' => 'Протокол не определён',
    'permission' => 'Нужно разрешение',
    'scanning' => 'Поиск…',
    'error' => 'Ошибка',
    'offline' || 'disconnected' => 'Отключено',
    'unavailable' => 'Недоступно',
    _ => state,
  };

  String _recipientLabel(MeshAppController controller, String mmId) {
    for (final contact in controller.contacts) {
      if (contact.mmId == mmId) return contact.displayName;
    }
    return 'Контакт';
  }

  String _transportLabel(String? id) => switch (id) {
    'lan' => 'Локальная сеть',
    'ep2-uart' => 'Радиомодуль',
    'meshtastic' => 'Meshtastic',
    null => 'Канал выбирается',
    _ => 'Другой канал',
  };

  String _messageKind(String messageClass) => switch (messageClass) {
    'map_point' => 'Точка',
    _ => 'Сообщение',
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pending = controller.pendingDeliveries;
    final ep2Active = !{
      'unavailable',
      'offline',
      'disconnected',
    }.contains(controller.ep2State);
    final anyRouteReady =
        controller.lanReady || controller.ep2Connected || controller.radioConnected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Связь',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  anyRouteReady ? 'Всё работает' : 'Автоматический маршрут',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  anyRouteReady
                      ? 'Есть доступный канал связи. Сообщения пойдут по подходящему маршруту автоматически.'
                      : 'Одна очередь сообщений. Подключи доступный канал — приложение выберет маршрут само.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusPill(
                      icon: Icons.wifi,
                      label: 'LAN',
                      ready: controller.lanReady,
                      detail: controller.lanPeers.isEmpty
                          ? null
                          : '${controller.lanPeers.length}',
                    ),
                    _StatusPill(
                      icon: Icons.usb,
                      label: 'Радио',
                      ready: controller.ep2Connected,
                    ),
                    _StatusPill(
                      icon: Icons.bluetooth,
                      label: 'Meshtastic',
                      ready: controller.radioConnected,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _LanCard(controller: controller, stateLabel: _transportState),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(controller.ep2Connected ? Icons.usb : Icons.usb_off),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Радиомодуль · USB',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _transportState(controller.ep2State),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Подключение через USB-C OTG и совместимый USB-UART адаптер.',
                ),
                if (!controller.hasEp2Uart) ...[
                  const SizedBox(height: 10),
                  const Text('USB-радиомодуль доступен в Android-сборке.'),
                ] else ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: controller.busy
                            ? null
                            : controller.refreshEp2Devices,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить USB'),
                      ),
                      if (controller.ep2Connected)
                        OutlinedButton.icon(
                          onPressed: controller.refreshEp2Info,
                          icon: const Icon(Icons.info_outline),
                          label: const Text('INFO / STATS'),
                        ),
                      if (controller.ep2Connected)
                        OutlinedButton.icon(
                          onPressed: controller.runRadioSelfTest,
                          icon: const Icon(Icons.health_and_safety_outlined),
                          label: const Text('Самопроверка'),
                        ),
                      if (controller.ep2Connected)
                        FilledButton.tonalIcon(
                          onPressed: controller.startEp2WifiUpdate,
                          icon: const Icon(Icons.wifi_tethering_outlined),
                          label: const Text('Wi-Fi обновление'),
                        ),
                      if (ep2Active)
                        OutlinedButton.icon(
                          onPressed: controller.disconnectEp2,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Отключить'),
                        ),
                    ],
                  ),
                  if (controller.ep2Protocol != 'unknown' ||
                      controller.ep2Baud != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${controller.ep2Protocol == 'unknown' ? 'Определение протокола' : controller.ep2Protocol}'
                      '${controller.ep2Baud == null ? '' : ' · ${controller.ep2Baud} бод'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (controller.mmUartActive) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${controller.externalRadioFamily ?? 'Радио'} · '
                      '${controller.externalBoardId ?? 'плата не указана'} · '
                      '${controller.externalRadioSupportsMmrp ? 'MMRP/1' : 'без MMRP/1'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (controller.ep2LocalNode != null ||
                      controller.ep2Firmware != null ||
                      controller.ep2Profile != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Узел ${controller.ep2LocalNode ?? '—'} · ${controller.ep2Firmware ?? '—'} · ${controller.ep2Profile ?? '—'}',
                    ),
                  ],
                  if (controller.ep2Connected && !controller.mmUartActive) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: controller.pingEp2Neighbor,
                          icon: const Icon(Icons.network_ping),
                          label: const Text('PING соседнего узла'),
                        ),
                        if (controller.ep2PingResult != null)
                          Chip(label: Text(controller.ep2PingResult!)),
                      ],
                    ),
                  ],
                  if (controller.ep2InfoNotice?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      controller.ep2InfoNotice!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (controller.ep2Rssi10 != null ||
                      controller.ep2Snr10 != null ||
                      controller.ep2RttMs != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'RSSI ${controller.ep2Rssi10 == null ? '—' : (controller.ep2Rssi10! / 10).toStringAsFixed(1)} dBm'
                      ' · SNR ${controller.ep2Snr10 == null ? '—' : (controller.ep2Snr10! / 10).toStringAsFixed(1)} dB'
                      ' · RTT ${controller.ep2RttMs ?? '—'} мс',
                    ),
                    Text(
                      'TX ${controller.ep2TxCount ?? 0} · RX ${controller.ep2RxCount ?? 0} · retry ${controller.ep2RetryCount ?? 0} · loss ${controller.ep2LossCount ?? 0}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (controller.ep2Error?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      controller.ep2Error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (controller.ep2OtaNotice?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      controller.ep2OtaNotice!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (controller.ep2OtaSsid != null) ...[
                    const SizedBox(height: 10),
                    Card(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wi-Fi обновление готово',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              'Сеть: ' + (controller.ep2OtaSsid ?? '—'),
                            ),
                            SelectableText(
                              'Пароль: ' + (controller.ep2OtaPassword ?? '—'),
                            ),
                            SelectableText(
                              'Адрес: ' + (controller.ep2OtaUrl ?? 'http://10.0.0.1'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (controller.ep2Devices.isEmpty)
                    Text(
                      'Подключи радиомодуль по USB — поиск и подключение выполняются автоматически.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...controller.ep2Devices.map(
                      (device) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.usb),
                        title: Text(device.name),
                        subtitle: Text(
                          device.permission
                              ? 'USB-устройство · готово к автоподключению'
                              : 'USB-устройство · Android запросит разрешение',
                        ),
                        trailing: FilledButton(
                          onPressed: controller.busy ||
                                  {'connecting', 'handshaking', 'probing', 'permission'}
                                      .contains(controller.ep2State) ||
                                  controller.ep2Connected
                              ? null
                              : () => controller.connectEp2(device.deviceId),
                          child: Text(
                            {'unknown', 'error'}.contains(controller.ep2State)
                                ? 'Повторить'
                                : 'Авто',
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UART диагностика',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text('Протокол: ${controller.ep2DetectedProtocol}'),
                          Text('RX: ${controller.ep2RxBytes} байт'),
                          if (controller.ep2LastHex.isNotEmpty)
                            SelectableText('HEX: ${controller.ep2LastHex}'),
                        ],
                      ),
                    ),
                  ),
                  _LogExpansion(
                    title: 'Диагностика радиомодуля',
                    lines: controller.ep2Log,
                    onClear: controller.clearEp2Log,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _MeshtasticCard(controller: controller, stateLabel: _transportState),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Исходящие',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            Badge(
              label: Text('${pending.length}'),
              child: const Icon(Icons.outbox_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Нет ожидающих сообщений'),
            ),
          )
        else
          ...pending.map(
            (item) => Card(
              child: ListTile(
                leading: const Icon(Icons.schedule_send_outlined),
                title: Text(
                  '${_messageKind(item.messageClass)} → ${_recipientLabel(controller, item.recipientMmId)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_transportLabel(item.selectedTransportId)),
                trailing: Text(_deliveryState(item.state)),
              ),
            ),
          ),
      ],
    );
  }
}

class _LanCard extends StatelessWidget {
  const _LanCard({required this.controller, required this.stateLabel});

  final MeshAppController controller;
  final String Function(String) stateLabel;

  @override
  Widget build(BuildContext context) {
    final needsPermission =
        controller.lanPermissionRequired && !controller.lanPermissionGranted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(controller.lanReady ? Icons.wifi : Icons.wifi_off),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Локальная сеть',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(stateLabel(controller.lanState)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Находит устройства Mesh Messenger в той же Wi-Fi сети или hotspot и обменивается сообщениями напрямую. Интернет не нужен.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Это устройство: ${controller.ownDeviceLabel}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Данные устройства'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(controller.ownMmId),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Fingerprint: ${controller.ownFingerprint}'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    controller.identitySeedStorage == 'android-keystore-aes-gcm'
                        ? 'Приватные ключи защищены Android Keystore'
                        : 'Хранилище ключей: ${controller.identitySeedStorage}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (controller.lanLocalAddresses.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'IP: ${controller.lanLocalAddresses.join(', ')}',
                    ),
                  ),
              ],
            ),
            if (needsPermission) ...[
              const SizedBox(height: 12),
              Text(
                'Android требует разрешение на доступ к локальной сети.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: controller.requestLanPermission,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Разрешить локальную сеть'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.lanReady
                        ? controller.announceLan
                        : controller.startLan,
                    icon: const Icon(Icons.radar),
                    label: Text(
                      controller.lanReady ? 'Найти сейчас' : 'Запустить',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.busy ? null : controller.restartLan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Перезапустить'),
                  ),
                ],
              ),
            ],
            if (controller.lanError?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                controller.lanError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.lanNotice?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(controller.lanNotice!),
            ],
            const SizedBox(height: 12),
            Text(
              controller.lanPeers.isEmpty
                  ? 'Другие устройства Mesh Messenger пока не найдены.'
                  : 'Устройства в сети: ${controller.lanPeers.length}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (controller.lanPeers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Чтобы добавить устройство в контакты, сравните одинаковый шестизначный код на обоих телефонах.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              ...controller.lanPeers.map((peer) {
                final inContacts = controller.hasContact(peer.mmId);
                final verified = controller.contacts.any(
                  (contact) => contact.mmId == peer.mmId && contact.verified,
                );
                final probePending = controller.lanProbePending.contains(
                  peer.mmId,
                );
                final rtt = controller.lanRttMs[peer.mmId];
                final pairing = controller.pairingFor(peer.mmId);
                final age = DateTime.now().toUtc().difference(peer.lastSeen);
                final seen = age.inSeconds < 2
                    ? 'сейчас'
                    : '${age.inSeconds} с назад';
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.devices_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  peer.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Видно $seen',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (verified)
                            const Tooltip(
                              message: 'Контакт проверен',
                              child: Icon(Icons.verified_user_outlined),
                            )
                          else if (inContacts)
                            const Tooltip(
                              message: 'Контакт добавлен, ключи не проверены',
                              child: Icon(Icons.shield_outlined),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: probePending
                                ? null
                                : () => controller.probeLanPeer(peer.mmId),
                            icon: const Icon(Icons.network_ping),
                            label: Text(
                              probePending
                                  ? 'Проверяем…'
                                  : rtt == null
                                  ? 'Проверить связь'
                                  : 'Связь · $rtt мс',
                            ),
                          ),
                          if (pairing == null && !verified)
                            FilledButton.tonalIcon(
                              onPressed: () => controller.startLanPairing(peer),
                              icon: const Icon(Icons.key_outlined),
                              label: Text(
                                inContacts
                                    ? 'Проверить ключи'
                                    : 'Проверить и добавить',
                              ),
                            )
                          else if (verified)
                            Text(
                              'Проверенный контакт',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                        ],
                      ),
                      if (pairing != null) ...[
                        const SizedBox(height: 12),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  pairing.sas.isEmpty
                                      ? 'Обмениваемся и проверяем ключи…'
                                      : 'Сравните код на обоих телефонах',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (pairing.sas.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SelectableText(
                                    pairing.sas,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Код должен быть одинаковым на двух устройствах. Не подтверждайте, если он отличается.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: pairing.localConfirmed
                                            ? null
                                            : () => controller
                                                  .confirmLanPairing(peer.mmId),
                                        icon: const Icon(
                                          Icons.verified_outlined,
                                        ),
                                        label: Text(
                                          pairing.localConfirmed
                                              ? 'Подтверждено здесь'
                                              : 'Коды совпадают',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => controller
                                            .cancelLanPairing(peer.mmId),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Отмена'),
                                      ),
                                    ],
                                  ),
                                  if (pairing.localConfirmed &&
                                      !pairing.remoteConfirmed) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Ждём подтверждения на втором устройстве.',
                                    ),
                                  ],
                                  if (!pairing.localConfirmed &&
                                      pairing.remoteConfirmed) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Второе устройство уже подтвердило код.',
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ] else if (verified) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Fingerprint: ${controller.contacts.where((contact) => contact.mmId == peer.mmId).firstOrNull?.fingerprint ?? '—'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
            _LogExpansion(
              title: 'Диагностика LAN',
              lines: controller.lanLog,
              onClear: controller.clearLanLog,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeshtasticCard extends StatelessWidget {
  const _MeshtasticCard({required this.controller, required this.stateLabel});

  final MeshAppController controller;
  final String Function(String) stateLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  controller.radioConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Meshtastic BLE',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(stateLabel(controller.radioState)),
              ],
            ),
            if (!controller.hasAndroidMeshtastic) ...[
              const SizedBox(height: 10),
              const Text('BLE доступен в Android-сборке.'),
            ] else ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : controller.scanMeshtastic,
                    icon: const Icon(Icons.radar),
                    label: const Text('Найти устройства'),
                  ),
                  if (controller.radioConnected)
                    OutlinedButton.icon(
                      onPressed: controller.disconnectMeshtastic,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Отключить'),
                    ),
                ],
              ),
              if (controller.radioError != null) ...[
                const SizedBox(height: 10),
                Text(
                  controller.radioError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (controller.radioDevices.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...controller.radioDevices.map(
                  (device) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.memory),
                    title: Text(device.name),
                    subtitle: Text(device.id),
                    trailing: FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.connectMeshtastic(device.id),
                      child: const Text('Подключить'),
                    ),
                  ),
                ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Диагностика BLE'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Android API: ${controller.radioDiagnostics['sdkInt'] ?? '—'}',
                        ),
                        Text(
                          'Bluetooth: ${controller.radioDiagnostics['bluetoothEnabled'] == true ? 'включён' : 'выключен/неизвестно'}',
                        ),
                        Text(
                          'Разрешения: ${controller.radioPermissions['granted'] == true ? 'выданы' : 'не выданы'}',
                        ),
                      ],
                    ),
                  ),
                  _LogBox(
                    lines: controller.radioLog,
                    onClear: controller.clearRadioLog,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.ready,
    this.detail,
  });

  final IconData icon;
  final String label;
  final bool ready;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(
        '$label · ${ready ? 'готов' : 'не готов'}${detail == null ? '' : ' · $detail'}',
      ),
    );
  }
}

class _LogExpansion extends StatelessWidget {
  const _LogExpansion({
    required this.title,
    required this.lines,
    required this.onClear,
  });

  final String title;
  final List<String> lines;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(title),
      children: [_LogBox(lines: lines, onClear: onClear)],
    );
  }
}

class _LogBox extends StatelessWidget {
  const _LogBox({required this.lines, required this.onClear});

  final List<String> lines;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: lines.isEmpty ? null : onClear,
            child: const Text('Очистить'),
          ),
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: lines.isEmpty
              ? const Text('Событий пока нет')
              : SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(lines.join('\n')),
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
