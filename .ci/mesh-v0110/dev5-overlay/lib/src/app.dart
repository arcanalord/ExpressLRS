import 'package:flutter/material.dart';

import 'application/mesh_app_controller.dart';
import 'features/chats/chats_page.dart';
import 'features/connection/connection_page.dart';
import 'features/help/help_sheet.dart';
import 'features/map/map_page.dart';
import 'features/settings/settings_page.dart';

class MeshMessengerApp extends StatelessWidget {
  const MeshMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mesh Messenger',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF84A8FF),
      ),
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<MeshAppController> _future = MeshAppController.create();
  MeshAppController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MeshAppController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Ошибка запуска: ${snapshot.error}')),
          );
        }
        final controller = snapshot.data;
        if (controller == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _controller ??= controller;
        return AppShell(controller: controller);
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({required this.controller, super.key});

  final MeshAppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChatsPage(
        controller: widget.controller,
        onOpenMapPoint: (point) {
          widget.controller.requestMapFocus(point);
          setState(() => index = 1);
        },
      ),
      MapPage(controller: widget.controller),
      ConnectionPage(controller: widget.controller),
      const SettingsPage(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = Row(
      children: [
        if (wide)
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.chat_bubble_outline),
                label: Text('Чаты'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                label: Text('Карта'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.hub_outlined),
                label: Text('Связь'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                label: Text('Настройки'),
              ),
            ],
          ),
        Expanded(child: pages[index]),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Messenger'),
        actions: [
          TextButton.icon(
            onPressed: () => showHelpSheet(context),
            icon: const Icon(Icons.help_outline),
            label: const Text('Справка'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: 'Чаты',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  label: 'Карта',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  label: 'Связь',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Настройки',
                ),
              ],
            ),
    );
  }
}
