import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart' as st;

import '../core/score_service.dart';
import 'format.dart';
import 'providers.dart';
import 'theme.dart';
import 'widgets.dart';

const _daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});
  @override
  ConsumerState<TrendsScreen> createState() => _TrendsState();
}

class _TrendsState extends ConsumerState<TrendsScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final scores = ref.watch(recentScoresProvider(_days));
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trends',
          style: TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
        children: [
          Center(
            child: SegmentedButton<int>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: ink,
                selectedForegroundColor: Colors.white,
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE4E4EB)),
              ),
              segments: const [
                ButtonSegment(value: 7, label: Text('7 d')),
                ButtonSegment(value: 30, label: Text('30 d')),
                ButtonSegment(value: 90, label: Text('90 d')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
          ),
          const SizedBox(height: 16),
          scores.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const SoftCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No historical data yet. Sync your band.'),
                    ),
                  ),
                );
              }

              // Weekly Prominent Rounded Bar Chart (screenshot right frame)
              final latest = rows.last;
              final latestRec = latest.recovery;
              final latestRhr = latest.rhr;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Weekly Strain Volume Card
                  SoftCard(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Weekly goal',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: ink,
                              ),
                            ),
                            Text(
                              '${rows.length} days ›',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 180,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (int i = 0; i < rows.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(child: _PillBar(score: rows[i])),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Dual Biomarker Grid (Intensity + Resting HR)
                  Row(
                    children: [
                      // Intensity / Recovery %
                      Expanded(
                        child: SoftCard(
                          blob: true,
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Intensity',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                latestRec == null
                                    ? '–'
                                    : '${latestRec.round()}%',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                latest.calibrating
                                    ? 'Calibrating baseline'
                                    : '${sc.recoveryColor(latestRec!).name} recovery',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Solid Orange Resting HR Tile
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(cardRadius),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33FF5A1F),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Resting HR',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text.rich(
                                TextSpan(
                                  text: latestRhr == null
                                      ? '–'
                                      : '${latestRhr.round()}',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: ' bpm',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Sleep average',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 3. Multi-day Metric List / Summary
                  SoftCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'History & Biomarkers',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final s in rows.reversed.take(7))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  s.date,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: ink,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'Strain ${n1(s.strain)}',
                                      style: const TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      s.recovery == null
                                          ? '–'
                                          : '${s.recovery!.round()}% Rec',
                                      style: TextStyle(
                                        color: recoveryColour(s.recovery),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PillBar extends StatelessWidget {
  const _PillBar({required this.score});
  final st.DailyScore score;

  @override
  Widget build(BuildContext context) {
    final strain = score.strain.clamp(0.0, 21.0);
    // Max height 130px for 21 strain
    final barHeight = (strain / 21.0 * 130).clamp(12.0, 130.0);
    final date = parseDateKey(score.date);
    final dayLabel = _daysOfWeek[date.weekday - 1];

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          strain.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: barHeight,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22FF5A1F),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          dayLabel,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ],
    );
  }
}
