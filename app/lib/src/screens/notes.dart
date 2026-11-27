import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:url_launcher/url_launcher.dart';

import '../core/limit.dart' show setLimit;
import '../core/notes.dart';
import '../core/skip_reasons.dart' show easeRestOfWeek;
import '../core/today.dart' show appNow;
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';
import 'week_template.dart' show pickLimit;
import '../billing/pro.dart';

/// One note (D3): routine, exercise or session.
final noteProvider = FutureProvider.family<String?, (NoteScope, String)>((
  ref,
  k,
) {
  ref.watch(dbTickProvider);
  return loadNote(ref.watch(dbProvider), k.$1, k.$2);
});

String _scopeHint(NoteScope s) => switch (s) {
  NoteScope.routine => 'Shows every time you start this routine',
  NoteScope.exercise => 'Pinned to this exercise, in every routine',
  NoteScope.session => 'For today’s session only',
};

String _scopeTitle(NoteScope s) => switch (s) {
  NoteScope.routine => 'Routine note',
  NoteScope.exercise => 'Exercise note',
  NoteScope.session => 'Session note',
};

/// A note line: the note, or "Add a … note"; tap to write or change it.
class NoteLine extends ConsumerWidget {
  const NoteLine(this.scope, this.noteRef, {super.key, this.compact = false});
  final NoteScope scope;
  final String noteRef;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final note = ref.watch(noteProvider((scope, noteRef))).value;
    return Pressable(
      label: note ?? 'Add a ${_scopeTitle(scope).toLowerCase()}',
      onTap: () => editNote(context, ref, scope, noteRef, note),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: TempoIcon(
                note == null ? TempoIcons.plus : TempoIcons.edit,
                size: 15,
                color: c.text3,
                stroke: 2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note ?? 'Add a ${_scopeTitle(scope).toLowerCase()}',
                style: (note == null ? TempoType.caption : TempoType.bodyS).c(
                  note == null ? c.text3 : c.text1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> editNote(
  BuildContext context,
  WidgetRef ref,
  NoteScope scope,
  String noteRef,
  String? note,
) async {
  final ctl = TextEditingController(text: note ?? '');
  final out = await showTempoSheet<String>(
    context,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_scopeTitle(scope), style: TempoType.titleM.c(ctx.c.text1)),
        const SizedBox(height: 4),
        Text(_scopeHint(scope), style: TempoType.bodyS.c(ctx.c.text2)),
        const SizedBox(height: 12),
        TempoField(controller: ctl, autofocus: true, maxLines: 4),
        const SizedBox(height: 16),
        TempoButton(
          'Save',
          expand: true,
          onTap: () => Navigator.pop(ctx, ctl.text),
        ),
        if (note != null)
          TempoButton(
            'Delete note',
            kind: ButtonKind.text,
            expand: true,
            onTap: () => Navigator.pop(ctx, ''),
          ),
      ],
    ),
  );
  ctl.dispose();
  if (out == null) return;
  await saveNote(ref.read(dbProvider), scope, noteRef, out);
  ref.invalidate(noteProvider((scope, noteRef)));
}

final reflectionProvider = FutureProvider.family<sc.Reflection?, DateTime>((
  ref,
  start,
) {
  ref.watch(dbTickProvider);
  return loadReflection(ref.watch(dbProvider), start);
});

/// After any workout: how it went in a tap or two, and your own words.
/// Sore and pain are what the coach acts on (Today offers to ease the week,
/// or to train around it).
class ReflectionCard extends ConsumerWidget {
  const ReflectionCard({super.key, required this.start, required this.title});
  final DateTime start;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final r = ref.watch(reflectionProvider(start)).value;
    final tags = r?.tags ?? const <sc.ReflectTag>{};
    final db = ref.read(dbProvider);
    Future<void> save({Set<sc.ReflectTag>? t, String? text}) async {
      await saveReflection(
        db,
        sc.Reflection(
          at: start,
          title: title,
          tags: t ?? tags,
          text: text ?? r?.text ?? '',
        ),
      );
      ref.invalidate(reflectionProvider(start));
    }

    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Overline('How did it go?'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in sc.ReflectTag.values)
                TempoChip(
                  sc.reflectTagName(t),
                  selected: tags.contains(t),
                  onTap: () => save(
                    t: tags.contains(t) ? ({...tags}..remove(t)) : {...tags, t},
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Pressable(
            label: 'Write a reflection',
            onTap: () async {
              final ctl = TextEditingController(text: r?.text ?? '');
              final out = await showTempoSheet<String>(
                context,
                builder: (ctx) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Reflection', style: TempoType.titleM.c(ctx.c.text1)),
                    const SizedBox(height: 4),
                    Text(
                      'For you to look back on. The tags above are what the coach acts on.',
                      style: TempoType.bodyS.c(ctx.c.text2),
                    ),
                    const SizedBox(height: 12),
                    TempoField(controller: ctl, autofocus: true, maxLines: 5),
                    const SizedBox(height: 16),
                    TempoButton(
                      'Save',
                      expand: true,
                      onTap: () => Navigator.pop(ctx, ctl.text),
                    ),
                  ],
                ),
              );
              ctl.dispose();
              if (out != null) await save(text: out);
            },
            child: Text(
              (r?.text ?? '').isEmpty ? 'Add a few words ›' : r!.text,
              style: TempoType.bodyS.c(
                (r?.text ?? '').isEmpty ? c.text2 : c.text1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final reflectCallProvider = FutureProvider<sc.ReflectCall?>((ref) {
  ref.watch(dbTickProvider);
  return loadReflectCall(ref.watch(dbProvider), now: appNow());
});

/// Today, after a workout you marked sore or painful: offer what the plan
/// can do about it. Once answered or put away it doesn't come back.
class ReflectFollowUpCard extends ConsumerWidget {
  const ReflectFollowUpCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Coach behaviour is Tempo Pro (launch plan §3).
    if (!ref.watch(proProvider)) return const SizedBox.shrink();
    final call = ref.watch(reflectCallProvider).value;
    if (call == null) return const SizedBox.shrink();
    final c = context.c;
    final db = ref.read(dbProvider);
    final pain = call.action == sc.ReflectAction.injury;
    final what = call.from.title.isEmpty ? 'your workout' : call.from.title;
    Future<void> done() async {
      await markHandled(db, call.from.at);
      ref.invalidate(reflectCallProvider);
    }

    return TempoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline(pain ? 'You noted pain' : 'You noted soreness'),
          const SizedBox(height: 8),
          Text(
            pain
                ? 'After $what. Train around it for now?'
                : 'After $what. Ease the rest of this week?',
            style: TempoType.titleM.c(c.text1),
          ),
          const SizedBox(height: 4),
          Text(
            pain
                ? 'Injury mode swaps out what loads it. If pain lasts more than a few days, see a doctor or physio.'
                : 'Hard sessions get their easier version and long ones lose a quarter. Easy days stay as they are.',
            style: TempoType.bodyS.c(c.text2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TempoButton(
                  pain ? 'Choose what to avoid' : 'Ease the week',
                  small: true,
                  expand: true,
                  onTap: () async {
                    if (pain) {
                      final l = await pickLimit(context, sc.TrainingLimit.none);
                      if (l == null) return;
                      await setLimit(db, l);
                    } else {
                      final days = await easeRestOfWeek(db, call.from.at);
                      if (context.mounted) {
                        showTempoToast(
                          context,
                          days.isEmpty
                              ? 'Nothing hard left this week'
                              : 'Eased ${days.length} ${days.length == 1 ? 'day' : 'days'}',
                        );
                      }
                    }
                    await done();
                    ref.invalidate(todayProvider);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TempoButton(
                  'Not needed',
                  small: true,
                  kind: ButtonKind.ghost,
                  expand: true,
                  onTap: done,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens a web search for form videos of [exercise] in the browser. Tempo
/// sends nothing: it hands the browser a search link (decisions.md
/// 2026-11-24).
Future<void> openFormVideos(BuildContext context, String exercise) async {
  final uri = Uri.https('www.youtube.com', '/results', {
    'search_query': '$exercise proper form',
  });
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showTempoToast(context, 'Couldn’t open a browser');
  }
}
