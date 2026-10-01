import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_build_info.dart';
import '../../../core/models.dart';
import '../../application/mesh_app_controller.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({required this.controller, super.key});

  final MeshAppController controller;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(
      ClipboardData(text: widget.controller.diagnosticSnapshotJson()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Диагностика скопирована')));
  }

  Future<void> _exportDiagnostics() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final saved = await widget.controller.exportDiagnosticSnapshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? 'Сохранение отменено' : 'Диагностика сохранена',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить диагностику: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pending = controller.pendingDeliveries;
    final peer = controller.lr24PeerMmId;

    return Scaffold(
      appBar: AppBar(title: const Text('Диагностика Mesh Messenger')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('Версия ${MeshAppBuildInfo.display}'),
          const SizedBox(height: 12),
          _DiagnosticCard(
            title: 'LR24 / радиоканал',
            children: [
              _Line(
                'USB',
                controller.lr24Connected ? 'готов' : controller.lr24State,
              ),
              _Line(
                'Peer',
                controller.lr24PeerReachable
                    ? 'подтверждён${peer == null ? '' : ' · $peer'}'
                    : 'не подтверждён',
              ),
              _Line(
                'RTT',
                controller.lr24RttMs == null
                    ? '—'
                    : '${controller.lr24RttMs} мс',
              ),
              _Line(
                'TX',
                '${controller.lr24TxFrames} кадров · ${controller.lr24TxBytes} байт',
              ),
              _Line(
                'RX',
                '${controller.lr24RxFrames} кадров · ${controller.lr24RxBytes} байт',
              ),
              _Line('Ошибки кадров', '${controller.lr24BadFrames}'),
              if (controller.lr24Error?.isNotEmpty == true)
                _Line('Последняя ошибка', controller.lr24Error!),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: controller.lr24Connected
                    ? controller.probeLr24Peer
                    : null,
                icon: const Icon(Icons.network_ping),
                label: const Text('Проверить связь'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DiagnosticCard(
            title: 'Очередь доставки',
            children: [
              _Line('Ожидает', '${pending.length}'),
              if (pending.isEmpty)
                const Text('Нет ожидающих сообщений.')
              else
                for (final item in pending.take(20)) _DeliveryLine(item: item),
            ],
          ),
          const SizedBox(height: 12),
          _DiagnosticCard(
            title: 'Файлы / M05',
            children: [
              _Line('Состояние', controller.fileTransferState),
              _Line(
                'Blocks',
                '${controller.fileTransferAckedChunks}/${controller.preparedFileChunks ?? 0}',
              ),
              _Line(
                'Logical block',
                controller.preparedFileChunkSize == null
                    ? '—'
                    : '${controller.preparedFileChunkSize} байт',
              ),
              _Line(
                'FILE/1 route',
                controller.lr24FileRouteAvailable ? 'ready' : 'waiting',
              ),
              if (controller.advancedMode &&
                  controller.preparedFileTransferId != null)
                _Line('transferId', controller.preparedFileTransferId!),
              if (controller.advancedMode &&
                  controller.preparedFileSha256 != null)
                _Line('SHA-256', controller.preparedFileSha256!),
              if (controller.fileTransferNotice?.isNotEmpty == true)
                _Line('Событие', controller.fileTransferNotice!),
              if (controller.lastReceivedFileName?.isNotEmpty == true)
                _Line('Последний полученный', controller.lastReceivedFileName!),
            ],
          ),
          if (controller.advancedMode) ...[
            const SizedBox(height: 12),
            _DiagnosticCard(
              title: 'Инженерный режим',
              children: [
                _Line('LR24 state', controller.lr24State),
                _Line(
                  'Peer age',
                  controller.lr24PeerAgeMs == null
                      ? '—'
                      : '${controller.lr24PeerAgeMs} мс',
                ),
                _Line(
                  'QoS control/text/file',
                  '${controller.lr24QosPendingControl}/'
                  '${controller.lr24QosPendingText}/'
                  '${controller.lr24QosPendingFile}',
                ),
                _Line(
                  'Route layers',
                  'USB ${controller.lr24Connected ? 'ready' : 'off'} · '
                  'peer ${controller.lr24PeerReachable ? 'ready' : 'pending'} · '
                  'FILE/1 ${controller.lr24FileRouteAvailable ? 'ready' : 'waiting'}',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Важно: TX/RX transport counters и TX_RESULT не означают application Delivered. '
                  'Для stock LR24 RSSI/SNR не показываются, если транспорт их реально не предоставляет.',
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _DiagnosticCard(
            title: 'Журнал LR24',
            children: [
              if (controller.lr24Log.isEmpty)
                const Text('Журнал пока пуст.')
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      controller.lr24Log.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DiagnosticCard(
            title: 'Экспорт',
            children: [
              const Text(
                'Файл не содержит payload сообщений и фильтрует поля '
                'password/secret/private/seed/token/keymaterial.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _exporting ? null : _exportDiagnostics,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                      _exporting ? 'Сохранение…' : 'Экспорт diagnostics.txt',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyDiagnostics,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Копировать'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('$label: $value'),
  );
}

class _DeliveryLine extends StatelessWidget {
  const _DeliveryLine({required this.item});
  final DeliveryEnvelope item;
  @override
  Widget build(BuildContext context) {
    final compactId = item.messageId.length <= 18
        ? item.messageId
        : '${item.messageId.substring(0, 18)}…';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '$compactId · ${item.state.name} · попыток ${item.attempts}'
        '${item.selectedTransportId == null ? '' : ' · ${item.selectedTransportId}'}'
        '${item.lastError == null ? '' : ' · ${item.lastError}'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
