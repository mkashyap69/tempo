import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 10, 4, 23);
  // Builds a night from (minutes, hr, motion) blocks, all flagged asleep.
  List<Minute> night(List<(int, int?, int)> blocks) {
    final out = <Minute>[];
    for (final (n, hr, motion) in blocks) {
      for (var i = 0; i < n; i++) {
        out.add(
          Minute(
            t0.add(Duration(minutes: out.length)),
            hr: hr == null ? null : hr + (i % 2),
            stage: Stage.light,
            motion: motion,
          ),
        );
      }
    }
    return out;
  }

  Map<Stage, int> count(StagedSleep s) {
    final c = <Stage, int>{};
    for (final m in s.minutes) {
      c[m.stage] = (c[m.stage] ?? 0) + 1;
    }
    return c;
  }

  test('too little heart rate: left unstaged', () {
    final m = [
      for (var i = 0; i < 300; i++)
        Minute(
          t0.add(Duration(minutes: i)),
          hr: i % 30 == 0 ? 60 : null,
          stage: Stage.light,
        ),
    ];
    final s = stageSleep(m);
    expect(s.staged, isFalse);
    expect(s.minutes.every((x) => x.stage == Stage.light), isTrue);
  });

  test('low steady HR is deep; moving with high HR is wake', () {
    final s = stageSleep(
      night([(40, 62, 2), (60, 52, 0), (60, 62, 2), (5, 85, 60), (60, 62, 2)]),
    );
    expect(s.staged, isTrue);
    final m = s.minutes;
    expect(m[70].stage, Stage.deep);
    expect(m[162].stage, Stage.wake);
    expect(m[20].stage, isNot(Stage.deep));
  });

  test('REM: still, HR above median and variable, after the first hour', () {
    final varied = [for (var i = 0; i < 40; i++) (1, 64 + (i % 4) * 3, 0)];
    final early = stageSleep(night([...varied, (200, 60, 2)]));
    expect(early.minutes.take(40).where((x) => x.stage == Stage.rem), isEmpty);
    final late = stageSleep(night([(90, 60, 2), ...varied, (90, 60, 2)]));
    final rem = late.minutes
        .skip(90)
        .take(40)
        .where((x) => x.stage == Stage.rem)
        .length;
    expect(rem, greaterThan(20));
  });

  test('short runs are smoothed into light', () {
    final s = stageSleep(night([(100, 62, 2), (3, 50, 0), (100, 62, 2)]));
    expect(s.minutes.skip(100).take(3).map((x) => x.stage), [
      Stage.light,
      Stage.light,
      Stage.light,
    ]);
  });

  test('a typical night gets every stage in plausible shares', () {
    final s = stageSleep(
      night([
        (30, 66, 3), // falling asleep
        (50, 54, 0), // deep
        (60, 62, 3),
        (20, 75, 0), // REM-ish
        (40, 56, 0), // deep
        (60, 62, 3),
        (30, 72, 0), // REM-ish
        (3, 88, 50), // wake
        (90, 63, 3),
      ]),
    );
    final c = count(s);
    final total = s.minutes.length;
    expect((c[Stage.deep] ?? 0) / total, inInclusiveRange(.1, .35));
    expect((c[Stage.light] ?? 0) / total, greaterThan(.3));
    expect(c[Stage.wake], greaterThan(0));
  });

  test('deep is found early even when HR drifts down all night', () {
    // HR falls 6 bpm over 6 h; a deep dip of 4 bpm below the drift sits in
    // the first cycle. Without detrending the late, lower HR wins.
    final m = <Minute>[];
    for (var i = 0; i < 360; i++) {
      final drift = 56 - 6 * i / 360;
      final dip = i >= 60 && i < 100 ? 4 : 0;
      m.add(
        Minute(
          t0.add(Duration(minutes: i)),
          hr: (drift - dip + (i % 2)).round(),
          stage: Stage.light,
          motion: i >= 60 && i < 100 ? 0 : 3,
        ),
      );
    }
    final early = (StagedSleep s) =>
        s.minutes.skip(60).take(40).where((x) => x.stage == Stage.deep).length;
    expect(early(stageSleep(m)), greaterThan(20));
    // The drift alone (last 2 h, no dip) isn't read as deep any more.
    final late = (StagedSleep s) =>
        s.minutes.skip(240).where((x) => x.stage == Stage.deep).length;
    expect(
      late(stageSleep(m, const StageParams(detrend: false))),
      greaterThan(late(stageSleep(m))),
    );
  });
}
