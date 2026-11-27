import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tempo/src/billing/pro.dart';
import 'package:tempo/src/design/theme.dart';
import 'package:tempo/src/screens/paywall.dart';

Widget _app(bool pro) => ProviderScope(
  overrides: [proProvider.overrideWithValue(pro)],
  child: MaterialApp(
    theme: tempoTheme(Brightness.dark),
    home: const ProGate(
      tab: true,
      title: 'Plan',
      lockTitle: 'Your coach',
      body: 'Each morning Tempo plans your day.',
      entry: PaywallEntry.coach,
      child: Text('the coach'),
    ),
  ),
);

void main() {
  testWidgets('Pro shows the feature', (t) async {
    await t.pumpWidget(_app(true));
    expect(find.text('the coach'), findsOneWidget);
    expect(find.text('See Tempo Pro'), findsNothing);
  });

  testWidgets('Free shows the lock with a way in', (t) async {
    await t.pumpWidget(_app(false));
    expect(find.text('the coach'), findsNothing);
    expect(find.text('Your coach'), findsOneWidget);
    expect(find.text('See Tempo Pro'), findsOneWidget);
  });
}
