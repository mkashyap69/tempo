import 'dart:convert';

import 'package:band_ble/band_ble.dart';
import 'package:store/store.dart';

const profileKey = 'profile';

Future<UserProfile?> loadProfile(TempoDb db) async {
  final raw = await db.setting(profileKey);
  if (raw == null) return null;
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return UserProfile(
    birthDate: DateTime.parse(j['birth'] as String),
    heightCm: j['height'] as int,
    weightKg: (j['weight'] as num).toDouble(),
    male: j['male'] as bool,
  );
}

Future<void> saveProfile(TempoDb db, UserProfile p) => db.putSetting(
  profileKey,
  jsonEncode({
    'birth': p.birthDate.toIso8601String(),
    'height': p.heightCm,
    'weight': p.weightKg,
    'male': p.male,
  }),
);
