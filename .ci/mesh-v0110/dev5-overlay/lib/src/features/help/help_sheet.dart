import 'package:flutter/material.dart';

import '../../application/mesh_app_controller.dart';

Future<void> showHelpSheet(
  BuildContext context, {
  required MeshAppController controller,
}) {
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
              'Справка Mesh Messenger',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const _HelpSection(
              title: 'Чаты и запросы',
              text:
                  'Узел из раздела «Рядом» можно открыть без автоматического добавления в контакты. '
                  'Неизвестный peer может прислать текстовый запрос: его можно прочитать и ответить. '
                  'Ответ не создаёт Contact и не делает peer Verified. Вложения, карта и управляющие '
                  'действия для неизвестного peer остаются ограничены до явного добавления контакта.',
            ),
            const _HelpSection(
              title: 'Как читать состояние связи',
              text:
                  'Mesh Messenger разделяет три уровня: устройство/радио, peer/route и delivery. '
                  'USB ready означает только готовность локального интерфейса. Peer ready подтверждает '
                  'удалённый узел. FILE/1 ready означает, что путь передачи файла восстановлен. '
                  'Ни один из этих статусов сам по себе не равен «Доставлено».',
            ),
            const _HelpSection(
              title: 'Файлы',
              text:
                  'Передача использует один M05/FILE/1 поток: manifest, HAVE/MISSING, недостающие '
                  'logical blocks, ACK, полная SHA-256 проверка и COMPLETE. После временного обрыва '
                  'передача должна продолжаться с тем же transferId и только с недостающих блоков.',
            ),
            const _HelpSection(
              title: 'Локальная сеть',
              text:
                  'Если два устройства находятся в одной Wi-Fi сети или на одном hotspot, '
                  'Messenger может находить их и обмениваться сообщениями напрямую без интернета.',
            ),
            const _HelpSection(
              title: 'Радиомодуль',
              text:
                  'LR24-F подключается к Android через USB-C OTG. Для stock LR24 приложение не '
                  'показывает выдуманные RSSI/SNR: доступны только реально измеряемые признаки '
                  'готовности, RTT, peer age, счётчики TX/RX и состояния очередей.',
            ),
            Text(
              'Для UART используйте логические уровни 3,3 В. Не подавайте 5 В на сигнальные линии радиомодуля.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            const _HelpSection(
              title: 'Meshtastic',
              text:
                  'Meshtastic остаётся отдельным транспортом. При переключении транспорта логическое '
                  'сообщение не создаётся заново.',
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Безопасность'),
              children: [
                Text(
                  'Discovered peer, Contact и Verified — разные состояния. QR/SAS используется для '
                  'проверки identity. Текущую verification нельзя обозначать как полноценное production '
                  'E2EE до завершения M07 production-provider gates.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              initiallyExpanded: controller.advancedMode,
              title: Text(
                controller.advancedMode
                    ? 'Инженерный режим · включён'
                    : 'Инженерный режим',
              ),
              children: [
                Text(
                  'Включается в Настройки → Инженерный режим. Он добавляет сырые состояния transport, '
                  'peer age, RTT, TX/RX counters, QoS queues, FILE/1 route state, logical block size, '
                  'журналы и расширенную диагностику. Он не меняет маршрутизацию, trust или delivery '
                  'semantics — только показывает больше доказательных данных.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Если связь пропала, старые значения не должны выглядеть как LIVE. Смотрите peer age, '
                  'route state и timestamp/журнал, а не только факт USB-подключения.',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'При ошибке: Настройки → Диагностика → Экспорт diagnostics.txt. '
              'Перед физическим PASS не считайте CI/BUILD PASS доказательством радиоканала или E2EE.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(text),
      ],
    ),
  );
}
