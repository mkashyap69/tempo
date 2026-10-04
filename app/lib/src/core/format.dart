import 'package:intl/intl.dart';
import 'package:scoring/scoring.dart' as sc;

/// "7h 12m"
String hmShort(double hours) {
  final m = (hours * 60).round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// "1 h 10 m" style used in sentences.
String hmSpaced(double hours) {
  final m = (hours * 60).round();
  if (m < 60) return '$m m';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} m';
}

/// "10:40 pm"
String clock12(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60) % 24, m = minuteOfDay % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

String clockOf(DateTime t) => clock12(t.hour * 60 + t.minute);

/// "7:30" without am/pm.
String clockShort(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h12:${t.minute.toString().padLeft(2, '0')}';
}

String ampm(DateTime t) => t.hour < 12 ? 'am' : 'pm';

/// "Sunday · 4 Oct"
String dayLong(DateTime d) =>
    '${DateFormat('EEEE').format(d)} · ${d.day} ${DateFormat('MMM').format(d)}';

/// "Sun 4 Oct"
String dayShort(DateTime d) => DateFormat('EEE d MMM').format(d);

/// "4 Oct"
String dm(DateTime d) => '${d.day} ${DateFormat('MMM').format(d)}';

/// "Sat night · 3–4 Oct"
String nightLabel(DateTime morning) {
  final eve = morning.subtract(const Duration(days: 1));
  final same = eve.month == morning.month;
  return '${DateFormat('EEE').format(eve)} night · ${eve.day}${same ? '' : ' ${DateFormat('MMM').format(eve)}'}–${morning.day} ${DateFormat('MMM').format(morning)}';
}

String recoveryGlyph(double r) => r >= 67
    ? '▲'
    : r >= 34
    ? '■'
    : '▼';
String recoveryWord(double r) => r >= 67
    ? 'Primed'
    : r >= 34
    ? 'Steady'
    : 'Low';

String loadGlyph(sc.LoadStatus s) => switch (s) {
  sc.LoadStatus.learning => '…',
  sc.LoadStatus.detraining => '↘',
  sc.LoadStatus.maintaining => '●',
  sc.LoadStatus.building => '↗',
  sc.LoadStatus.overreaching => '⚠',
};

String loadWord(sc.LoadStatus s) => switch (s) {
  sc.LoadStatus.learning => 'Learning',
  sc.LoadStatus.detraining => 'Detraining',
  sc.LoadStatus.maintaining => 'Maintaining',
  sc.LoadStatus.building => 'Building',
  sc.LoadStatus.overreaching => 'Overreaching',
};

/// "+5 to +7" from a session's strain range minus [now].
String strainRange(double lo, double hi) => '${lo.round()}–${hi.round()}';

String n1(double v) => v.toStringAsFixed(1);

/// Thousands separators: 17,204.
String grouped(num v) => NumberFormat('#,##0').format(v);

/// "6 min ago", "14 h ago", "just now"
String ago(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

String mmss(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}
