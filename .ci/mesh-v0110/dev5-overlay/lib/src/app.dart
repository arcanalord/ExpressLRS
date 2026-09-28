import 'dart:async';

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
        scaffoldBackgroundColor: const Color(0xFF090C12),
        cardTheme: CardThemeData(
          color: const Color(0xFF151A24).withValues(alpha: 0.78),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFFB9C7E8).withValues(alpha: 0.14),
            ),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF0E131D).withValues(alpha: 0.82),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0E131D).withValues(alpha: 0.86),
          indicatorColor: const Color(0xFF84A8FF).withValues(alpha: 0.18),
          elevation: 0,
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: const Color(0xFF0E131D).withValues(alpha: 0.76),
          indicatorColor: const Color(0xFF84A8FF).withValues(alpha: 0.18),
          elevation: 0,
        ),
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
  late final Future<MeshAppController> _future;
  MeshAppController? _controller;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _future = MeshAppController.create().then((controller) {
      if (_disposed) {
        unawaited(controller.shutdown());
        controller.dispose();
      } else {
        _controller = controller;
      }
      return controller;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.shutdown());
      controller.dispose();
      _controller = null;
    }
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
  bool _mapActivated = false;

  void _selectIndex(int value) {
    if (!mounted || value < 0 || value > 3) return;
    if (value == index && (value != 1 || _mapActivated)) return;
    setState(() {
      index = value;
      if (value == 1) _mapActivated = true;
    });
  }

  void _openMapComposerAfterOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectIndex(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChatsPage(
        controller: widget.controller,
        onOpenMapPoint: (point) {
          widget.controller.requestMapFocus(point);
          _selectIndex(1);
        },
        onOpenMapComposer: _openMapComposerAfterOverlay,
      ),
      _mapActivated
          ? MapPage(controller: widget.controller)
          : const SizedBox.shrink(),
      ConnectionPage(controller: widget.controller),
      SettingsPage(controller: widget.controller),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = Row(
      children: [
        if (wide)
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: _selectIndex,
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
        Expanded(
          child: IndexedStack(
            index: index,
            sizing: StackFit.expand,
            children: pages,
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Messenger'),
        actions: [
          IconButton(
            tooltip: 'Справка',
            onPressed: () => showHelpSheet(context),
            icon: const Icon(Icons.help_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _selectIndex,
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
