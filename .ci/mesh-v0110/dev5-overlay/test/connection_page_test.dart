import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/application/mesh_app_controller.dart';
import '../lib/src/features/connection/connection_page.dart';

void main() {
  testWidgets('connection page fits mobile and desktop', (tester) async {
    final root = await Directory.systemTemp.createTemp('mesh_ui_gate_');
    final controller = await MeshAppController.create(
      storageRoot: root,
      startRuntime: false,
    );
    addTearDown(() async {
      controller.dispose();
      await root.delete(recursive: true);
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConnectionPage(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Автоматический маршрут'), findsOneWidget);
    expect(find.text('Локальная сеть'), findsOneWidget);
    expect(find.text('Радиомодуль · USB'), findsOneWidget);
    expect(find.text('Meshtastic BLE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Автоматический маршрут'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
