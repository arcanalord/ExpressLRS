import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/application/mesh_app_controller.dart';
import '../lib/src/features/connection/connection_page.dart';

void main() {
  testWidgets('connection page fits mobile and desktop', (tester) async {
    final root = Directory.systemTemp.createTempSync('mesh_ui_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
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
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Автоматический маршрут'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await tester.runAsync(() async {
      await controller.shutdown();
    });
    controller.dispose();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });
}
