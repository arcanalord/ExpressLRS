import 'package:flutter/material.dart';

import '../../../core/models.dart';
import '../../../platform/android_map_bridge.dart';
import '../../application/mesh_app_controller.dart';

class MapPage extends StatefulWidget {
  const MapPage({required this.controller, super.key});

  final MeshAppController controller;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _packages = AndroidMapPackagesBridge();
  int _reloadToken = 0;
  List<OfflineMapPackage> _offline = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _loadPackages();
  }

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
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

  Future<void> _loadPackages() async {
    try {
      final items = await _packages.listPackages();
      if (mounted) setState(() => _offline = items);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focus = controller.requestedMapFocus;
    final points = controller.mapMessages
        .where((message) => message.mapPoint != null)
        .map((message) {
          final point = message.mapPoint!;
          return <String, Object?>{
            'id': point.id,
            'lat': point.latitude,
            'lon': point.longitude,
            'label': point.label,
            'outgoing': message.outgoing,
          };
        })
        .toList(growable: false);

    return Stack(
      children: [
        Positioned.fill(
          child: AndroidMapSurface(
            points: points,
            reloadToken: _reloadToken,
            focusPoint: focus == null
                ? null
                : (latitude: focus.latitude, longitude: focus.longitude),
            onTapCoordinate: (coord) =>
                _showPointComposer(context, coord.latitude, coord.longitude),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Text(
                        controller.selectedContact == null
                            ? 'Карта · выберите контакт в чатах'
                            : 'Карта · ${controller.selectedContact!.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _showOfflineMaps(context),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(
                    _offline.any((item) => item.active) ? 'Офлайн' : 'Карта',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (controller.mapMessages.isNotEmpty)
          Positioned(
            left: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Text('Точек в чате: ${controller.mapMessages.length}'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showPointComposer(
    BuildContext context,
    double latitude,
    double longitude,
  ) async {
    final label = TextEditingController();
    final note = TextEditingController();
    final controller = widget.controller;
    final canSend = controller.selectedContact != null;
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Точка на карте',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: label,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Например: точка встречи',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                maxLength: 160,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Примечание',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: canSend ? () => Navigator.pop(context, true) : null,
                icon: const Icon(Icons.send_outlined),
                label: Text(
                  canSend
                      ? 'Отправить ${controller.selectedContact!.displayName}'
                      : 'Сначала выберите контакт',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (send == true) {
      try {
        await controller.sendMapPoint(
          latitude: latitude,
          longitude: longitude,
          label: label.text,
          note: note.text,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('Не удалось отправить точку: $error')),
          );
        }
      }
    }
    label.dispose();
    note.dispose();
  }

  Future<void> _showOfflineMaps(BuildContext context) async {
    await _loadPackages();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> refresh() async {
            final items = await _packages.listPackages();
            if (mounted) setState(() => _offline = items);
            setSheetState(() {});
          }

          Future<void> disableActive() async {
            await _packages.setActive(null);
            await refresh();
            if (mounted) setState(() => _reloadToken++);
          }

          Future<void> deletePackage(OfflineMapPackage item) async {
            final confirmed = await showDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Удалить офлайн-карту?'),
                content: Text(
                  '${item.name}\n\nФайл будет удалён только из Mesh Messenger.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Отмена'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            final deleted = await _packages.deletePackage(item.id);
            if (!deleted) return;
            await refresh();
            if (mounted) setState(() => _reloadToken++);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Офлайн-карты',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Один лёгкий файл .pmtiles на район. Точки хранятся отдельно от карты.',
                  ),
                  const SizedBox(height: 12),
                  if (_offline.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Локальные карты ещё не добавлены.'),
                    ),
                  for (final item in _offline)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.active ? Icons.check_circle : Icons.map_outlined,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        item.active
                            ? '${_formatBytes(item.bytes)} · используется'
                            : _formatBytes(item.bytes),
                      ),
                      onTap: item.active
                          ? null
                          : () async {
                              await _packages.setActive(item.id);
                              await refresh();
                              if (mounted) setState(() => _reloadToken++);
                            },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'disable') await disableActive();
                          if (value == 'delete') await deletePackage(item);
                        },
                        itemBuilder: (context) => [
                          if (item.active)
                            const PopupMenuItem(
                              value: 'disable',
                              child: Text('Отключить карту'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить файл'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final imported = await _packages.importPackage();
                      if (imported == null) return;
                      await refresh();
                      if (mounted) setState(() => _reloadToken++);
                    },
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Добавить офлайн-карту'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }
}