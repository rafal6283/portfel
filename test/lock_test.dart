import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/lock/lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('PIN: poprawny i błędny, kod nie jest zapisany jawnie', () async {
    final l = LockService.I;
    await l.load();
    expect(l.enabled, isFalse);
    await l.setSecret(LockMode.pin, '2580', 4);
    expect(l.mode, LockMode.pin);
    expect(await l.verify('1111'), isFalse);
    expect(await l.verify('2580'), isTrue);
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys()) {
      expect(p.get(k).toString().contains('2580'), isFalse, reason: k);
    }
  });

  test('po 5 błędach jest przerwa, nawet dobry kod nie przechodzi', () async {
    final l = LockService.I;
    await l.setSecret(LockMode.pattern, '0-1-2-5', 4);
    for (var i = 0; i < 5; i++) {
      expect(await l.verify('0-3-6'), isFalse);
    }
    expect(await l.cooldown(), greaterThan(Duration.zero));
    expect(await l.verify('0-1-2-5'), isFalse);
  });

  test('migracja: stara blokada biometrią i wyłączenie', () async {
    SharedPreferences.setMockInitialValues({'lock': true});
    final l = LockService.I;
    await l.load();
    expect(l.mode, LockMode.biometric);
    await l.disable();
    await l.load();
    expect(l.enabled, isFalse);
  });
}
