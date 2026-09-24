import 'package:flutter/material.dart';

import '../../../platform/android_map_bridge.dart';

class OfflineMapsSheet extends StatefulWidget {
  const OfflineMapsSheet({
    required this.packages,
    required this.initialItems,
    super.key,
  });

  final AndroidMapPackagesBridge packages;
  final List<OfflineMapPackage> initialItems;

  @override
  State<OfflineMapsSheet> createState() => _OfflineMapsSheetState();
}

class _OfflineMapsSheetState extends State<OfflineMapsSheet> {
  late List<OfflineMapPackage> _items;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final items = await widget.packages.listPackages();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось прочитать список карт: $error');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Ошибка карты: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    await _run(() async {
      final imported = await widget.packages.importPackage();
      if (imported == null || !mounted) return;
      Navigator.pop(context, true);
    });
  }

  Future<void> _activate(OfflineMapPackage item) async {
    await _run(() async {
      await widget.packages.setActive(item.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    });
  }

  Future<void> _disable() async {
    await _run(() async {
      await widget.packages.setActive(null);
      if (!mounted) return;
      Navigator.pop(context, true);
    });
  }

  Future<void> _delete(OfflineMapPackage item) async {
    final confirmed = await showDialog<bool>(
      context: context,
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
    if (confirmed != true || !mounted) return;

    await _run(() async {
      final deleted = await widget.packages.deletePackage(item.id);
      if (!deleted) {
        throw StateError('Не удалось удалить файл');
      }
      if (!mounted) return;
      if (item.active) {
        Navigator.pop(context, true);
        return;
      }
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Офлайн-карты', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Лёгкий .pmtiles на нужный район. Если локальная карта не откроется, приложение попробует лёгкую OSM-карту, а без сети оставит рабочую сетку.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Material(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('Локальные карты ещё не добавлены.'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item.active
                                  ? Icons.check_circle
                                  : Icons.map_outlined,
                            ),
                            title: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.active
                                  ? '${_formatBytes(item.bytes)} · используется'
                                  : _formatBytes(item.bytes),
                            ),
                            onTap: _busy || item.active
                                ? null
                                : () => _activate(item),
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (value) async {
                                if (value == 'disable') await _disable();
                                if (value == 'delete') await _delete(item);
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
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_open_outlined),
                label: const Text('Добавить офлайн-карту'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }
}
