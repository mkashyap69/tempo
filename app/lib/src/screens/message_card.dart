import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as st;

import '../core/profile.dart' show Keys;
import '../design/components.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

/// Ids of Today's message cards put away today (D5).
final dismissedTodayProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(dbTickProvider);
  return loadDismissedToday(ref.watch(dbProvider));
});

Future<Set<String>> loadDismissedToday(st.TempoDb db, {DateTime? now}) async {
  final raw = await db.setting(Keys.dismissedToday);
  if (raw == null || raw.isEmpty) return {};
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['date'] != st.dateKey(now ?? DateTime.now())) return {};
    return {for (final x in (j['ids'] as List)) '$x'};
  } catch (_) {
    return {};
  }
}

Future<void> dismissToday(st.TempoDb db, String id, {DateTime? now}) async {
  final had = await loadDismissedToday(db, now: now);
  await db.putSetting(
    Keys.dismissedToday,
    jsonEncode({
      'date': st.dateKey(now ?? DateTime.now()),
      'ids': [...had, id],
    }),
  );
}

/// A small fact under a message: an arrow or dot in the message's colour
/// and a short value ("▼ 4 bpm resting HR").
typedef Marker = ({String glyph, String text, Color color});

/// Today's coach messages (D5): an icon in the message's colour, a title,
/// a line of why, optional markers, one action, and a way to put it away
/// (the ✕ or a swipe). Put away for today only; insights stay in All
/// insights.
class MessageCard extends ConsumerWidget {
  const MessageCard({
    super.key,
    required this.id,
    required this.icon,
    required this.color,
    required this.overline,
    required this.title,
    this.body,
    this.tag,
    this.markers = const [],
    this.actionLabel,
    this.onAction,
    this.footnote,
  });

  /// Stable for the day, so a dismissal sticks ("insight:load:detraining").
  final String id;
  final String icon;
  final Color color;
  final String overline, title;
  final String? body, tag, actionLabel, footnote;
  final List<Marker> markers;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gone = ref.watch(dismissedTodayProvider).value;
    if (gone == null || gone.contains(id)) return const SizedBox.shrink();
    final c = context.c;
    Future<void> dismiss() async {
      await dismissToday(ref.read(dbProvider), id);
      ref.invalidate(dismissedTodayProvider);
    }

    return Dismissible(
      key: ValueKey('msg-$id'),
      onDismissed: (_) => dismiss(),
      background: const SizedBox.shrink(),
      child: TempoCard(
        label: '$overline: $title',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: TempoIcon(icon, size: 20, color: color, stroke: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Overline(overline, color: color)),
                      if (tag != null) TempoBadge(tag!, color: color),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(title, style: TempoType.titleM.c(c.text1).tnum),
                  if (body != null) ...[
                    const SizedBox(height: 4),
                    Text(body!, style: TempoType.bodyS.c(c.text2).tnum),
                  ],
                  if (markers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final m in markers) _MarkerChip(m)],
                    ),
                  ],
                  if (footnote != null) ...[
                    const SizedBox(height: 8),
                    Text(footnote!, style: TempoType.caption.c(c.text3)),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 6),
                    TempoButton(
                      '$actionLabel ›',
                      small: true,
                      kind: ButtonKind.text,
                      onTap: onAction,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Transform.translate(
              offset: const Offset(8, -8),
              child: TempoIconButton(
                TempoIcons.close,
                label: 'Put away for today',
                onTap: dismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerChip extends StatelessWidget {
  const _MarkerChip(this.m);
  final Marker m;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: m.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(TempoRadii.pill),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${m.glyph} ',
            style: TextStyle(color: m.color),
          ),
          TextSpan(text: m.text),
        ],
      ),
      style: TempoType.caption.c(context.c.text1).tnum,
    ),
  );
}
