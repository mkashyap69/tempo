import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('in range, recheck and ask the doctor from the ranges', () {
    expect(readLab('crp', .6, male: true).bucket, LabBucket.inRange);
    expect(readLab('crp', 2, male: true).bucket, LabBucket.recheck);
    final high = readLab('crp', 4.2, male: true);
    expect(high.bucket, LabBucket.askDoctor);
    expect(high.note, 'above 3 mg/L');
    expect(
      readLab('glucose', 6.1, male: true).note,
      'a little above 5.5 mmol/L',
    );
    expect(readLab('glucose', 7.2, male: true).bucket, LabBucket.askDoctor);
    expect(readLab('albumin', 33, male: true).note, 'a little below 35 g/L');
  });

  test('creatinine depends on sex', () {
    expect(readLab('creatinine', 100, male: true).bucket, LabBucket.inRange);
    expect(readLab('creatinine', 100, male: false).bucket, LabBucket.recheck);
  });

  test('a panel sorts the furthest out first', () {
    const l = Labs(
      albumin: 45,
      creatinine: 80,
      glucose: 5.0,
      crp: 4,
      lymphocytePct: 30,
      mcv: 90,
      rdw: 15,
      alp: 70,
      wbc: 6,
    );
    final r = readLabs(l, male: true);
    expect(r.length, 9);
    expect(r[0].key, 'crp');
    expect(r[0].bucket, LabBucket.askDoctor);
    expect(r[1].key, 'rdw');
    expect(r[1].bucket, LabBucket.recheck);
    expect(r.skip(2).every((x) => x.bucket == LabBucket.inRange), isTrue);
  });
}
