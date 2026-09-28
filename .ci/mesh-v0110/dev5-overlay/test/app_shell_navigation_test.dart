import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/app.dart';
import '../lib/src/application/mesh_app_controller.dart';

void main() {
  testWidgets('rapid tab switching keeps inherited dependencies stable',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('mesh_app_shell_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));
    await tester.pump();

    const labels = <String>['Связь', 'Настройки', 'Карта', 'Чаты'];
    for (var round = 0; round < 12; round++) {
      for (final label in labels) {
        await tester.tap(find.text(label).last);
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await tester.runAsync(() => controller.shutdown());
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
}
