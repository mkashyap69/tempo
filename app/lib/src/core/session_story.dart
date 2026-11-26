import 'package:scoring/scoring.dart' as sc;

/// v3 after-session: one line that says how it went, before the numbers.
/// [landed] is whether a guided session's work blocks landed in their zone
/// (null when there were no work blocks to judge); [dayStrain] is the day's
/// strain after the session, [target] today's range.
String sessionHeadline({
  required bool guided,
  bool? landed,
  required double dayStrain,
  sc.StrainTarget? target,
}) {
  final t = target;
  if (t != null && t.cap && dayStrain > t.hi) {
    return 'Done. That took today past its cap.';
  }
  if (guided && landed == false) return 'Done, a little short of the plan.';
  if (t == null || t.cap) {
    return guided && landed == true ? 'Nailed it.' : 'Done.';
  }
  if (dayStrain > t.hi + .5) return 'Done, and past today’s range.';
  if (dayStrain < t.lo) {
    return guided && landed == true
        ? 'Nailed it, with room left today.'
        : 'Done, with room left today.';
  }
  return guided && landed == true
      ? 'Nailed it.'
      : 'Done, right in today’s range.';
}

/// What the rest of today should look like after [headline]'s session.
String sessionNext({required double dayStrain, sc.StrainTarget? target}) {
  final t = target;
  if (t == null) return 'Keep the rest of the day easy and sleep on time.';
  if (dayStrain >= t.lo || t.cap) {
    return 'That’s today’s work done. Keep the rest of the day easy.';
  }
  return 'A walk later would take today into its range.';
}
