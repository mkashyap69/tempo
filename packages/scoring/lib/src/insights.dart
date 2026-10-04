/// Journal insights: next-morning recovery with vs without a tag.
library;

/// Check-ins needed before any insight is shown.
const insightsUnlockAt = 30;

/// Smallest group size for a pattern.
const insightMinNights = 5;

enum Confidence { notEnough, none, low, moderate, high }

/// One tagged night: the tag value on day D and recovery on morning D+1.
final class TaggedNight {
  const TaggedNight(this.tagged, this.nextRecovery);
  final bool tagged;
  final double nextRecovery;
}

final class TagInsight {
  const TagInsight({
    required this.nWith,
    required this.nWithout,
    required this.avgWith,
    required this.avgWithout,
    required this.consistent,
    required this.confidence,
  });
  final int nWith, nWithout;
  final double avgWith, avgWithout;

  /// Tagged nights on the same side of the untagged average as the effect.
  final int consistent;
  final Confidence confidence;

  double get diff => avgWith - avgWithout;
}

TagInsight tagInsight(List<TaggedNight> nights) {
  final yes = [
    for (final n in nights)
      if (n.tagged) n.nextRecovery,
  ];
  final no = [
    for (final n in nights)
      if (!n.tagged) n.nextRecovery,
  ];
  double mean(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  final aw = mean(yes), an = mean(no);
  final diff = aw - an;
  final consistent = yes.where((v) => diff < 0 ? v < an : v > an).length;
  Confidence c;
  if (yes.length < insightMinNights || no.length < insightMinNights) {
    c = Confidence.notEnough;
  } else if (diff.abs() < 3) {
    c = Confidence.none;
  } else {
    final share = consistent / yes.length;
    c = yes.length >= 15 && share >= 0.8
        ? Confidence.high
        : yes.length >= 8 && share >= 0.7
        ? Confidence.moderate
        : Confidence.low;
  }
  return TagInsight(
    nWith: yes.length,
    nWithout: no.length,
    avgWith: aw,
    avgWithout: an,
    consistent: consistent,
    confidence: c,
  );
}
