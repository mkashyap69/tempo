/// History fetch: commands, framing and record parsers.
///
/// Every opcode, type code and record layout here is `TODO(verify)`. They
/// come from public protocol descriptions; confirm each against a capture
/// in docs/packets/ and replace the synthetic tests with golden ones.
library;

import 'dart:typed_data';

/// Data types the band can stream. Codes are TODO(verify).
enum FetchType {
  activity(0x01, 'activity'),
  stress(0x14, 'stress'), // TODO(verify)
  spo2(0x25, 'spo2'), // TODO(verify)
  pai(0x0d, 'pai'), // TODO(verify)
  /// Workouts started on the band (Workout app). One summary per fetch;
  /// the reply's start time is that workout's start. TODO(verify)
  workouts(0x05, 'workouts');

  const FetchType(this.code, this.key);
  final int code;

  /// Stable name for sync cursors.
  final String key;
}

abstract final class FetchCommands {
  static const startOpcode = 0x01; // TODO(verify)
  static const transferOpcode = 0x02; // TODO(verify)
  static final transfer = Uint8List.fromList([transferOpcode]);

  /// Ack after a completed transfer. Some firmware deletes acknowledged data
  /// from the band, so the sync does not send it until verified.
  static final ack = Uint8List.fromList([0x03, 0x09]); // TODO(verify)

  /// `01 | type | year u16 LE | month | day | hour | minute | second | tz`.
  /// [encodeBandTime] has no seconds byte; this inserts it before tz.
  /// A 7-byte time (tz where the second should be) got `10 01 02` on
  /// V1.0.6.20. TODO(verify)
  static Uint8List start(FetchType t, DateTime since) {
    final time = encodeBandTime(since);
    return Uint8List.fromList([
      startOpcode,
      t.code,
      ...time.sublist(0, 6),
      since.toLocal().second,
      time[6],
    ]);
  }
}

/// `year u16 LE, month, day, hour, minute, tz` where tz is the UTC offset in
/// quarter hours. TODO(verify)
List<int> encodeBandTime(DateTime t) {
  final l = t.toLocal();
  final tz = l.timeZoneOffset.inMinutes ~/ 15;
  return [
    l.year & 0xff,
    l.year >> 8,
    l.month,
    l.day,
    l.hour,
    l.minute,
    tz & 0xff,
  ];
}

/// Inverse of [encodeBandTime] (seconds are dropped). Null if too short.
DateTime? decodeBandTime(List<int> b, [int offset = 0]) {
  if (b.length < offset + 7) return null;
  final year = b[offset] | (b[offset + 1] << 8);
  final tz = b[offset + 6].toSigned(8);
  final utc = DateTime.utc(
    year,
    b[offset + 2],
    b[offset + 3],
    b[offset + 4],
    b[offset + 5],
  ).subtract(Duration(minutes: tz * 15));
  return utc.toLocal();
}

/// Reply to [FetchCommands.start] on the control characteristic:
/// `[0x10, 0x01, status, count u32 LE, start time…]`. TODO(verify)
final class FetchStartReply {
  const FetchStartReply(this.ok, this.count, this.start);
  final bool ok;
  final int count;
  final DateTime? start;

  static FetchStartReply? parse(List<int> d) {
    if (d.length < 3 || d[0] != 0x10 || d[1] != FetchCommands.startOpcode)
      return null;
    if (d[2] != 0x01 || d.length < 7)
      return const FetchStartReply(false, 0, null);
    final count = d[3] | (d[4] << 8) | (d[5] << 16) | (d[6] << 24);
    return FetchStartReply(true, count, decodeFetchTime(d, 7));
  }
}

/// Fetch replies use `year u16 LE, month, day, hour, minute, second, tz`.
/// [decodeBandTime] is the 7-byte form (no seconds). TODO(verify) spo2 still
/// uses that shorter form.
DateTime? decodeFetchTime(List<int> b, [int offset = 0]) {
  if (b.length < offset + 8) return null;
  final year = b[offset] | (b[offset + 1] << 8);
  final tz = b[offset + 7].toSigned(8);
  final utc = DateTime.utc(
    year,
    b[offset + 2],
    b[offset + 3],
    b[offset + 4],
    b[offset + 5],
    b[offset + 6],
  ).subtract(Duration(minutes: tz * 15));
  return utc.toLocal();
}

/// `[0x10, 0x02, status]` once the band has sent everything. TODO(verify)
bool? parseTransferDone(List<int> d) =>
    d.length >= 3 && d[0] == 0x10 && d[1] == FetchCommands.transferOpcode
    ? d[2] == 0x01
    : null;

/// Joins data notifications. Byte 0 of each is a rolling sequence number;
/// the rest is payload. Records may straddle packets. TODO(verify)
final class ChunkAssembler {
  final _buf = BytesBuilder(copy: false);
  int? _lastSeq;
  int gaps = 0;

  void add(List<int> packet) {
    if (packet.isEmpty) return;
    final seq = packet[0];
    if (_lastSeq != null && seq != ((_lastSeq! + 1) & 0xff)) gaps++;
    _lastSeq = seq;
    _buf.add(packet.sublist(1));
  }

  Uint8List take() => _buf.takeBytes();

  /// Payload bytes received so far.
  int get length => _buf.length;
}

