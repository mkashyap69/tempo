/// Reflections after a workout (D3): how it went in a few taps, plus your
/// own words. Tempo's coach is rule-based and doesn't read the words; the
/// tags are what it acts on. Pure Dart.
library;

/// How a workout went. [sore] and [pain] are what the coach acts on.
enum ReflectTag { strong, easy, hard, tired, sore, pain }

String reflectTagName(ReflectTag t) => switch (t) {
  ReflectTag.strong => 'Felt strong',
  ReflectTag.easy => 'Easier than planned',
  ReflectTag.hard => 'Harder than planned',
  ReflectTag.tired => 'Tired',
  ReflectTag.sore => 'Sore',
  ReflectTag.pain => 'Pain',
};

final class Reflection {
  const Reflection({
    required this.at,
    required this.title,
    this.tags = const {},
    this.text = '',
  });

  /// When the workout started.
  final DateTime at;
  final String title;
  final Set<ReflectTag> tags;
  final String text;

  bool get isEmpty => tags.isEmpty && text.trim().isEmpty;
}

/// What the coach offers after a reflection.
enum ReflectAction {
  /// Sore: ease the rest of the week (hard sessions get their easier
  /// version, long ones lose a quarter).
  easeWeek,

  /// Pain: train around it (You → Injury) and see someone if it lasts.
  injury,
}

typedef ReflectCall = ({Reflection from, ReflectAction action});

/// How long a sore or pain reflection stays worth acting on.
const reflectWindow = Duration(hours: 36);

/// The newest reflection in the last [reflectWindow] tagged sore or pain,
/// and what to offer; pain wins over sore. Null when none, or when that
/// reflection was already answered ([handled] holds workout start times
/// already acted on or dismissed).
ReflectCall? reflectCall(
  List<Reflection> all,
  DateTime now, {
  Set<DateTime> handled = const {},
}) {
  final recent = [
    for (final r in all)
      if (!r.at.isAfter(now) &&
          now.difference(r.at) <= reflectWindow &&
          !handled.contains(r.at) &&
          (r.tags.contains(ReflectTag.sore) ||
              r.tags.contains(ReflectTag.pain)))
        r,
  ]..sort((a, b) => b.at.compareTo(a.at));
  if (recent.isEmpty) return null;
  final r = recent.first;
  return (
    from: r,
    action: r.tags.contains(ReflectTag.pain)
        ? ReflectAction.injury
        : ReflectAction.easeWeek,
  );
}
