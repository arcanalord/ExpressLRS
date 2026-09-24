import 'package:flutter/material.dart';

Future<void> showHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Справка',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Mesh Messenger использует одну очередь сообщений. Для каждого контакта приложение автоматически выбирает доступный канал: радиомодуль, Meshtastic или локальную сеть.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Локальная сеть',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Если два устройства находятся в одной Wi-Fi сети или на одном hotspot, Messenger может находить их и обмениваться сообщениями напрямую без интернета.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Радиомодуль',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Подключается к Android через USB-C OTG. Обычному пользователю достаточно подключить совместимый модуль; технические параметры доступны в диагностике.',
            ),
            const SizedBox(height: 8),
            Text(
              'Для UART используйте логические уровни 3,3 В. Не подавайте 5 В на сигнальные линии радиомодуля.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            const Text(
              'Meshtastic',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Meshtastic остаётся отдельным каналом. При переключении канала сообщение не создаётся заново.',
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Безопасность и технические детали'),
              children: [
                Text(
                  'Контакты в локальной сети подтверждаются сравнением одинакового шестизначного SAS-кода на двух устройствах. MM-ID связан с криптографическим ключом, приватный материал на Android защищается Android Keystore. Транспортные адреса используются только как привязки к контакту.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
