// Zestawienie roczne do rozliczenia podatku: FIFO z datami zakupu (czysty Dart, testowany w CI).
//
// Kruszce (złoto, srebro w sztabkach/monetach) to „rzeczy ruchome”: sprzedaż po upływie pół roku
// licząc od końca miesiąca zakupu jest wolna od podatku; wcześniejsza – dochód w PIT-36 (skala).
// Waluty: wynik sprzedaży (przychód, koszt FIFO, dochód) – sposób opodatkowania zależy od sytuacji
// (interpretacje są niejednolite), aplikacja tylko liczy kwoty.
// Lokaty: podatek Belki pobiera bank, w zestawieniu tylko informacyjnie.
import 'calc.dart';
import 'models.dart';

class TaxSum {
  double revenue = 0; // przychód ze sprzedaży
  double cost = 0; // koszty: zakup FIFO z prowizjami + prowizja sprzedaży
  double get income => revenue - cost;
  void add(double r, double c) {
    revenue += r;
    cost += c;
  }
}

class TaxYear {
  final int year;
  final Map<String, TaxSum> currencies = {}; // kod waluty → wynik
  final TaxSum metalsTaxable = TaxSum(); // sprzedane przed upływem pół roku
  final TaxSum metalsExempt = TaxSum(); // po upływie pół roku – wolne od podatku
  final Map<String, TaxSum> metalsTaxableBy = {};
  double depositInterest = 0; // odsetki brutto z lokat zakończonych w roku
  double depositTax = 0; // podatek pobrany przez bank (lub 19% szacunkowo)
  bool oversold = false; // sprzedaż bez pokrycia w zakupach – wynik niepełny
  TaxYear(this.year);

  TaxSum get currencyTotal {
    final t = TaxSum();
    for (final s in currencies.values) {
      t.add(s.revenue, s.cost);
    }
    return t;
  }

  bool get isEmpty => currencies.isEmpty && metalsTaxable.revenue == 0 && metalsExempt.revenue == 0 && depositInterest == 0;
}

/// Ostatni dzień „pół roku od końca miesiąca zakupu”; sprzedaż PO tym dniu jest wolna od podatku.
DateTime metalExemptAfter(String buyIso) {
  final d = DateTime.parse(buyIso);
  return DateTime(d.year, d.month + 7, 0);
}

bool metalSaleExempt(String buyIso, String sellIso) => DateTime.parse(sellIso).isAfter(metalExemptAfter(buyIso));

class _Lot {
  double q;
  final double unit;
  final String date;
  _Lot(this.q, this.unit, this.date);
}

Map<int, TaxYear> taxYears(List<Tx> txs, List<Deposit> deposits) {
  final out = <int, TaxYear>{};
  TaxYear y(String iso) {
    final yr = int.parse(iso.substring(0, 4));
    return out.putIfAbsent(yr, () => TaxYear(yr));
  }

  final lots = <String, List<_Lot>>{};
  for (final t in [...txs]..sort(compareTx)) {
    if (t.qty <= 0) continue;
    final l = lots.putIfAbsent(t.asset, () => []);
    if (t.isBuy) {
      l.add(_Lot(t.qty, (t.total + t.fee) / t.qty, t.date));
      continue;
    }
    final ty = y(t.date);
    final unitSell = t.total / t.qty;
    final feeUnit = t.fee / t.qty;
    var left = t.qty;
    while (left > 1e-12 && l.isNotEmpty) {
      final lot = l.first;
      final take = lot.q < left ? lot.q : left;
      final rev = take * unitSell;
      final cost = take * (lot.unit + feeUnit);
      if (isMetal(t.asset)) {
        if (metalSaleExempt(lot.date, t.date)) {
          ty.metalsExempt.add(rev, cost);
        } else {
          ty.metalsTaxable.add(rev, cost);
          ty.metalsTaxableBy.putIfAbsent(t.asset, () => TaxSum()).add(rev, cost);
        }
      } else {
        ty.currencies.putIfAbsent(t.asset, () => TaxSum()).add(rev, cost);
      }
      lot.q -= take;
      left -= take;
      if (lot.q <= 1e-12) l.removeAt(0);
    }
    if (left > 1e-9) ty.oversold = true; // nadwyżka bez zakupu – pominięta
  }

  for (final d in deposits) {
    if (d.status != 'closed' || d.end == null || d.end!.length < 4) continue;
    double? gross = d.interest;
    double? tax = d.tax;
    if (gross == null && d.payout != null) {
      final net = d.payout! - d.principal;
      if (net > 0) gross = net / (1 - belka);
    }
    if (gross == null || gross <= 0) continue;
    final ty = y(d.end!);
    ty.depositInterest += gross;
    ty.depositTax += tax ?? gross * belka;
  }
  return out;
}
