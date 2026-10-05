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
    '6aa50002-0000-1000-8000-00805f9b34fb': null,
  };

  @override
  Future<FetchStartReply?> probeFetch(int code, DateTime since) async {
    probed.add(code);
    return switch (code) {
      0x01 => FetchStartReply(true, 1716, DateTime(2026, 10, 3, 13, 27)),
      0x07 => FetchStartReply(true, 12, DateTime(2026, 10, 4)),
      0x14 => const FetchStartReply(true, 0, null),
      _ => null,
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

void main() {
  test('surveys characteristics, history types and live HR (no RR)', () async {
    final band = _FakeBand();
    final r = await BandExplorer(
      codes: [0x01, 0x05, 0x07, 0x14],
      hrFor: Duration.zero,
    ).run(band);
    expect(band.probed, [0x01, 0x05, 0x07, 0x14]);
    expect(r.probes.map((p) => p.code), [0x01, 0x07, 0x14]);
    expect(r.silent, [0x05]);
    expect(r.newWithData.single.code, 0x07);
    expect(r.probes.first.known, 'activity');
    expect(band.stopped, isTrue);
    expect(r.hasRr, isFalse);
    final j = r.toJson();
    expect((j['characteristics'] as Map).length, 3);
    expect((j['history'] as List).first, containsPair('code', '0x01'));
    expect(j['silentCodes'], ['0x5']);
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
