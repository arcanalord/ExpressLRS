import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/contact_card.dart';
import '../lib/src/app.dart';
import '../lib/src/application/mesh_app_controller.dart';

void main() {
  testWidgets('rapid tab switching keeps inherited dependencies stable', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('mesh_app_shell_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
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

  testWidgets('contact add QR and manual routes survive repeated open close', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync(
      'mesh_contact_route_gate_',
    );
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
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

  test('QR import keeps a user-selected local name and safe rename preserves identity', () async {
    final root = Directory.systemTemp.createTempSync(
      'mesh_contact_alias_gate_',
    );
    final controller = await MeshAppController.createForWidgetTest(
      storageRoot: root,
    );
    try {
      final raw = const ContactCard(
        mmId: 'mm:peer-alpha',
        displayName: 'Remote advertised name',
        fingerprint: 'fp-001',
        identityPublicKey: 'ik-001',
        agreementPublicKey: 'ak-001',
      ).encode();

      await controller.addContactCard(raw, displayNameOverride: 'Мой Алексей');
      var contact = controller.contacts.singleWhere(
        (item) => item.mmId == 'mm:peer-alpha',
      );
      expect(contact.displayName, 'Мой Алексей');
      expect(contact.fingerprint, 'fp-001');
      expect(contact.identityPublicKey, 'ik-001');
      expect(contact.agreementPublicKey, 'ak-001');

      await controller.renameContact(
        mmId: 'mm:peer-alpha',
        displayName: 'Алексей работа',
      );
      contact = controller.contacts.singleWhere(
        (item) => item.mmId == 'mm:peer-alpha',
      );
      expect(contact.displayName, 'Алексей работа');
      expect(contact.fingerprint, 'fp-001');
      expect(contact.identityPublicKey, 'ik-001');
      expect(contact.agreementPublicKey, 'ak-001');
    } finally {
      await controller.shutdown();
      controller.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });

  testWidgets('general location handoff opens map without contact assertion', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('mesh_general_map_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
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
      expect(find.text('Файл'), findsOneWidget);
      expect(find.text('Местоположение'), findsOneWidget);
      expect(find.text('Медиа'), findsNothing);
      expect(find.textContaining('Голосовое сообщение'), findsNothing);
      final locationTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Местоположение'),
      );
      final locationAction = locationTile.onTap;
      expect(locationAction, isNotNull);
      locationAction?.call();
      await tester.pumpAndSettle();
      expect(find.text('Карта · Общий чат'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Чаты').last);
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

  testWidgets('settings always shows app version', (tester) async {
    final root = Directory.systemTemp.createTempSync('mesh_version_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('О приложении'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    const expectedVersion = String.fromEnvironment(
      'APP_VERSION',
      defaultValue: 'dev',
    );
    const expectedBuild = String.fromEnvironment(
      'APP_BUILD',
      defaultValue: 'local',
    );
    expect(find.text('О приложении'), findsOneWidget);
    expect(
      find.text('Версия $expectedVersion ($expectedBuild)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await controller.shutdown();
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  testWidgets('diagnostics page exposes LR24 state and export action', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('mesh_diagnostics_gate_');
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Диагностика'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Диагностика').last);
    await tester.pumpAndSettle();

    expect(find.text('Диагностика Mesh Messenger'), findsOneWidget);
    expect(find.text('LR24 / радиоканал'), findsOneWidget);
    expect(find.text('Очередь доставки'), findsOneWidget);
    expect(find.text('Экспорт diagnostics.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await controller.shutdown();
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  testWidgets(
    'nearby peer save becomes contact without inherited dependency assertion',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'mesh_nearby_contact_gate_',
      );
      late MeshAppController controller;
      await tester.runAsync(() async {
        controller = await MeshAppController.createForWidgetTest(
          storageRoot: root,
        );
      });
      controller.injectNearbyPeerForTest(
        'mm:nearby-contact',
        label: 'Mesh Nearby',
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(home: AppShell(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Рядом'), findsOneWidget);
      expect(find.text('Mesh Nearby'), findsOneWidget);
      final nearbyTile = find.ancestor(
        of: find.text('Mesh Nearby'),
        matching: find.byType(ListTile),
      );
      expect(nearbyTile, findsOneWidget);
      final add = find.descendant(
        of: nearbyTile,
        matching: find.byTooltip('Добавить контакт'),
      );
      expect(add, findsOneWidget);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Добавить контакт'), findsWidgets);
      expect(tester.takeException(), isNull);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Рабочий контакт');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      // This regression targets the physical red-screen failure during dialog
      // teardown. The physical rc5 report already proved that persistence
      // succeeds even when the old UI lifecycle assertion flashes.
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
      await controller.shutdown();
      controller.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    },
  );
  testWidgets('nearby peer opens direct chat without becoming a contact', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync(
      'mesh_unknown_direct_gate_',
    );
    late MeshAppController controller;
    await tester.runAsync(() async {
      controller = await MeshAppController.createForWidgetTest(
        storageRoot: root,
      );
    });
    controller.injectNearbyPeerForTest(
      'mm:unknown-direct',
      label: 'Nearby Unknown',
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(home: AppShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(controller.hasContact('mm:unknown-direct'), isFalse);
    expect(find.text('Nearby Unknown'), findsOneWidget);

    final tile = find.ancestor(
      of: find.text('Nearby Unknown'),
      matching: find.byType(ListTile),
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(controller.hasContact('mm:unknown-direct'), isFalse);
    expect(controller.selectedPeerMmId, 'mm:unknown-direct');
    expect(find.text('Не в контактах · запрос/прямой чат'), findsOneWidget);
    expect(find.text('Сообщение'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
    await controller.shutdown();
    controller.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
}
