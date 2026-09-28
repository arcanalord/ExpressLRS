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
    await controller.shutdown();
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('contact add QR and manual routes survive repeated open close',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('mesh_contact_route_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));
    await tester.pumpAndSettle();

    for (var round = 0; round < 4; round++) {
      await tester.tap(find.byTooltip('Добавить контакт'));
      await tester.pumpAndSettle();
      expect(find.text('Добавить контакт'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Показать мой QR'));
      await tester.pumpAndSettle();
      expect(find.text('Мой QR и MM-ID'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Ввести вручную'));
      await tester.pumpAndSettle();
      expect(find.text('Ввести контакт вручную'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('Связь').last);
    await tester.pumpAndSettle();
    expect(find.text('Связь'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await controller.shutdown();
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });


  testWidgets('general location handoff opens map without contact assertion',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('mesh_general_map_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));
    await tester.pumpAndSettle();
    expect(controller.isGeneralChat, isTrue);
    await tester.tap(find.text('Общий чат').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Добавить'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var round = 0; round < 4; round++) {
      final addButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline),
      );
      final addAction = addButton.onPressed;
      expect(addAction, isNotNull);
      addAction?.call();
      await tester.pumpAndSettle();
      expect(find.text('Местоположение'), findsOneWidget);
      final locationTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Местоположение'),
      );
      final locationAction = locationTile.onTap;
      expect(locationAction, isNotNull);
      locationAction?.call();
      await tester.pumpAndSettle();
      expect(find.text('Карта · Общий чат'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final navigationFinder = find.byType(NavigationBar);
      expect(navigationFinder, findsOneWidget);
      final navigation = tester.widget<NavigationBar>(navigationFinder);
      final selectDestination = navigation.onDestinationSelected;
      expect(selectDestination, isNotNull);
      selectDestination?.call(0);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Добавить'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await controller.shutdown();
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

}
