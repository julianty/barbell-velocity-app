import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() {
  runApp(const BarbellVelocityApp());
}

class BarbellVelocityApp extends StatelessWidget {
  const BarbellVelocityApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2A78D6); // viz series-1 blue
    return MaterialApp(
      title: 'Barbell Velocity',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: seed, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}
