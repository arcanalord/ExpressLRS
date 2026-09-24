import 'package:flutter/material.dart';

import '../../../platform/android_map_bridge.dart';
import 'offline_maps_sheet.dart';
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
  MapSourceState _source = const MapSourceState(
    mode: 'online',
    selectedId: null,
    hasOffline: false,
  );

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
      final results = await Future.wait<Object>([
        _packages.listPackages(),
        _packages.sourceState(),
      ]);
      final items = results[0] as List<OfflineMapPackage>;
      final source = results[1] as MapSourceState;
      if (mounted) {
        setState(() {
          _offline = items;
          _source = source;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleSourceMode() async {
    final next = _source.isOffline ? 'online' : 'offline';
    if (next == 'offline' && !_source.hasOffline) {
      await _showOfflineMaps(context);
      return;
    }
    try {
      await _packages.setSourceMode(next);
      if (!mounted) return;
      await _loadPackages();
      if (!mounted) return;
      setState(() => _reloadToken++);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось переключить карту: $error')),
      );
    }
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
                  onPressed: _toggleSourceMode,
                  onLongPress: () => _showOfflineMaps(context),
                  icon: Icon(
                    _source.isOffline
                        ? Icons.download_for_offline_outlined
                        : Icons.public_outlined,
                  ),
                  label: Text(_source.isOffline ? 'Офлайн' : 'Онлайн'),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Карты',
                  onPressed: () => _showOfflineMaps(context),
                  icon: const Icon(Icons.layers_outlined),
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

    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => OfflineMapsSheet(
        packages: _packages,
        initialItems: _offline,
      ),
    );

    if (changed == true && mounted) {
      await _loadPackages();
      if (!mounted) return;
      setState(() => _reloadToken++);
    }
  }

}