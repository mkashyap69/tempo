import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart';
import '../core/profile.dart';
import '../core/week_override.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'coach_replies.dart' show CoachLabel;

const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime nextMonday([DateTime? now]) =>
    mondayOf(dayOf(now ?? DateTime.now())).add(const Duration(days: 7));

final _nextOverrideProvider = FutureProvider.autoDispose<WeekOverride?>((ref) {
  ref.watch(dbTickProvider);
  return loadWeekOverride(ref.watch(dbProvider), nextMonday());
});

/// v3 interactive coach 4 (0.11.0): the entry, from Friday to Sunday.
class PlanNextWeekCard extends ConsumerWidget {
  const PlanNextWeekCard({super.key, this.from = DateTime.friday});

  /// The first weekday it shows (Train from Friday, Today on Sunday).
  final int from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DateTime.now().weekday < from) return const SizedBox.shrink();
    final c = context.c;
    final done = ref.watch(_nextOverrideProvider).value != null;
    return TempoCard(
      key: const ValueKey('plan-next-week'),
      label: 'Plan next week with me',
      onTap: () => showPlanWeekSheet(context, ref),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CoachLabel('Coach'),
                const SizedBox(height: 6),
                Text(
                  done ? 'Next week is planned' : 'Plan next week with me',
                  style: TempoType.titleM.c(c.text1),
                ),
                const SizedBox(height: 2),
                Text(
                  done
                      ? 'Tap to change your busy days or long day.'
                      : 'Your busy days and your long day, in a few taps.',
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          Text('›', style: TempoType.titleM.c(c.text3)),
        ],
      ),
    );
  }
}

/// The sheet: tap a day once for busy, twice for the long day; the week
/// below is what the coach would build. Looks good saves it for next week
/// only and rebuilds that week.
Future<void> showPlanWeekSheet(BuildContext context, WidgetRef ref) async {
  final db = ref.read(dbProvider);
  final profile = await loadAppProfile(db) ?? const Profile();
  final mon = nextMonday();
  final saved = await loadWeekOverride(db, mon);
  if (!context.mounted) return;
  var busy = {...?saved?.busy};
  int? long = saved?.longDay ?? profile.longDay;
  final service = CoachService(db);
  return showTempoSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.c, s = ctx.s;
        final o = WeekOverride(busy: busy, longDay: long);
        void tap(int d) => setState(() {
          if (long == d) {
            long = null;
          } else if (busy.contains(d)) {
            busy = {...busy}..remove(d);
            long = d;
          } else {
            busy = {...busy, d};
          }
        });
        Widget chip(int d) {
          final off = !profile.days.contains(d);
          final isBusy = busy.contains(d), isLong = long == d && !off;
          final (bg, border, fg, tag) = off
              ? (c.surface2, c.line, c.text3, 'OFF')
              : isLong
              ? (
                  s.loadBuilding.withValues(alpha: .16),
                  s.loadBuilding.withValues(alpha: .55),
                  s.loadBuilding,
                  'LONG',
                )
              : isBusy
              ? (
                  s.recLow.withValues(alpha: .14),
                  s.recLow.withValues(alpha: .45),
                  s.recLow,
                  'BUSY',
                )
              : (c.surface2, c.line, c.text1, '');
          return Expanded(
            child: Pressable(
              key: ValueKey('week-day-$d'),
              label:
                  '${_names[d - 1]}: ${tag.isEmpty ? 'free' : tag.toLowerCase()}',
              onTap: off ? null : () => tap(d),
              child: Container(
                height: 54,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(TempoRadii.md),
                  border: Border.all(color: border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_names[d - 1], style: TempoType.label.c(fg)),
                    if (tag.isNotEmpty)
                      Text(
                        tag,
                        style: TempoType.caption.copyWith(
                          fontSize: 9,
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoachLabel('Coach · next week'),
            const SizedBox(height: 8),
            Text('Plan next week with me', style: TempoType.titleL.c(c.text1)),
            const SizedBox(height: 4),
            Text(
              'Tap a day once if it’s busy, twice for your long day. Only next week changes.',
              style: TempoType.bodyS.c(c.text2),
            ),
            const SizedBox(height: 14),
            Row(children: [for (var d = 1; d <= 7; d++) chip(d)]),
            const SizedBox(height: 14),
            FutureBuilder<(List<sc.Session>, bool, sc.BlockWeek?)>(
              key: ValueKey(o.toJson()),
              future: service.buildWeek(mon, override: o),
              builder: (ctx, snap) {
                final week = snap.data?.$1;
                return Container(
                  key: const ValueKey('week-preview'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(TempoRadii.md),
                  ),
                  child: week == null
                      ? const SizedBox(height: 7 * 30)
                      : Column(
                          children: [
                            for (var i = 0; i < 7; i++)
                              SizedBox(
                                height: 30,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        _names[i],
                                        style: TempoType.caption.c(c.text2),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        week[i].isRest
                                            ? 'Rest'
                                            : '${week[i].title} · ${week[i].minutes} min',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TempoType.bodyS.c(
                                          week[i].isRest
                                              ? c.text3
                                              : week[i].isHard
                                              ? s.strain[2]
                                              : c.text1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                );
              },
            ),
            const SizedBox(height: 14),
            TempoButton(
              'Looks good',
              expand: true,
              onTap: () async {
                await db.putSetting(weekOverrideKey(mon), o.toJson());
                await service.ensureWeek(mon, rebuild: true);
                if (ctx.mounted) {
                  showTempoToast(ctx, 'Next week is planned');
                  Navigator.pop(ctx);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    ),
  );
}
