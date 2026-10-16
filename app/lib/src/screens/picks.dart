import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/coach_service.dart';
import '../core/picks_service.dart';
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'strength_log.dart';
import 'nav.dart';

/// Today's three picks: a run, a strength session and a game or other
/// sport, each with exactly what to do. One is Tempo's pick.
final picksProvider = FutureProvider<List<sc.Pick>>((ref) async {
  ref.watch(dbTickProvider);
  final t = await ref.watch(todayProvider.future);
  return loadPicks(ref.watch(dbProvider), t);
});

String pickIcon(sc.Pick p) => switch (p.kind) {
  sc.PickKind.run => TempoIcons.run,
  sc.PickKind.strength => TempoIcons.strength,
  sc.PickKind.play => switch (p.session.sport) {
    sc.Sport.cycling => TempoIcons.ride,
    sc.Sport.walking => TempoIcons.walk,
    sc.Sport.yoga => TempoIcons.yoga,
    sc.Sport.hiit => TempoIcons.hiit,
    _ => TempoIcons.sport,
  },
};

String pickKindLabel(sc.Pick p) => switch (p.kind) {
  sc.PickKind.run => 'RUN',
  sc.PickKind.strength => 'STRENGTH',
  sc.PickKind.play =>
    p.detail is sc.PlayDetail && (p.detail as sc.PlayDetail).game != null
        ? 'PLAY'
        : 'SOMETHING ELSE',
};

/// "Threshold intervals · 45′ · Z2–Z4"
String pickSubtitle(sc.Pick p) {
  final d = p.detail;
  final what = switch (d) {
    sc.RunDetail(:final type) => sc.runTypeName(type),
    sc.StrengthDetail(:final exercises) => '${exercises.length} exercises',
    sc.PlayDetail(:final format) => format,
  };
  return '$what · ${p.session.minutes}′';
}

