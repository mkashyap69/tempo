import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;

import '../core/everyday.dart' show signalName, signalValue;
import '../core/metric_info.dart';
import '../design/components.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import 'baselines.dart';
import 'health_v3.dart' show NormalBandChart, scores30Provider;
import 'everyday_cards.dart' show bodySignalsProvider;
import 'nav.dart';

/// v3 Health: every overnight signal on a strip of your own normal.
class BodyCheckCard extends ConsumerWidget {
  const BodyCheckCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(bodySignalsProvider).value;
    if (b == null || b.readings.isEmpty) return const SizedBox.shrink();
    final c = context.c, s = context.s;
    final tone = b.off.length >= 2
        ? s.recLow
        : b.off.length == 1
        ? s.recMid
        : s.recHigh;
    return TempoCard(
      label: 'Body check',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Body check · last night')),
              if (b.level != sc.BodyLevel.learning)
                Text(
                  b.off.isEmpty ? 'All clear' : '${b.off.length} to watch',
                  style: TempoType.caption.c(tone),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(bodySummary(b), style: TempoType.bodyS.c(c.text1)),
          const SizedBox(height: 4),
          for (final r in b.readings) _SignalRow(r),
          const SizedBox(height: 8),
          Text(
            'The grey band is the middle of your own nights. Tap a row for what it means.',
            style: TempoType.caption.c(c.text3),
          ),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow(this.r);
  final sc.SignalReading r;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final place = sc.normalPlace(r);
    return Pressable(
      label: '${signalName(r.key)}: ${placeWord(place)}',
      onTap: () => push(context, MetricScreen(signalKey: r.key)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    signalName(r.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TempoType.bodyS.c(c.text1),
                  ),
                ),
                if (r.value != null) ...[
                  Text(
                    signalValue(r.key, r.value!),
                    style: TempoType.bodyS.c(c.text1).tnum,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  _short(place),
                  style: TempoType.caption.c(placeColor(context, place)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            NormalStrip(reading: r),
          ],
        ),
      ),
    );
  }

  static String _short(sc.NormalPlace p) => switch (p) {
    sc.NormalPlace.learning => 'learning',
    sc.NormalPlace.missing => 'no reading',
    sc.NormalPlace.inNormal => 'normal',
    sc.NormalPlace.better => 'better',
    sc.NormalPlace.outside => 'outside',
  };
}

Color placeColor(BuildContext context, sc.NormalPlace p) => switch (p) {
  sc.NormalPlace.better => context.s.recHigh,
  sc.NormalPlace.outside => context.s.recLow,
  sc.NormalPlace.inNormal => context.c.text2,
  _ => context.c.text3,
};

/// Your normal as a grey band, last night as a dot. Empty track while
/// learning or with no reading.
class NormalStrip extends StatelessWidget {
  const NormalStrip({super.key, required this.reading, this.height = 8});
  final sc.SignalReading reading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final band = sc.normalBand(reading);
    final v = reading.value;
    return SizedBox(
      height: height + 6,
      child: CustomPaint(
        painter: _StripPainter(
          band: band,
          value: band == null ? null : v,
          sd: reading.sd,
          track: c.surface3,
          bandColor: c.text2.withValues(alpha: .32),
          dot: c.text1,
          ring: c.bg,
          height: height,
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.band,
    required this.value,
    required this.sd,
    required this.track,
    required this.bandColor,
    required this.dot,
    required this.ring,
    required this.height,
  });
  final ({double lo, double hi})? band;
  final double? value, sd;
  final Color track, bandColor, dot, ring;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final r = Radius.circular(height / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(0, y - height / 2, size.width, y + height / 2, r),
      Paint()..color = track,
    );
    final b = band;
    if (b == null) return;
    // Axis: the band in the middle third-ish, wide enough for the dot.
    final pad = (sd ?? (b.hi - b.lo) / 2.6) * 2.2;
    var lo = b.lo - pad, hi = b.hi + pad;
    if (value != null) {
      lo = lo < value! - pad / 3 ? lo : value! - pad / 3;
      hi = hi > value! + pad / 3 ? hi : value! + pad / 3;
    }
    double x(double v) => (v - lo) / (hi - lo) * size.width;
    canvas.drawRRect(
      RRect.fromLTRBR(x(b.lo), y - height / 2, x(b.hi), y + height / 2, r),
      Paint()..color = bandColor,
    );
    if (value != null) {
      final cx = x(value!);
      canvas.drawCircle(
        Offset(cx, y),
        height * .9 + 1.5,
        Paint()..color = ring,
      );
      canvas.drawCircle(Offset(cx, y), height * .9, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.band != band || old.value != value || old.dot != dot;
}

/// v3 "any number, explained": what it is, your normal, last night, what
/// to do, when it's worth a doctor's view.
class MetricScreen extends ConsumerWidget {
  const MetricScreen({super.key, required this.signalKey});
  final String signalKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final b = ref.watch(bodySignalsProvider).value;
    final info = metricInfo(signalKey);
    sc.SignalReading? r;
    for (final x in b?.readings ?? const <sc.SignalReading>[]) {
      if (x.key == signalKey) r = x;
    }
    final place = r == null ? sc.NormalPlace.learning : sc.normalPlace(r);
    final band = r == null ? null : sc.normalBand(r);
    Widget block(String title, String body, {bool quiet = false}) => TempoCard(
      border: quiet ? c.lineStrong : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline(title),
          const SizedBox(height: 6),
          Text(body, style: TempoType.bodyS.c(quiet ? c.text2 : c.text1)),
        ],
      ),
    );
    return TempoPage(
      children: [
        DetailHeader(title: signalName(signalKey)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('Last night'),
            const SizedBox(height: 6),
            Text(
              r?.value == null ? '—' : signalValue(signalKey, r!.value!),
              style: TempoType.scoreL.c(c.text1),
            ),
            const SizedBox(height: 6),
            Text(
              placeWord(place),
              style: TempoType.body.c(placeColor(context, place)),
            ),
          ],
        ),
        if (r != null && band != null) ...[
          NormalStrip(reading: r, height: 12),
          Text(
            'Your normal: ${signalValue(signalKey, band.lo)} – ${signalValue(signalKey, band.hi)}, the middle of your own recent nights.',
            style: TempoType.caption.c(c.text2),
          ),
        ],
        // v3: the last 30 days against your normal (signals kept on the
        // daily score; the others are read from night samples).
        if (const {'rhr', 'hrv', 'stress'}.contains(signalKey))
          if (ref.watch(scores30Provider).value case final days?
              when days.isNotEmpty)
            TempoCard(
              key: const ValueKey('metric-chart'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Overline('Last ${days.length} days'),
                  const SizedBox(height: 10),
                  NormalBandChart(
                    values: [
                      for (final d in days)
                        switch (signalKey) {
                          'rhr' => d.rhr,
                          'hrv' => d.hrv,
                          _ => d.hrvProxy,
                        },
                    ],
                    lo: band == null
                        ? null
                        : signalKey == 'hrv'
                        ? math.exp(band.lo)
                        : band.lo,
                    hi: band == null
                        ? null
                        : signalKey == 'hrv'
                        ? math.exp(band.hi)
                        : band.hi,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The grey band is your normal; the dot is last night.',
                    style: TempoType.caption.c(c.text3),
                  ),
                ],
              ),
            ),
        if (info != null) block('What it is', info.what),
        block('What to do', placeAdvice(place)),
        if (info != null) block('What moves it', info.moves),
        if (info != null)
          block('When it’s worth a doctor’s view', info.doctor, quiet: true),
        TempoButton(
          'See your baselines',
          kind: ButtonKind.secondary,
          expand: true,
          onTap: () => push(context, const BaselinesScreen()),
        ),
        Text(
          'Tempo shows patterns in your own data. It is not a medical device and does not diagnose.',
          style: TempoType.caption.c(c.text3),
        ),
      ],
    );
  }
}
