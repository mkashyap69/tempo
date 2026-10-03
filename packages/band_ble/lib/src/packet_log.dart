import 'dart:convert';

import 'protocol.dart';

enum PacketDir { tx, rx, info }

/// One line in a docs/packets/ capture (JSON Lines).
final class PacketEvent {
  PacketEvent({
    required this.dir,
    this.characteristic,
    this.bytes,
    this.note,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final DateTime at;
  final PacketDir dir;
  final String? characteristic;

  /// Bytes as sent or received. Null for redacted or info-only events.
  final List<int>? bytes;
  final String? note;

  String toJsonLine() => jsonEncode({
    'ts': at.toUtc().toIso8601String(),
    'dir': dir.name,
    if (characteristic != null) 'char': characteristic,
    if (bytes != null) 'hex': hex(bytes!),
    if (note != null) 'note': note,
  });
}

/// Sink for every packet the band layer sends or receives.
abstract interface class PacketLog {
  void record(PacketEvent e);
}

final class NoopPacketLog implements PacketLog {
  const NoopPacketLog();
  @override
  void record(PacketEvent e) {}
}