/// Coach → Today (and Today's "choose a workout"): the three picks.
class TodayPicks extends ConsumerWidget {
  const TodayPicks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(picksProvider).value;
    if (picks == null || picks.isEmpty) return const SizedBox.shrink();
    return Section(
      title: 'Choose today’s workout',
      child: Column(
        children: [
          for (final p in picks) ...[
            PickCard(pick: p),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class PickCard extends StatelessWidget {
  const PickCard({super.key, required this.pick});
  final sc.Pick pick;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = pick;
    return TempoCard(
      label: '${p.session.title}${p.recommended ? ', Tempo’s pick' : ''}',
      onTap: () => showPick(context, p),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: TempoIcon(pickIcon(p), size: 20, color: c.text1),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Overline(pickKindLabel(p)),
                    if (p.recommended) ...[
                      const SizedBox(width: 8),
                      const TempoBadge('Tempo’s pick', small: true),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(p.session.title, style: TempoType.label.c(c.text1)),
                const SizedBox(height: 2),
                Text(
                  pickSubtitle(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TempoType.bodyS.c(c.text2).tnum,
                ),
                const SizedBox(height: 6),
                Text(p.why, style: TempoType.caption.c(c.text3)),
              ],
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3),
        ],
      ),
    );
  }
}

/// The full pick: how it should feel, what it's for and what to do, with
/// "Make it today's plan" and "Start now".
Future<void> showPick(BuildContext context, sc.Pick p) => showTempoSheet<void>(
  context,
  builder: (ctx) => Consumer(
    builder: (ctx, ref, _) => _PickSheet(pick: p, ref: ref),
  ),
);

class _PickSheet extends StatelessWidget {
  const _PickSheet({required this.pick, required this.ref});
  final sc.Pick pick;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = pick;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * .85,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Overline(pickKindLabel(p)),
                if (p.recommended) ...[
                  const SizedBox(width: 8),
                  const TempoBadge('Tempo’s pick', small: true),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(p.session.title, style: TempoType.titleL.c(c.text1)),
            const SizedBox(height: 4),
            Text(pickSubtitle(p), style: TempoType.bodyS.c(c.text2).tnum),
            const SizedBox(height: 12),
            Text(p.why, style: TempoType.body.c(c.text1)),
            const SizedBox(height: 16),
            PickDetailView(session: p.session),
            const SizedBox(height: 20),
            TempoButton(
              'Make it today’s plan',
              expand: true,
              onTap: () async {
                await CoachService(ref.read(dbProvider))
                    .swapToday(p.session, 'you picked ${p.session.title}');
                if (context.mounted) {
                  Navigator.pop(context);
                  showTempoToast(context, '${p.session.title} is today’s plan');
                }
              },
            ),
            const SizedBox(height: 8),
            TempoButton(
              'Start now',
              kind: ButtonKind.secondary,
              expand: true,
              onTap: () async {
                await CoachService(ref.read(dbProvider))
                    .swapToday(p.session, 'you picked ${p.session.title}');
                if (!context.mounted) return;
                Navigator.pop(context);
                await openLive(context, ref, plan: p.session);
              },
            ),
            if (p.kind == sc.PickKind.strength) ...[
              const SizedBox(height: 8),
              TempoButton(
                'Log sets',
                kind: ButtonKind.text,
                expand: true,
                onTap: () async {
                  await CoachService(ref.read(dbProvider))
                      .swapToday(p.session, 'you picked ${p.session.title}');
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await push(context, StrengthLogScreen(plan: p.session));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What to do in a session that came from today's picks. Nothing for
/// sessions without a detail.
class PickDetailView extends StatelessWidget {
  const PickDetailView({super.key, required this.session});
  final sc.Session session;

  @override
  Widget build(BuildContext context) {
    final d = session.detail;
    if (d == null) return const SizedBox.shrink();
    final c = context.c;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Overline(t),
    );
    Widget para(String t) => Text(t, style: TempoType.bodyS.c(c.text2));
    Widget bullet(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('·  ', style: TempoType.bodyS.c(c.text3)),
          Expanded(child: para(t)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label('How it should feel'),
        para(d.effort),
        label('Why'),
        para(d.purpose),
        ...switch (d) {
          sc.RunDetail(:final cues) => [
            label('The session'),
            para(session.structure),
            if (cues.isNotEmpty) ...[
              label('Tips'),
              for (final x in cues) bullet(x),
            ],
          ],
          sc.StrengthDetail(:final exercises, :final circuit, :final warmup) => [
            if (warmup.isNotEmpty) ...[label('Warm-up'), para(warmup)],
            label(circuit ? 'Circuit · 3 rounds' : 'Exercises'),
            for (final e in exercises)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.name, style: TempoType.body.c(c.text1)),
                        ),
                        Text(
                          circuit
                              ? e.reps
                              : '${e.sets} × ${e.reps}${e.restSeconds > 0 ? ' · ${e.restSeconds} s rest' : ''}',
                          style: TempoType.bodyS.c(c.text2).tnum,
                        ),
                      ],
                    ),
                    if (e.kg != null)
                      Text(
                        '${e.kg! == e.kg!.roundToDouble() ? e.kg!.round() : e.kg} kg × ${e.reps} · ${e.target ?? ''}',
                        style: TempoType.caption.c(context.s.recHigh),
                      ),
                    if (e.home != null && e.home != e.name)
                      Text(
                        'At home: ${e.home}',
                        style: TempoType.caption.c(c.text3),
                      ),
                    if (e.cue.isNotEmpty)
                      Text(e.cue, style: TempoType.caption.c(c.text3)),
                  ],
                ),
              ),
          ],
          sc.PlayDetail(:final format, :final cues) => [
            label('Format'),
            para(format),
            if (cues.isNotEmpty) ...[
              label('Tips'),
              for (final x in cues) bullet(x),
            ],
          ],
        },
      ],
    );
  }
}

/// Today: one quiet row that opens Coach on its picks.
class PicksEntry extends ConsumerWidget {
  const PicksEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(picksProvider).value;
    if (picks == null || picks.isEmpty) return const SizedBox.shrink();
    final c = context.c;
    return TempoCard(
      label: 'Choose a workout',
      onTap: () => showTempoSheet<void>(
        context,
        builder: (ctx) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose today’s workout',
                style: TempoType.titleL.c(ctx.c.text1),
              ),
              const SizedBox(height: 14),
              for (final p in picks) ...[
                PickCard(pick: p),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose a workout', style: TempoType.label.c(c.text1)),
                const SizedBox(height: 2),
                Text(
                  picks.map((p) => p.session.title).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TempoType.bodyS.c(c.text2),
                ),
              ],
            ),
          ),
          TempoIcon(TempoIcons.chevron, size: 16, color: c.text3),
        ],
      ),
    );
  }
}
