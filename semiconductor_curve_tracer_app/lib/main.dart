import 'package:flutter/material.dart';
import 'tracer_screen.dart';

void main() {
  runApp(const CurveTracerApp());
}

class CurveTracerApp extends StatelessWidget {
  const CurveTracerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NSUT Curve Tracer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        primaryColor: const Color(0xFF0F3460),
      ),
      home: const TracerScreen(),
    );
  }
}
