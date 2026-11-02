import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

/// V3: today's strain range sized to your own load.
void main() {
  CardioLoad load(double chronic, {LoadStatus s = LoadStatus.maintaining}) =>
      CardioLoad(acute: chronic, chronic: chronic, status: s);

  test('a light normal gets a light range, never above the bands', () {
    // Owner-like: fitness ~12 TRIMP a day, recovery 45 (bands say 8–12).
    final base = strainTarget(recovery: 45);
    final t = personalTarget(base, recovery: 45, load: load(12));
    expect(t.lo, closeTo((strainFromTrimp(12 * .8) * 2).round() / 2, 1e-9));
    expect(t.hi, lessThanOrEqualTo(base.hi));
    expect(t.lo, lessThan(base.lo));
    expect(t.hi, closeTo((strainFromTrimp(12 * 1.1) * 2).round() / 2, 1e-9));
    expect(t.hi - t.lo, greaterThanOrEqualTo(1));
  });

  test('higher recovery asks for more of your own load', () {
    final lo = personalTarget(
      strainTarget(recovery: 45),
      recovery: 45,
      load: load(12),
    );
    final hi = personalTarget(
      strainTarget(recovery: 85),
      recovery: 85,
      load: load(12),
    );
    expect(hi.lo, greaterThan(lo.lo));
    expect(hi.hi, greaterThan(lo.hi));
  });

  test('a big normal is held to the bands', () {
    final base = strainTarget(recovery: 70);
    expect(personalTarget(base, recovery: 70, load: load(400)).hi, base.hi);
  });

  test('rest caps, general days and learning load pass through', () {
    final rest = strainTarget(recovery: 20);
    expect(personalTarget(rest, recovery: 20, load: load(12)), same(rest));
    final general = strainTarget();
    expect(personalTarget(general, load: load(12)), same(general));
    final base = strainTarget(recovery: 60);
    expect(
      personalTarget(
        base,
        recovery: 60,
        load: load(12, s: LoadStatus.learning),
      ),
      same(base),
    );
  });
}
