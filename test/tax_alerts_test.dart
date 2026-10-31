import 'package:flutter_test/flutter_test.dart';
import 'package:portfel/alerts.dart';
import 'package:portfel/models.dart';
import 'package:portfel/tax.dart';

Tx tx(String date, String side, String asset, double qty, double total, {double fee = 0}) =>
    Tx(id: newId('t'), date: date, side: side, asset: asset, qty: qty, total: total, fee: fee);

void main() {
  test('pół roku od końca miesiąca zakupu', () {
    expect(metalExemptAfter('2025-03-15'), DateTime(2025, 9, 30));
    expect(metalSaleExempt('2025-03-15', '2025-09-30'), isFalse);
    expect(metalSaleExempt('2025-03-15', '2025-10-01'), isTrue);
    expect(metalExemptAfter('2025-08-01'), DateTime(2026, 2, 28));
  });

  test('FIFO: waluty i kruszce w zestawieniu rocznym', () {
    final y = taxYears([
      tx('2025-01-10', 'buy', 'USD', 100, 400, fee: 2),
      tx('2025-02-10', 'buy', 'USD', 100, 420),
      tx('2025-06-10', 'sell', 'USD', 150, 630, fee: 3),
      tx('2025-01-05', 'buy', 'XAU', 10, 3000),
      tx('2025-05-20', 'buy', 'XAU', 10, 3500),
      tx('2025-10-02', 'sell', 'XAU', 15, 6000),
    ], [
      Deposit(id: 'd', principal: 10000, status: 'closed', end: '2025-12-01', interest: 300, tax: 57),
    ])[2025]!;
    final usd = y.currencies['USD']!;
    expect(usd.revenue, closeTo(630, 1e-9));
    expect(usd.cost, closeTo(402 + 210 + 3, 1e-9)); // 100 szt. po 4.02 + 50 po 4.20 + prowizja
    // 10 g z 05.01 – wolne (po 31.07); 5 g z 20.05 – przed 30.11 → do opodatkowania
    expect(y.metalsExempt.revenue, closeTo(4000, 1e-9));
    expect(y.metalsExempt.cost, closeTo(3000, 1e-9));
    expect(y.metalsTaxable.revenue, closeTo(2000, 1e-9));
    expect(y.metalsTaxable.income, closeTo(250, 1e-9));
    expect(y.depositInterest, 300);
    expect(y.depositTax, 57);
    expect(y.oversold, isFalse);
  });

  test('alerty jednorazowe', () {
    final a = [
      PriceAlert(id: '1', asset: 'XAU', above: true, price: 500),
      PriceAlert(id: '2', asset: 'EUR', above: false, price: 4.2),
    ];
    final f = fireAlerts(a, (c) => c == 'XAU' ? 520 : 4.3);
    expect(f.map((x) => x.id), ['1']);
    expect(a[0].active, isFalse);
    expect(fireAlerts(a, (c) => 600), isEmpty);
    final j = PriceAlert.fromJson(a[0].toJson());
    expect((j.active, j.firedRate), (false, 520.0));
  });

  test('przypomnienia o lokatach', () {
    final r = depositReminders([
      Deposit(id: 'a', principal: 1000, bank: 'Bank', end: '2026-12-10'),
      Deposit(id: 'b', principal: 1000, end: '2026-01-01'),
      Deposit(id: 'c', principal: 1000, status: 'closed', end: '2026-12-10'),
    ], daysBefore: 3, now: DateTime(2026, 11, 1));
    expect(r.length, 2);
    expect(r.first.$1, DateTime(2026, 12, 7, 9));
    expect(r.last.$1, DateTime(2026, 12, 10, 9));
  });
}
