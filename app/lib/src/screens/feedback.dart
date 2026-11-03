import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../state/providers.dart';

enum FeedbackKind { bug, score, idea, other }

String feedbackKindLabel(FeedbackKind k) => switch (k) {
  FeedbackKind.bug => 'Something broke',
  FeedbackKind.score => 'A score looks off',
  FeedbackKind.idea => 'An idea',
  FeedbackKind.other => 'Other',
};

/// Exactly what a feedback report says: the category, the user's words
/// and, if they choose, app details. No health values, ever: the details
/// are the version, the scoring version, the phone's OS, the data source
/// and when it last synced.
String feedbackText({
  required FeedbackKind kind,
  required String words,
  Map<String, String>? details,
}) {
  final b = StringBuffer()
    ..writeln('Tempo feedback · ${feedbackKindLabel(kind)}')
    ..writeln()
    ..writeln(words.trim().isEmpty ? '(no message)' : words.trim());
  if (details != null && details.isNotEmpty) {
    b
      ..writeln()
      ..writeln('— App details —');
    for (final e in details.entries) {
      b.writeln('${e.key}: ${e.value}');
    }
  }
  return b.toString().trimRight();
}

/// You → Help → Send feedback: a category, your words, and a preview of
/// exactly what gets sent. Until the beta's feedback service exists
/// (Backend plan G3), Send opens the share sheet, so the user picks how it
/// leaves the phone (Mail, a message) and Tempo makes no network call.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _words = TextEditingController();
  var _kind = FeedbackKind.bug;
  var _details = true;

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  Map<String, String> _appDetails() {
    final t = ref.read(todayProvider).value;
    final source = ref.read(dataSourceProvider);
    final sync = ref.read(syncProvider);
    return {
      'App': 'Tempo 1.0',
      'Scoring': 'algo ${sc.algoVersion}',
      'Phone': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Reads from': source.label,
      'Last sync': t?.lastSync == null
          ? 'never'
          : '${dayShort(t!.lastSync!)} ${clockOf(t.lastSync!)}',
      'Sync state': sync.problem.name,
      'Nights counted': '${t?.nights ?? 0}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = feedbackText(
      kind: _kind,
      words: _words.text,
      details: _details ? _appDetails() : null,
    );
    return TempoPage(
      children: [
        const DetailHeader(
          title: 'Send feedback',
          subtitle: 'Read by the people who build Tempo',
        ),
        const Overline('What’s it about'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in FeedbackKind.values)
              TempoChip(
                feedbackKindLabel(k),
                height: 40,
                selected: _kind == k,
                onTap: () => setState(() => _kind = k),
              ),
          ],
        ),
        const Overline('In your words'),
        Container(
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: BorderRadius.circular(TempoRadii.md),
            border: Border.all(color: c.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: TextField(
            controller: _words,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: TempoType.body.c(c.text1),
            cursorColor: c.text1,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: switch (_kind) {
                FeedbackKind.bug => 'What happened, and what did you expect?',
                FeedbackKind.score =>
                  'Which score, which day, and how did you actually feel?',
                FeedbackKind.idea => 'What would make Tempo better for you?',
                FeedbackKind.other => 'Anything on your mind',
              },
              hintStyle: TempoType.body.c(c.text3),
            ),
          ),
        ),
        CardList(
          children: [
            ListRow(
              'Include app details',
              sub: 'Version, phone, data source, last sync. No health data.',
              chevron: false,
              trailing: TempoSwitch(
                label: 'Include app details',
                value: _details,
                onChanged: (v) => setState(() => _details = v),
              ),
            ),
          ],
        ),
        const Overline('Exactly what gets sent'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(TempoRadii.md),
          ),
          child: SelectableText(text, style: TempoType.monoS.c(c.text2)),
        ),
        TempoButton(
          'Send',
          expand: true,
          onTap: _words.text.trim().isEmpty
              ? null
              : () => SharePlus.instance.share(
                  ShareParams(text: text, subject: 'Tempo feedback'),
                ),
        ),
        Text(
          'Opens your share sheet: choose Mail or a message. Tempo itself '
          'sends nothing.',
          textAlign: TextAlign.center,
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}
