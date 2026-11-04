import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/format.dart';
import '../core/week_review.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'coach_parts.dart' show statusColor, statusGlyph;
import 'weekly_report.dart';
import 'weekly_review.dart' show weekReviewProvider;
import '../billing/pro.dart';
import 'paywall.dart';

/// Week in review as four pages you tap through: the sessions, recovery
/// and sleep, the effort, and what's next. The scrolling review stays
/// the full version (and the screen-reader path: every page also has
/// Back and Next buttons).
class WeekStoryScreen extends ConsumerStatefulWidget {
  const WeekStoryScreen({super.key, required this.monday});
  final DateTime monday;

  @override
  ConsumerState<WeekStoryScreen> createState() => _WeekStoryState();
}

class _WeekStoryState extends ConsumerState<WeekStoryScreen> {
  static const pages = 4;
  var _page = 0;

  void _go(int p) {
    if (p < 0) return;
    if (p >= pages) {
      Navigator.pop(context);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _page = p);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(proProvider)) {
      return const ProGate(
        title: 'Week story',
        lockTitle: 'Your week, as a story',
        body: 'Four pages on the week: what you did, how your body answered, what worked and what’s next. The short weekly report stays free.',
        entry: PaywallEntry.weekReview,
        child: SizedBox.shrink(),
      );
    }
    final key = st.dateKey(widget.monday);
    final r = ref.watch(weekReviewProvider(key)).value;
    final report = ref.watch(weekReportProvider(key)).value;
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: r == null || report == null
            ? const SizedBox.shrink()
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        for (var i = 0; i < pages; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: AnimatedContainer(
                              duration: context.reduceMotion
                                  ? Duration.zero
                                  : TempoMotion.base,
                              height: 3,
                              decoration: BoxDecoration(
                                color: i <= _page ? c.text1 : c.surface3,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        TempoIconButton(
                          TempoIcons.close,
                          label: 'Close',
                          onTap: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Left third goes back, the rest forward.
                      onTapUp: (d) {
                        final w = MediaQuery.sizeOf(context).width;
                        _go(d.localPosition.dx < w / 3 ? _page - 1 : _page + 1);
                      },
                      child: AnimatedSwitcher(
                        duration: context.reduceMotion
                            ? Duration.zero
                            : TempoMotion.base,
                        child: Padding(
                          key: ValueKey(_page),
                          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                          child: _pageBody(context, _page, r, report),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        TempoButton(
                          'Back',
                          kind: ButtonKind.ghost,
                          onTap: _page == 0 ? null : () => _go(_page - 1),
                        ),
                        const Spacer(),
                        TempoButton(
                          _page == pages - 1 ? 'Done' : 'Next',
                          onTap: () => _go(_page + 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _pageBody(BuildContext context, int p, WeekReview r, WeekReport w) {
    final c = context.c, s = context.s;
    Widget big(String overline, String title, String sub, List<Widget> more) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(overline),
            const SizedBox(height: 12),
            Text(title, style: TempoType.scoreL.c(c.text1)),
            const SizedBox(height: 12),
            Text(sub, style: TempoType.body.c(c.text2)),
            const SizedBox(height: 28),
            ...more,
          ],
        );
    final week = 'Week of ${dayShort(r.monday)}';
    switch (p) {
      case 0:
        final n = r.planned.length;
        return big(
          week,
          n == 0 ? 'A free week' : '${r.done} of $n',
          n == 0 ? 'Nothing was planned this week.' : r.headline,
          [
            Row(
              children: [
                for (final d in r.days)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          dayShort(d.date).substring(0, 1),
                          style: TempoType.caption.c(c.text3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          statusGlyph(d.status),
                          style: TempoType.titleM.c(
                            d.status == null
                                ? c.text3
                                : statusColor(context, d.status!),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      case 1:
        final rec = w.avg(w.rec), sl = w.avg(w.sleep);
        final best = w.best;
        return big(
          'Recovery and sleep',
          rec == null ? '—' : '${rec.round()}%',
          rec == null
              ? 'Not enough nights this week for an average.'
              : 'Recovery averaged ${rec.round()}%'
                    '${best == null ? '' : ', best on ${_day(best.$1)} at ${best.$2.round()}%'}.',
          [
            if (sl != null)
              _Fact(
                color: s.sleepChannel,
                label: 'Sleep',
                value: '${hmShort(sl)} a night',
              ),
          ],
        );
      case 2:
        final days = w.strain.whereType<double>().length;
        return big(
          'Effort',
          '${r.moderateMinutes} min',
          'Moderate or harder, against the 150 a week the WHO suggests.',
          [
            _Fact(
              color: s.strain[2],
              label: 'Strain in plan',
              value: days == 0 ? '—' : '${w.inPlan} of $days days',
            ),
            const SizedBox(height: 12),
            _Fact(
              color: c.text1,
              label: 'Strength days',
              value: '${r.strengthDays} of 2',
            ),
            const SizedBox(height: 12),
            _Fact(
              color: c.text2,
              label: 'Cardio load',
              value: '${loadGlyph(w.load.status)} ${loadWord(w.load.status)}',
            ),
          ],
        );
      default:
        return big('What’s next', _nextTitle(w.load.status), w.summary(), []);
    }
  }

  static String _nextTitle(sc.LoadStatus l) => switch (l) {
    sc.LoadStatus.overreaching => 'Ease in',
    sc.LoadStatus.building => 'Hold steady',
    sc.LoadStatus.detraining => 'Add one',
    _ => 'Keep going',
  };

  static String _day(int i) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i];
}

class _Fact extends StatelessWidget {
  const _Fact({required this.color, required this.label, required this.value});
  final Color color;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TempoType.label.c(c.text2))),
        Text(value, style: TempoType.label.c(c.text1).tnum),
      ],
    );
  }
}
