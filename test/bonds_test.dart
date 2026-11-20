import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/bonds.dart';

void main() {
  test('rodzaj z nazwy serii', () {
    expect(bondTypeOf('EDO1136')!.months, 120);
    expect(bondTypeOf('coi0730')!.capitalized, isFalse);
    expect(bondTypeOf('XYZ'), isNull);
  });

  test('EDO: kapitalizacja, odsetki narosłe, opłata i podatek przy wcześniejszym wykupie', () {
    final b = Bond(id: 'b1', series: 'EDO0135', date: '2025-01-10', count: 10, rates: [5.35, 6.0]);
    final c = bondCalc(b, today: '2026-07-10');
    expect(c.period, 2);
    expect(c.grossValue, closeTo(1084.84, 0.001)); // 1053,50 po roku + 181/365 z 6%
    expect(c.fee, 30); // 3 zł × 10
    expect(c.tax, 10); // 19% od (84,84 − 30), do pełnych złotych
    expect(c.netIfRedeemed, closeTo(1044.84, 0.001));
    expect(c.estimated, isFalse);
    expect(c.maturity, '2035-01-10');
  });

  test('opłata nie większa niż narosłe odsetki', () {
    final b = Bond(id: 'b2', series: 'EDO1136', date: '2026-11-01', count: 10, rates: [5.35]);
    final c = bondCalc(b, today: '2026-11-11');
    expect(c.fee, closeTo(c.grossValue - 1000, 0.001));
    expect(c.netIfRedeemed, closeTo(1000, 0.001));
  });

  test('COI: odsetki wypłacane co rok (po podatku), w terminie bez opłaty', () {
    final b = Bond(id: 'b3', series: 'COI0726', date: '2022-07-15', count: 10, rates: [5.0, 14.25, 4.0, 5.5]);
    final c = bondCalc(b, today: '2026-08-01');
    expect(c.matured, isTrue);
    expect(c.fee, 0);
    expect(c.netIfRedeemed, closeTo(1000, 0.001));
    expect(c.paidOut, closeTo(287.5 * 0.81, 0.001));
    expect(c.net, closeTo(232.875, 0.001));
  });

  test('brak wpisanej stopy: inflacja (dwa miesiące przed okresem) + marża, oznaczone jako szacunek', () {
    final b = Bond(id: 'b4', series: 'EDO0135', date: '2025-01-10', count: 1, rates: [5.35]);
    final c = bondCalc(b, today: '2026-03-01', inflationYoY: (m) => m == '2025-11' ? 4.0 : null);
    expect(c.currentRate, 6.0); // 4% + marża 2% z oferty
    expect(c.estimated, isTrue);
    // ujemna inflacja liczy się jak zero
    final d = bondCalc(b, today: '2026-03-01', inflationYoY: (_) => -1.0);
    expect(d.currentRate, 2.0);
  });

  test('zapis i odczyt oraz podsumowanie bez wykupionych', () {
    final b = Bond(id: 'b5', series: 'TOS1128', date: '2025-11-05', count: 5, rates: [4.4], note: 'IKE');
    final back = Bond.fromJson(b.toJson());
    expect(back.toJson(), b.toJson());
    final r = Bond(id: 'b6', series: 'OTS0226', date: '2025-11-05', count: 3, rates: [2.0], redeemed: '2026-02-05');
    final t = bondTotals([b, r], today: '2026-01-05');
    expect(t.open, 1);
    expect(t.principal, 500);
  });
}
