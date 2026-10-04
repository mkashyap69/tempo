import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/background.dart';
import 'src/ui/home.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    // iOS state restoration so CoreBluetooth can relaunch us for the band.
    await FlutterBluePlus.setOptions(restoreState: true);
  }
  try {
    await scheduleBackgroundSync();
  } catch (e) {
    debugPrint('background sync not scheduled: $e');
  }
  runApp(const ProviderScope(child: TempoApp()));
}

class TempoApp extends StatelessWidget {
  const TempoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tempo',
    theme: tempoTheme(),
    darkTheme: tempoTheme(),
    home: const Home(),
  );
}
