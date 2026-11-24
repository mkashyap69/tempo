import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scoring/scoring.dart' as sc;
import 'package:store/store.dart';
import 'package:tempo/src/core/health_sync.dart' show daySources;
import 'package:tempo/src/core/notes.dart';

void main() {
  late TempoDb db;
  setUp(() => db = TempoDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('notes per routine, exercise and session; empty deletes', () async {
    await saveNote(db, NoteScope.routine, 'Upper A', 'Warm up shoulders');
    await saveNote(db, NoteScope.exercise, 'bench_press', 'Elbows in');
    await saveNote(
      db,
      NoteScope.session,
      sessionRef(DateTime(2026, 11, 24)),
      'Short on time',
    );
    expect(
      await loadNote(db, NoteScope.routine, 'Upper A'),
      'Warm up shoulders',
    );
    expect(await loadNote(db, NoteScope.exercise, 'bench_press'), 'Elbows in');
    expect(
      await loadNote(db, NoteScope.session, sessionRef(DateTime(2026, 11, 25))),
      isNull,
    );
    await saveNote(db, NoteScope.exercise, 'bench_press', '  ');
    expect(await loadNote(db, NoteScope.exercise, 'bench_press'), isNull);
    expect(await loadNote(db, NoteScope.routine, 'Upper A'), isNotNull);
  });

  test('a sore reflection is offered once, then handled', () async {
    final start = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch - 5 * 3600 * 1000,
    );
    await saveReflection(
      db,
      sc.Reflection(
        at: start,
        title: 'Lower body',
        tags: {sc.ReflectTag.sore},
        text: 'Legs heavy',
      ),
    );
    final r = (await loadReflection(db, start))!;
    expect(r.text, 'Legs heavy');
    final call = (await loadReflectCall(db))!;
    expect(call.action, sc.ReflectAction.easeWeek);
    await markHandled(db, start);
    expect(await loadReflectCall(db), isNull);
    await saveReflection(db, sc.Reflection(at: start, title: 'Lower body'));
    expect(await loadReflection(db, start), isNull);
  });

  test('a day with no Health records lists no sources', () async {
    expect(await daySources(db, DateTime(2026, 11, 23)), isEmpty);
  });
}
