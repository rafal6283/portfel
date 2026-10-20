import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/security/lock.dart';
import 'package:portfel/ui/lock_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> tapDigits(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    await t.tap(find.text(d));
    await t.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ustawienie PIN-u: wpisz, ✓, powtórz → zapisane i ekran zamknięty', (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                    context, MaterialPageRoute(builder: (_) => const LockSetupScreen(method: LockMethod.pin)));
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('start'));
    await t.pumpAndSettle();

    await tapDigits(t, '2580');
    await t.tap(find.byIcon(Icons.check));
    await t.pumpAndSettle();
    expect(find.text('Powtórz PIN'), findsOneWidget);

    await tapDigits(t, '2580'); // drugi raz bez zatwierdzania
    await t.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(LockSetupScreen), findsNothing);
    expect((await Lock.load()).method, LockMethod.pin);
    expect(await Lock.pinLength(), 4);
  });

  testWidgets('odblokowanie PIN-em bez zatwierdzania', (t) async {
    await Lock.setSecret(LockMethod.pin, '1357');
    final c = await Lock.load();
    var unlocked = false;
    await t.pumpWidget(MaterialApp(home: LockScreen(config: c, onUnlocked: () => unlocked = true)));
    await t.pumpAndSettle();
    await tapDigits(t, '1357');
    await t.pumpAndSettle();
    expect(unlocked, isTrue);
  });
}
