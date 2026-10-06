import 'dart:async';
import 'dart:convert';

import 'package:band_ble/band_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/core/band_explorer.dart';

class _FakeBand implements ExplorerBand {
  _FakeBand({this.rr = false});
  final bool rr;
  final probed = <int>[];
  bool stopped = false;

  @override
  Future<Map<String, List<int>?>> readAllReadable() async => {
    '00002a28-0000-1000-8000-00805f9b34fb': utf8.encode('V1.0.6.20'),
    '6aa50001-0000-1000-8000-00805f9b34fb': [1, 2, 3],
    '00000006-0000-3512-2118-0009af100700': [
      0x0f, 46, 0, 0xb2, 7, 1, 1, 0, 0, 0, 0, //
      0xea, 7, 10, 4, 23, 6, 51, 0x16, 98,
    ],
    '00000007-0000-3512-2118-0009af100700': [
      0x0c,
      81,
      0,
      0,
      0,
      51,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
    ],
    '6aa50002-0000-1000-8000-00805f9b34fb': null,
  };

  @override
  Future<ProbeOutcome> probeFetch(int code, DateTime since) async {
    probed.add(code);
    return switch (code) {
      0x01 => ProbeOutcome(
        FetchStartReply(true, 1716, DateTime(2026, 10, 3, 13, 27)),
        const [0x10, 0x01, 0x01],
        List.filled(1716 * 8, 0),
      ),
      0x07 => ProbeOutcome(
        FetchStartReply(true, 12, DateTime(2026, 10, 4)),
        const [0x10, 0x01, 0x01],
        List.filled(48, 7),
      ),
      0x14 => const ProbeOutcome(FetchStartReply(true, 0, null), [
        0x10,
        0x01,
        0x01,
      ], []),
      _ => const ProbeOutcome(null, null, []),
    };
  }

  @override
  Future<Stream<List<int>>> startLiveHrRaw() async => Stream.fromIterable([
    for (var i = 0; i < 40; i++)
      rr
          // 60 bpm with one RR of 1000 or 1040 ms (1024 / 1065 in 1/1024 s)
          ? [
              0x10,
              60,
              ...(i.isEven ? [0x00, 0x04] : [0x29, 0x04]),
            ]
          : [0x00, 60],
  ]);

  @override
  Future<void> stopLiveHr() async => stopped = true;
}

/// Answers like V1.0.6.20 on 6 Oct: from long ago, only the first block.
class _BlockBand extends _FakeBand {
  final since = <DateTime>[];
  @override
  Future<ProbeOutcome> probeFetch(int code, DateTime since) async {
    probed.add(code);
    this.since.add(since);
    const ok = [0x10, 0x01, 0x01];
    final old = since.isBefore(DateTime(2026, 10, 5, 17, 49));
    return switch (code) {
      0x01 when old => ProbeOutcome(
        FetchStartReply(true, 1368, DateTime(2026, 10, 5, 17, 58)),
        ok,
        List.filled(1368 * 8, 1),
      ),
      0x01 when since == DateTime(2026, 10, 6, 16, 46) => ProbeOutcome(
        FetchStartReply(true, 175, DateTime(2026, 10, 6, 16, 46)),
        ok,
        List.filled(175 * 8, 2),
      ),
      0x13 when old => ProbeOutcome(
        FetchStartReply(true, 9, DateTime(2026, 10, 5, 17, 49)),
        ok,
        List.filled(9, 0xff),
      ),
      0x13 when since == DateTime(2026, 10, 5, 17, 58) => ProbeOutcome(
        FetchStartReply(true, 1435, DateTime(2026, 10, 5, 17, 58)),
        ok,
        List.filled(1435, 30),
      ),
      _ => const ProbeOutcome(FetchStartReply(true, 0, null), ok, []),
    };
  }
}

void main() {
  test('surveys characteristics, history types and live HR (no RR)', () async {
    final band = _FakeBand();
    final r = await BandExplorer(
      codes: [0x01, 0x05, 0x07, 0x14],
      hrFor: Duration.zero,
    ).run(band);
    // 0x01 is followed once more from its block end; the fake repeats
    // itself, so that stops it.
    expect(band.probed, [0x01, 0x01, 0x05, 0x07, 0x14]);
    expect(r.probes.map((p) => p.code), [0x01, 0x07, 0x14]);
    expect(r.silent, [0x05]);
    expect(r.newWithData.single.code, 0x07);
    expect(r.probes.first.known, 'activity');
    expect(band.stopped, isTrue);
    expect(r.hasRr, isFalse);
    expect(r.battery!.level, 46);
    expect(r.battery!.lastChargeLevel, 98);
    expect(r.today!.steps, 81);
    final j = r.toJson();
    expect((j['characteristics'] as Map).length, 5);
    final hist = (j['history'] as List).cast<Map<String, Object?>>();
    expect(hist[0]['bytesPerRecord'], 8);
    expect(hist[0].containsKey('payload'), isFalse); // activity: known
    expect(hist[1]['payload'], '07' * 48); // 0x07: new, kept
    expect(hist[1]['reply'], '100101');
    expect((j['history'] as List).first, containsPair('code', '0x01'));
    expect(j['silentCodes'], ['0x5']);
  });

  test('follows activity and stress blocks to the present', () async {
    final band = _BlockBand();
    final r = await BandExplorer(
      codes: [0x01, 0x13],
      hrFor: Duration.zero,
      now: () => DateTime(2026, 10, 6, 19, 41),
    ).run(band);
    final act = r.probes.first;
    // 6 Oct: 1368 minutes to 16:46, then 175 more to 19:41.
    expect(act.count, 1368 + 175);
    expect(act.data.length, (1368 + 175) * 8);
    expect(act.blocks.map((b) => b.$2), [1368, 175]);
    expect(band.since[1], DateTime(2026, 10, 6, 16, 46));
    final j = act.toJson();
    expect((j['blocks'] as List).length, 2);
    expect(r.probes.last.blocks.map((b) => b.$2), [9, 1435]);
  });

  test('beat intervals become HRV when the band sends them', () async {
    final band = _FakeBand(rr: true);
    final r = await BandExplorer(
      codes: const [],
      hrFor: const Duration(seconds: 2),
    ).run(band);
    expect(r.hrPackets.length, 40);
    expect(r.packetsWithRr, 40);
    expect(r.rrMs.take(2), [1000, 1040]);
    expect(r.rmssd, closeTo(40, 1));
  });

  test('stops early when cancelled', () async {
    final band = _FakeBand();
    var n = 0;
    final r = await BandExplorer(
      codes: [1, 2, 3, 4],
      hrFor: const Duration(minutes: 5),
    ).run(band, cancelled: () => ++n > 2);
    expect(band.probed.length, lessThan(4));
    expect(r.hrPackets, isEmpty);
  });
}
