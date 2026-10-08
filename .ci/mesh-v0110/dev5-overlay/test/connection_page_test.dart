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

    controller.injectExternalRadioCapabilitiesForTest({
      'networkProtocols': ['MMRP/1'],
      'powerControlAvailable': true,
      'powerControlVersion': 1,
      'powerUnit': 'mW',
      'powerCalibrationSource': 'STOCK_EXPRESSLRS_TARGET',
      'autoPowerAvailable': true,
      'powerSteps': [
        {
          'id': 'P100',
          'nominalMw': 100,
          'radiatedPowerCalibrated': true,
          'normalUiRecommended': true,
          'autoEligible': true,
        },
        {
          'id': 'P250',
          'nominalMw': 250,
          'radiatedPowerCalibrated': true,
          'normalUiRecommended': true,
          'autoEligible': true,
        },
        {
          'id': 'P500',
          'nominalMw': 500,
          'radiatedPowerCalibrated': true,
          'normalUiRecommended': true,
          'autoEligible': true,
        },
        {
          'id': 'P1000',
          'nominalMw': 1000,
          'radiatedPowerCalibrated': true,
          'normalUiRecommended': true,
          'autoEligible': true,
        },
      ],
    });
    await tester.pump();
    expect(find.text('Мощность'), findsOneWidget);
    expect(find.textContaining('По умолчанию 100 mW'), findsOneWidget);
    expect(find.text('100 mW'), findsWidgets);
    expect(find.textContaining('плата не указана'), findsNothing);

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
