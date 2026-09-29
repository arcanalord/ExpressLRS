import 'package:flutter/material.dart';

final class BestApp extends StatelessWidget {
  const BestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh Messenger Best v1',
      debugShowCheckedModeBanner: false,
      home: const _BestHomePage(),
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    );
  }
}

final class _BestHomePage extends StatelessWidget {
  const _BestHomePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mesh Messenger Best v1',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text('Greenfield vertical slice'),
              SizedBox(height: 24),
              Text('M02 -> M07 -> M12 -> PreparedTransportPacket -> M03'),
              SizedBox(height: 12),
              Text('Release status: experimental / not production'),
            ],
          ),
        ),
      ),
    );
  }
}
