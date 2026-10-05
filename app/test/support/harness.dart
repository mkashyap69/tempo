import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:tempo/src/core/notifications.dart';
import 'package:tempo/src/design/theme.dart';
import 'package:tempo/src/state/providers.dart';

import 'fake_sink.dart';

/// Sync that never touches the radio.
class IdleSync extends SyncController {
  IdleSync([this.initial = const SyncStatus()]);
  final SyncStatus initial;
  @override
  SyncStatus build() => initial;
  @override
  Future<SyncStatus> syncNow() async => state;
}

Widget harness(
  TempoDb db,
  Widget child, {
  Brightness b = Brightness.dark,
  SyncStatus sync = const SyncStatus(),
  BluetoothAdapterState adapter = BluetoothAdapterState.on,
}) {
  notificationSink = FakeNotificationSink();
  return _scope(db, child, b: b, sync: sync, adapter: adapter);
}

Widget _scope(
  TempoDb db,
  Widget child, {
  required Brightness b,
  required SyncStatus sync,
  required BluetoothAdapterState adapter,
}) => ProviderScope(
  overrides: [
    dbProvider.overrideWithValue(db),
    syncProvider.overrideWith(() => IdleSync(sync)),
    adapterProvider.overrideWith((ref) => Stream.value(adapter)),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: tempoTheme(b),
    home: child,
  ),
);

/// Pumps until drift's streams settle without waiting on periodic timers.
Future<void> settle(WidgetTester t, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Tears down the tree and DB so no timers are left pending.
Future<void> teardown(WidgetTester t, TempoDb db) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
  await t.runAsync(
    () => db.close().timeout(const Duration(seconds: 2), onTimeout: () {}),
  );
  await t.pump(const Duration(seconds: 1));
}
