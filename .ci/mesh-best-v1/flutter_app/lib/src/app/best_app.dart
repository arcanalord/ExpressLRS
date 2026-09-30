import 'package:flutter/material.dart';

import 'best_hil_page.dart';

final class BestApp extends StatelessWidget {
  const BestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh Messenger Best v1',
      debugShowCheckedModeBanner: false,
      home: const BestHilPage(),
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    );
  }
}
