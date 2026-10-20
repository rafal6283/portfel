import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/calc.dart';
import 'package:portfel/models.dart';

Tx tx(String id, String date, String side, String asset, double qty, double total, {double fee = 0}) =>
    Tx(id: id, date: date, side: side, asset: asset, qty: qty, total: total, fee: fee, createdAt: 0);

void main() {
  group('FIFO', () {
    test('częściowa sprzedaż bierze najstarszą partię', () {
      final p = computePortfolio([
        tx('a', '2020-01-01', 'buy', 'USD', 1000, 3800),
        tx('b', '2020-02-01', 'buy', 'USD', 1000, 4000),
        tx('c', '2020-03-01', 'sell', 'USD', 1500, 6150),
      ], (c) => 4.0);
      final r = p.rows.single;
      expect(r.qty, closeTo(500, 1e-9));
      expect(r.cost, closeTo(2000, 1e-6)); // zostaje pół drugiej partii po 4,00
      expect(p.sells['c']!.gain, closeTo(6150 - 3800 - 2000, 1e-6));
      expect(r.unrealized, closeTo(0, 1e-6));
    });

    test('prowizja zwiększa koszt i zmniejsza przychód', () {
      final p = computePortfolio([
        tx('a', '2025-12-14', 'buy', 'XAU', 10, 5000, fee: 20),
        tx('b', '2026-01-10', 'sell', 'XAU', 10, 5600, fee: 10),
      ], (c) => 600);
      expect(p.sells['b']!.gain, closeTo(5600 - 10 - 5020, 1e-6));
      expect(p.rows.single.closed, isTrue);
      expect(p.fees, closeTo(30, 1e-9));
    });

    test('sprzedaż ponad stan jest oznaczona i nie daje zysku z nadwyżki', () {
      final p = computePortfolio([
        tx('a', '2022-01-01', 'buy', 'CHF', 50, 230),
        tx('b', '2022-02-01', 'sell', 'CHF', 100, 480),
      ], (c) => 4.7);
      expect(p.rows.single.oversold, isTrue);
      expect(p.sells['b']!.gain, closeTo(480 - 230 - 50 * 4.8, 1e-6));
    });

    test('brak kursu = brak wartości', () {
      final p = computePortfolio([tx('a', '2022-01-01', 'buy', 'NOK', 100, 40)], (c) => null);
      expect(p.rows.single.value, isNull);
      expect(p.value, 0);
    });
  });

  group('Lokaty', () {
    test('zakończona z wypłatą', () {
      final d = Deposit(id: '1', principal: 10000, start: '2011-06-24', end: '2012-06-25', status: 'closed', payout: 10484.48);
      final c = depositCalc(d);
      expect(c.net, closeTo(484.48, 1e-6));
      expect(c.days, 367);
      expect(c.annual, closeTo(484.48 / 10000 * 365 / 367, 1e-9));
    });

    test('zakończona z odsetkami i podatkiem', () {
      final d = Deposit(id: '1', principal: 10000, status: 'closed', interest: 815, tax: 154.85);
      expect(depositCalc(d).net, closeTo(660.15, 1e-6));
    });

    test('noAnn ukrywa % r/r', () {
      final d = Deposit(id: '1', principal: 100, start: '2020-01-01', end: '2021-01-01', status: 'closed', payout: 110, noAnn: true);
      expect(depositCalc(d).annual, isNull);
    });

    test('trwająca nalicza liniowo po podatku', () {
      final d = Deposit(id: '1', principal: 36500, start: '2026-01-01', rate: 5, status: 'open');
      final c = depositCalc(d, today: '2026-01-11');
      expect(c.days, 10);
      expect(c.net, closeTo(36500 * 0.05 * 10 / 365 * 0.81, 1e-6));
      expect(c.value, closeTo(36500 + c.net!, 1e-9));
    });

    test('trwająca bez oprocentowania: wartość = kapitał', () {
      final d = Deposit(id: '1', principal: 503000, start: '2024-09-26', status: 'open');
      final c = depositCalc(d, today: '2026-10-18');
      expect(c.net, 0);
      expect(c.value, 503000);
    });

    test('nieznany wynik nie wlicza się', () {
      final t = depositTotals([
        Deposit(id: '1', principal: 10000, status: 'unknown'),
        Deposit(id: '2', principal: 100, status: 'closed', payout: 150),
      ]);
      expect(t.net, 50);
      expect(t.unknown, 1);
    });
  });

  test('JSON: nieznane pola są zachowane', () {
    final t = Tx.fromJson({'id': 'x', 'date': '2020-01-01', 'side': 'buy', 'asset': 'USD', 'qty': 1, 'total': 4, 'src': 'mbank'});
    expect(t.toJson()['src'], 'mbank');
    final d = Deposit.fromJson({'id': 'y', 'principal': 5, 'status': 'closed', 'payout': 6, 'foo': 1});
    expect(d.toJson()['foo'], 1);
    expect(d.payout, 6);
  });

  group('Gotówka i nieruchomości', () {
    test('gotówka w walucie po kursie, PLN 1:1, brak kursu nie wlicza się', () {
      final t = cashTotals([
        CashEntry(id: '1', currency: 'PLN', amount: 1000),
        CashEntry(id: '2', currency: 'EUR', amount: 100),
        CashEntry(id: '3', currency: 'NOK', amount: 50),
      ], (c) => c == 'EUR' ? 4.3 : null);
      expect(t.value, closeTo(1430, 1e-9));
      expect(t.missingRate, isTrue);
      expect(t.byCurrency['EUR'], 100);
    });

    test('nieruchomość posiadana: wycena minus zakup z kosztami, plus najem', () {
      final p = Property(id: 'a', buyDate: '2020-01-01', buyPrice: 400000, buyCosts: 20000, value: 550000, income: 30000);
      final c = propertyCalc(p, today: '2025-01-01');
      expect(c.cost, 420000);
      expect(c.value, 550000);
      expect(c.change, 130000);
      expect(c.net, 160000);
      expect(c.annual, isNotNull);
    });

    test('bez wyceny wartość = koszt, wynik 0', () {
      final c = propertyCalc(Property(id: 'b', buyPrice: 300000, buyCosts: 10000));
      expect(c.value, 310000);
      expect(c.net, 0);
    });

    test('sprzedana: zysk zrealizowany, wartość 0', () {
      final p = Property(id: 'c', buyDate: '2015-05-01', buyPrice: 250000, buyCosts: 15000, sold: true, sellDate: '2024-05-01', sellPrice: 480000, sellCosts: 12000);
      final c = propertyCalc(p);
      expect(c.value, 0);
      expect(c.net, closeTo(480000 - 12000 - 265000, 1e-9));
      final t = propertyTotals([p, Property(id: 'd', buyPrice: 100, value: 150)]);
      expect(t.sold, 1);
      expect(t.owned, 1);
      expect(t.value, 150);
    });

    test('JSON gotówki i nieruchomości', () {
      final c = CashEntry.fromJson({'id': 'x', 'currency': 'USD', 'amount': 12.5, 'foo': 1});
      expect(c.toJson()['foo'], 1);
      final p = Property.fromJson({'id': 'y', 'buyPrice': 1, 'sold': true, 'sellPrice': 2});
      expect(p.sold, isTrue);
      expect(Property.fromJson(p.toJson()).sellPrice, 2);
    });
  });
}
