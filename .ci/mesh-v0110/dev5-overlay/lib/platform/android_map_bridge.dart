import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class OfflineMapPackage {
  const OfflineMapPackage({
    required this.id,
    required this.name,
    required this.bytes,
    required this.active,
  });

  final String id;
  final String name;
  final int bytes;
  final bool active;

  factory OfflineMapPackage.fromMap(Map<Object?, Object?> raw) =>
      OfflineMapPackage(
        id: raw['id'] as String,
        name: raw['name'] as String? ?? raw['id'] as String,
        bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
        active: raw['active'] == true,
      );
}

final class AndroidMapPackagesBridge {
  static const _channel = MethodChannel('org.fpvclub.mesh/maps');

  bool get supported => defaultTargetPlatform == TargetPlatform.android;

  Future<List<OfflineMapPackage>> listPackages() async {
    if (!supported) return const [];
    final raw =
        await _channel.invokeListMethod<Object?>('listPackages') ?? const [];
    return raw
        .whereType<Map>()
        .map((item) => OfflineMapPackage.fromMap(item.cast<Object?, Object?>()))
        .toList();
  }

  Future<OfflineMapPackage?> importPackage() async {
    if (!supported) return null;
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'importPackage',
    );
    return raw == null ? null : OfflineMapPackage.fromMap(raw);
  }

  Future<void> setActive(String? id) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('setActive', {'id': id});
  }

  Future<bool> deletePackage(String id) async {
    if (!supported) return false;
    return await _channel.invokeMethod<bool>('deletePackage', {'id': id}) ??
        false;
  }
}

final class AndroidMapSurface extends StatefulWidget {
  const AndroidMapSurface({
    required this.points,
    required this.onTapCoordinate,
    this.focusPoint,
    this.reloadToken = 0,
    super.key,
  });

  final List<Map<String, Object?>> points;
  final ValueChanged<({double latitude, double longitude})> onTapCoordinate;
  final ({double latitude, double longitude})? focusPoint;
  final int reloadToken;

  @override
  State<AndroidMapSurface> createState() => _AndroidMapSurfaceState();
}

class _AndroidMapSurfaceState extends State<AndroidMapSurface> {
  MethodChannel? _channel;
  bool _ready = false;

  @override
  void didUpdateWidget(covariant AndroidMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.points, widget.points)) _pushPoints();
    if (oldWidget.focusPoint != widget.focusPoint &&
        widget.focusPoint != null) {
      _focus(widget.focusPoint!);
    }
    if (oldWidget.reloadToken != widget.reloadToken) {
      _reload();
    }
  }

  Future<void> _reload() async {
    _ready = false;
    await _channel?.invokeMethod<void>('reload');
  }

  Future<void> _pushPoints() async {
    if (!_ready) return;
    await _channel?.invokeMethod<void>('setPoints', {
      'json': jsonEncode(widget.points),
    });
  }

  Future<void> _focus(({double latitude, double longitude}) point) async {
    if (!_ready) return;
    await _channel?.invokeMethod<void>('focus', {
      'lat': point.latitude,
      'lon': point.longitude,
      'zoom': 15.0,
    });
  }

  Future<void> _onMapReady() async {
    if (!mounted) return;
    _ready = true;
    await _pushPoints();
    final focus = widget.focusPoint;
    if (focus != null) await _focus(focus);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(
        child: Text('Карта MapLibre сейчас подключена для Android'),
      );
    }
    return AndroidView(
      viewType: 'org.fpvclub.mesh/mapview',
      onPlatformViewCreated: (id) {
        final channel = MethodChannel('org.fpvclub.mesh/mapview/$id');
        channel.setMethodCallHandler((call) async {
          if (call.method == 'mapReady') {
            await _onMapReady();
            return;
          }
          if (call.method != 'mapTap') return;
          final args = (call.arguments as Map).cast<Object?, Object?>();
          final lat = (args['lat'] as num).toDouble();
          final lon = (args['lon'] as num).toDouble();
          widget.onTapCoordinate((latitude: lat, longitude: lon));
        });
        _channel = channel;
        _ready = false;
      },
    );
  }
}