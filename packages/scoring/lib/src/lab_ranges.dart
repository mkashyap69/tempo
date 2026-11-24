/// The nine PhenoAge markers sorted by how far each sits from common adult
/// reference ranges (D2): in range, worth a recheck, or worth asking your
/// doctor about. A wellness read, not a diagnosis. Pure Dart.
library;

import 'longevity.dart' show Labs;

enum LabBucket { askDoctor, recheck, inRange }

/// One marker's read.
final class LabRead {
  const LabRead(
    this.key,
    this.name,
    this.value,
    this.unit,
    this.bucket,
    this.note,
  );
  final String key, name, unit;
  final double value;
  final LabBucket bucket;

  /// Why, in a few words ("above 3 mg/L").
  final String note;
}

/// (range lo, range hi, recheck lo, recheck hi): inside the range is in
/// range, inside the wider band is a recheck, outside it asks the doctor. Typical adult ranges; labs differ a
/// little, so the report's own range wins when they disagree.
typedef _Band = (double, double, double, double);

_Band _band(String key, bool male) => switch (key) {
  'albumin' => (35, 50, 30, 55), // g/L
  'creatinine' => male ? (60, 110, 50, 130) : (45, 90, 40, 110), // µmol/L
  'glucose' => (3.9, 5.5, 3.0, 6.9), // mmol/L fasting; ≥ 7.0 diabetic range
  'crp' => (0, 1, 0, 3), // mg/L hs-CRP; AHA: < 1 low, 1–3 average, > 3 high
  'lymphocytePct' => (20, 40, 15, 50), // %
  'mcv' => (80, 100, 76, 104), // fL
  'rdw' => (11.5, 14.5, 11, 16), // %
  'alp' => (40, 130, 30, 200), // U/L
  'wbc' => (4, 10, 3.5, 12), // 10⁹/L
  _ => (
    double.negativeInfinity,
    double.infinity,
    double.negativeInfinity,
    double.infinity,
  ),
};

const labNames = {
  'albumin': ('Albumin', 'g/L'),
  'creatinine': ('Creatinine', 'µmol/L'),
  'glucose': ('Glucose, fasting', 'mmol/L'),
  'crp': ('hs-CRP', 'mg/L'),
  'lymphocytePct': ('Lymphocytes', '%'),
  'mcv': ('MCV', 'fL'),
  'rdw': ('RDW', '%'),
  'alp': ('ALP', 'U/L'),
  'wbc': ('White cells', '×10⁹/L'),
};

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// Reads one marker.
LabRead readLab(String key, double v, {required bool male}) {
  final (flo, fhi, wlo, whi) = _band(key, male);
  final (name, unit) = labNames[key] ?? (key, '');
  final LabBucket b;
  final String note;
  if (v >= flo && v <= fhi) {
    b = LabBucket.inRange;
    note = 'in the usual range';
  } else if (v >= wlo && v <= whi) {
    b = LabBucket.recheck;
    note = v > fhi
        ? 'a little above ${_n(fhi)} $unit'
        : 'a little below ${_n(flo)} $unit';
  } else {
    b = LabBucket.askDoctor;
    note = v > whi ? 'above ${_n(whi)} $unit' : 'below ${_n(wlo)} $unit';
  }
  return LabRead(key, name, v, unit, b, note);
}

/// All nine markers of [l], the furthest out first.
List<LabRead> readLabs(Labs l, {required bool male}) {
  final v = {
    'albumin': l.albumin,
    'creatinine': l.creatinine,
    'glucose': l.glucose,
    'crp': l.crp,
    'lymphocytePct': l.lymphocytePct,
    'mcv': l.mcv,
    'rdw': l.rdw,
    'alp': l.alp,
    'wbc': l.wbc,
  };
  final out = [for (final e in v.entries) readLab(e.key, e.value, male: male)];
  out.sort((a, b) => a.bucket.index.compareTo(b.bucket.index));
  return out;
}
