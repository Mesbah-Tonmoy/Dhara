import 'package:flutter/material.dart';

void main() {
  runApp(const DharaApp());
}

/// Root widget. Phase 0 only proves that an empty window opens;
/// the real theme comes from the approved design tokens in Phase 6.
class DharaApp extends StatelessWidget {
  const DharaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dhara',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF8B6CFF),
        scaffoldBackgroundColor: const Color(0xFF06070C),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Dhara', key: Key('app-title')),
        ),
      ),
    );
  }
}
