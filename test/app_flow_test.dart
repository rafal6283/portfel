import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/main.dart';
import 'package:portfel/security/lock.dart';
import 'package:portfel/ui/settings.dart';
import 'package:portfel/ui/tx_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('po odblokowaniu PIN-em otwierają się ustawienia i formularz transakcji', (t) async {
    await Lock.setSecret(LockMethod.pin, '2468');
    await t.pumpWidget(const PortfelApp());
    // wczytanie danych i ustawień idzie przez prawdziwe I/O – dajemy mu chwilę poza zegarem testu
    await t.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await t.pumpAndSettle();
    expect(find.text('Wpisz PIN'), findsOneWidget);

    for (final d in '2468'.split('')) {
      await t.tap(find.text(d));
      await t.pump();
    }
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    await t.pumpAndSettle();
    expect(find.text('Wpisz PIN'), findsNothing);

    await t.tap(find.byIcon(Icons.settings_outlined));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.text('Transakcja'));
    await t.pumpAndSettle();
    expect(find.byType(TxForm), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
