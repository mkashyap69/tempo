import 'package:scoring/scoring.dart' as sc;
import 'package:tempo/src/core/notifications.dart';

/// Records what the coach would schedule, instead of the platform plugin.
class FakeNotificationSink implements NotificationSink {
  final pending = <int, sc.NudgeSpec>{};
  final scheduled = <sc.NudgeSpec>[];
  var legacyCancelled = 0;

  @override
  Future<void> schedule(sc.NudgeSpec n, {bool precise = false}) async {
    pending[n.id] = n;
    scheduled.add(n);
  }

  @override
  Future<void> cancel(int id) async => pending.remove(id);

  @override
  Future<void> cancelLegacy() async => legacyCancelled++;
}