final class ActivityRecord {
  const ActivityRecord(this.ts, this.kind, this.intensity, this.steps, this.hr);
  final DateTime ts;
  final int kind, intensity, steps;
  final int? hr;
}

/// Activity on V1.0.6.20: 8 bytes per minute. The first four match the older
/// layout `kind, intensity, steps, hr` (hr 0xff or 0 means no reading).
/// Bytes 4–7 are still TODO(verify); `android-2026-10-04T12-33-07` is
/// 13728 bytes / 1716 records.
const activityRecordSize = 8;

List<ActivityRecord> parseActivity(Uint8List data, DateTime start) {
  final out = <ActivityRecord>[];
  for (
    var i = 0;
    i + activityRecordSize <= data.length;
    i += activityRecordSize
  ) {
    final hr = data[i + 3];
    out.add(
      ActivityRecord(
        start.add(Duration(minutes: i ~/ activityRecordSize)),
        data[i],
        data[i + 1],
        data[i + 2],
        hr == 0xff || hr == 0 ? null : hr,
      ),
    );
  }
  return out;
}

final class ValueRecord {
  const ValueRecord(this.ts, this.value);
  final DateTime ts;
  final int value;
}

/// Stress: one byte per minute, 0xff/0 = none. TODO(verify)
List<ValueRecord> parseStress(Uint8List data, DateTime start) => [
  for (var i = 0; i < data.length; i++)
    if (data[i] != 0xff && data[i] != 0)
      ValueRecord(start.add(Duration(minutes: i)), data[i]),
];

/// SpO2: records of `time(7 bytes), value` per measurement. TODO(verify)
List<ValueRecord> parseSpo2(Uint8List data) {
  const size = 8; // TODO(verify)
  final out = <ValueRecord>[];
  for (var i = 0; i + size <= data.length; i += size) {
    final t = decodeBandTime(data, i);
    final v = data[i + 7];
    if (t != null && v > 0 && v <= 100) out.add(ValueRecord(t, v));
  }
  return out;
}

/// Activity-kind codes → sleep stage name. All TODO(verify); unknown codes
/// map to null (treated as awake/unknown by scoring).
const sleepKinds = <int, String>{
  0x70: 'light', // TODO(verify)
  0x7a: 'light', // TODO(verify)
  0x7b: 'deep', // TODO(verify)
  0x79: 'deep', // TODO(verify)
  0x6e: 'rem', // TODO(verify)
  // android-2026-10-04T12-33-07: 0xf0 runs for hours with HR every minute
  // and ~0 steps (night and a nap). 0xf9/0xfa sit inside those runs.
  // Stage split is still TODO(verify); counted as light so the night exists.
  0xf0: 'light',
  0xf9: 'light',
  0xfa: 'light',
};

/// Codes meaning "not worn". TODO(verify)
/// 0xf3 in that capture is 245 minutes with no HR sample at all.
const notWornKinds = {0x73, 0x0f, 0xf3}; // TODO(verify)

/// A workout recorded by the band's own Workout app.
final class BandWorkout {
  const BandWorkout({
    required this.start,
    required this.end,
    required this.kind,
    required this.raw,
  });
  final DateTime start, end;

  /// Band sport code, see [bandSportNames]. TODO(verify)
  final int kind;

  /// The whole summary, kept so later firmware findings can re-read it.
  final Uint8List raw;

  Duration get duration => end.difference(start);
}

/// Summary header: `version u16 LE, kind u16 LE, start u32 LE, end u32 LE`
/// (Unix seconds), then per-version stats that Tempo does not read; HR,
/// steps and strain come from the activity minutes instead. TODO(verify)
/// [announcedStart] is the start the fetch reply gave; the header's times
/// are only trusted when they agree with it (within a day) and end > start.
BandWorkout? parseWorkoutSummary(Uint8List data, DateTime announcedStart) {
  if (data.length < 12) return null;
  int u16(int o) => data[o] | (data[o + 1] << 8);
  int u32(int o) =>
      data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24);
  final kind = u16(2);
  final start = DateTime.fromMillisecondsSinceEpoch(u32(4) * 1000);
  final end = DateTime.fromMillisecondsSinceEpoch(u32(8) * 1000);
  if (start.difference(announcedStart).abs() > const Duration(days: 1)) {
    return null;
  }
  final d = end.difference(start);
  if (d <= Duration.zero || d > const Duration(hours: 24)) return null;
  return BandWorkout(start: start, end: end, kind: kind, raw: data);
}

/// Band sport codes → Tempo sport names (scoring's `Sport`). Every code is
/// TODO(verify) against a workout captured on the real band; unknown codes
/// stay "other" and keep their number in the title.
const bandSportNames = <int, String>{
  0x01: 'running', // outdoor run
  0x06: 'walking', // walking
  0x08: 'running', // treadmill
  0x09: 'cycling', // outdoor cycling
  0x0a: 'cycling', // indoor cycling
  0x10: 'sport', // freestyle
  0x3c: 'yoga',
};

/// Display titles for [bandSportNames] codes. TODO(verify)
const bandSportTitles = <int, String>{
  0x01: 'Outdoor run',
  0x06: 'Walk',
  0x08: 'Treadmill',
  0x09: 'Outdoor ride',
  0x0a: 'Indoor ride',
  0x10: 'Freestyle',
  0x3c: 'Yoga',
};
