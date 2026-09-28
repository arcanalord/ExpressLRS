import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/application/mesh_app_controller.dart';
import '../lib/src/features/connection/connection_page.dart';

void main() {
  testWidgets('connection page fits mobile and desktop', (tester) async {
    print('WIDGET_GATE: start');
    final root = await Directory.systemTemp.createTemp('mesh_ui_gate_');
    print('WIDGET_GATE: temp-ready');
    final controller = await MeshAppController.createForWidgetTest(
      storageRoot: root,
    );
    print('WIDGET_GATE: controller-ready');

    await tester.binding.setSurfaceSize(const Size(390, 844));
    print('WIDGET_GATE: mobile-size');
    print('WIDGET_GATE: before-pumpWidget');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConnectionPage(controller: controller)),
      ),
    );
    print('WIDGET_GATE: after-pumpWidget');
    await tester.pump(const Duration(milliseconds: 300));
    print('WIDGET_GATE: after-mobile-pump');
    expect(find.text('Автоматический маршрут'), findsOneWidget);
    expect(find.text('Локальная сеть'), findsOneWidget);
    expect(find.text('Радиомодуль · USB'), findsOneWidget);
    expect(find.text('Meshtastic BLE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    print('WIDGET_GATE: mobile-assertions-ok');
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    print('WIDGET_GATE: desktop-size');
    await tester.pump(const Duration(milliseconds: 300));
    print('WIDGET_GATE: after-desktop-pump');
    expect(find.text('Автоматический маршрут'), findsOneWidget);
    expect(tester.takeException(), isNull);

    print('WIDGET_GATE: desktop-assertions-ok');
    await tester.pumpWidget(const SizedBox.shrink());
    print('WIDGET_GATE: unmounted');
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    print('WIDGET_GATE: before-shutdown');
    await controller.shutdown();
    print('WIDGET_GATE: after-shutdown');
    controller.dispose();
    if (await root.exists()) {
      await root.delete(recursive: true);
      print('WIDGET_GATE: root-deleted');
    }
  });
}
