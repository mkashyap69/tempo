import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'src/app.dart';
import 'src/core/background.dart';
import 'src/core/home_widgets.dart';
import 'src/core/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    // iOS state restoration so CoreBluetooth can relaunch us for the band.
    await FlutterBluePlus.setOptions(restoreState: true);
  }
  for (final step in [
    scheduleBackgroundSync,
    () => HomeWidget.setAppGroupId(widgetAppGroup),
    TempoNotifications.instance.init,
  ]) {
    try {
      await step();
    } catch (e) {
      debugPrint('startup: $e');
    }
  }
  runApp(const ProviderScope(child: TempoApp()));
}
