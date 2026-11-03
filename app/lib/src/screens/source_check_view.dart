import 'package:flutter/material.dart';

import '../core/source_check.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';

/// The source check as a card: one row per thing Tempo needs, with how much
/// it found and from which app (B1b). Used by onboarding and Data sources.
class SourceCheckView extends StatelessWidget {
  const SourceCheckView({super.key, required this.check});
  final SourceCheck check;

  @override
  Widget build(BuildContext context) {
    final c = context.c, s = context.s;
    Widget mark(CheckState st) {
      final (bg, fg, t) = switch (st) {
        CheckState.good => (s.recHigh.withValues(alpha: .18), s.recHigh, '✓'),
        CheckState.partial => (s.recMid.withValues(alpha: .18), s.recMid, '!'),
        CheckState.missing => (s.recLow.withValues(alpha: .18), s.recLow, '–'),
      };
      return Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          t,
          style: TempoType.caption.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardList(
          children: [
            for (final l in check.lines)
              Semantics(
                container: true,
                label: '${l.title}: ${l.amount}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      mark(l.state),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.title, style: TempoType.body.c(c.text1)),
                            if (l.apps.isNotEmpty)
                              Text(
                                l.apps.take(3).join(', '),
                                style: TempoType.caption.c(c.text3),
                              ),
                            if (l.hint != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  l.hint!,
                                  style: TempoType.caption.c(c.text2),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(l.amount, style: TempoType.bodyS.c(c.text2).tnum),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (check.sleepApps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(TempoRadii.md),
            ),
            child: Text(
              '${check.sleepApps.length} apps write sleep '
              '(${check.sleepApps.join(', ')}). Tempo uses ${check.sleepApps.first}; '
              'change it in You → Data source.',
              style: TempoType.bodyS.c(c.text2),
            ),
          ),
        ],
      ],
    );
  }
}
