import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_source/health_source.dart';
import 'package:store/store.dart' as st;

import '../core/band_link.dart' show deviceIdKey;
import '../core/data_source.dart';
import '../core/health_reader.dart';
import '../core/profile.dart' show Keys;
import '../core/score_service.dart';
import '../core/minutes.dart' show firstDataMinute;
import '../design/components.dart';
import '../state/providers.dart';
import 'nav.dart';
import 'pairing.dart';

/// Asks for Health access and, when given, makes Health the data source
/// and reads it. Returns false (with a toast saying why) when it couldn't.
/// Used by onboarding and Profile → Data source.
Future<bool> connectHealth(
  BuildContext context,
  WidgetRef ref, {
  HealthReader? reader,
}) async {
  final target = DataSource.platformHealth;
  final r = reader ?? PluginHealthReader();
  HealthConnectResult res;
  try {
    res = await r.connect();
  } catch (e) {
    if (context.mounted) showTempoToast(context, 'Couldn’t open Health: $e');
    return false;
  }
  if (!context.mounted) return false;
  switch (res) {
    case HealthConnectResult.ok:
      break;
    case HealthConnectResult.denied:
      showTempoToast(
        context,
        'Tempo needs to read heart rate, sleep and steps. Allow them in Health Connect.',
      );
      return false;
    case HealthConnectResult.needsInstall:
      showTempoToast(
        context,
        'Install or update Health Connect, then try again.',
      );
      return false;
    case HealthConnectResult.unavailable:
      showTempoToast(context, 'Health Connect isn’t available on this phone.');
      return false;
  }
  final db = ref.read(dbProvider);
  await saveDataSource(db, target);
  // The first read reaches back 90 days and rescores them; it runs in the
  // background of the UI, with its progress on Today's sync pill.
  final status = await ref.read(syncProvider.notifier).syncNow();
  if (!context.mounted) return true;
  final found = await healthFound(db);
  if (!context.mounted) return true;
  final hr = found.contains(HealthKind.heartRate);
  final sleep = found.any((k) => k.isSleep);
  if (status.problem != SyncProblem.none) {
    showTempoToast(
      context,
      'Connected. Tempo couldn’t read ${target.label} yet; it tries again when you open it.',
    );
  } else if (!hr && !sleep) {
    // Apple Health never says whether reading was allowed: no data at all
    // usually means it wasn't.
    showTempoToast(
      context,
      target == DataSource.appleHealth
          ? 'No heart rate or sleep found. Check Settings → Health → Data Access & Devices → Tempo.'
          : 'No heart rate or sleep found yet. Make sure your watch app writes to Health Connect.',
    );
  } else {
    showTempoToast(
      context,
      'Connected to ${target.label}${hr ? '' : ' · no heart rate found yet'}${sleep ? '' : ' · no sleep found yet'}',
    );
  }
  return true;
}

/// Kinds the Health source has given at least once.
Future<Set<HealthKind>> healthFound(st.TempoDb db) async {
  try {
    final m = jsonDecode(
      await db.setting(Keys.healthFound) ?? '{}',
    ) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (e.value == true && HealthKind.values.asNameMap()[e.key] != null)
          HealthKind.values.byName(e.key),
    };
  } catch (_) {
    return {};
  }
}

/// Profile → Data source: switch between the band and this phone's Health
/// store. Old scores stay; baselines restart for the new source.
Future<void> switchDataSource(BuildContext context, WidgetRef ref) async {
  final db = ref.read(dbProvider);
  final now = await loadDataSource(db);
  final health = DataSource.platformHealth;
  if (!context.mounted) return;
  final pick = await pickOption<DataSource>(
    context,
    title: 'Where should Tempo get your data?',
    options: [DataSource.band, health],
    label: (s) => s == DataSource.band
        ? 'Mi Band 6 · direct Bluetooth'
        : '${s.label} · from your watch or ring, read-only',
    selected: now,
  );
  if (pick == null || pick == now || !context.mounted) return;
  final ok = await confirmSheet(
    context,
    title: 'Switch to ${pick.label}?',
    body:
        'Scores you already have stay. Recovery compares nights from one source only, so it learns your normal again from ${pick.label}’s nights (14 needed; Health history counts).',
    action: 'Switch',
  );
  if (!ok || !context.mounted) return;
  if (pick.isHealth) {
    await connectHealth(context, ref);
    return;
  }
  await saveDataSource(db, DataSource.band);
  final first = await firstDataMinute(db, source: DataSource.band);
  if (first != null) await ScoreService(db).recomputeFrom(first);
  if (!context.mounted) return;
  final paired = (await db.setting(deviceIdKey) ?? '').isNotEmpty;
  if (!context.mounted) return;
  if (!paired) {
    await push(context, const PairingScreen());
  } else {
    await ref.read(syncProvider.notifier).syncNow();
  }
}
