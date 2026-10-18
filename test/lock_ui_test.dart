import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/lock/lock_screens.dart';
import 'package:portfel/lock/lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> tapDigits(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    await t.tap(find.widgetWithText(TextButton, d));
    await t.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ustawienie PIN-u: wpisz, zatwierdź, powtórz → zapisane i ekran zamknięty', (t) async {
    await LockService.I.disable();
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                    context, MaterialPageRoute(builder: (_) => const SetSecretScreen(mode: LockMode.pin)));
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    expect(find.text('Wpisz nowy PIN (4–8 cyfr)'), findsOneWidget);

    await tapDigits(t, '2580');
    await t.tap(find.byIcon(Icons.check));
    await t.pumpAndSettle();
    expect(find.text('Wpisz PIN jeszcze raz'), findsOneWidget);

    await tapDigits(t, '2580');
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();

    expect(LockService.I.mode, LockMode.pin);
    expect(result, isTrue);
    expect(find.byType(SetSecretScreen), findsNothing);
  });

  testWidgets('odblokowanie PIN-em', (t) async {
    await LockService.I.setSecret(LockMode.pin, '1357', 4);
    var unlocked = false;
    await t.pumpWidget(MaterialApp(home: UnlockScreen(onUnlocked: () => unlocked = true)));
    await t.pump();
    await tapDigits(t, '1357');
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(unlocked, isTrue);
  });
}
