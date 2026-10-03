import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/spike_screen.dart';

void main() => runApp(const ProviderScope(child: TempoApp()));

class TempoApp extends StatelessWidget {
  const TempoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tempo',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const SpikeScreen(),
  );
}
