// Obliczenia: FIFO dla walut i kruszców, wynik lokat. Czysty Dart (testowany w CI).
import 'models.dart';

class PositionRow {
  final String code;
  final double qty;
  final double cost; // koszt otwartej części (z prowizjami)
  final double? value; // wartość po bieżącym kursie
  final double realized;
  final double fees;
  final bool oversold;
  const PositionRow({
    required this.code,
    required this.qty,
    required this.cost,
    required this.value,
    required this.realized,
    required this.fees,
    required this.oversold,
  });
  bool get closed => qty <= 1e-9;
  double get avg => qty > 1e-12 ? cost / qty : 0;
  double? get unrealized => value == null ? null : value! - cost;
}

class TxResult {
  final double gain;
  final bool oversold;
  const TxResult(this.gain, this.oversold);
}

class Portfolio {
  final List<PositionRow> rows;
  final Map<String, TxResult> sells; // wynik każdej sprzedaży
  final double value;
  final double cost;
  final double unrealized;
  final double realized;
  final double fees;
  const Portfolio(this.rows, this.sells, this.value, this.cost, this.unrealized, this.realized, this.fees);
}

class _Lot {
  double q;
  final double unit;
  _Lot(this.q, this.unit);
}

int compareTx(Tx a, Tx b) {
  final c = a.date.compareTo(b.date);
  return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
}

Portfolio computePortfolio(List<Tx> txs, double? Function(String code) rateOf) {
  final sorted = [...txs]..sort(compareTx);
  final lots = <String, List<_Lot>>{};
  final realized = <String, double>{};
  final fees = <String, double>{};
  final over = <String, bool>{};
  final sells = <String, TxResult>{};

  for (final t in sorted) {
    if (t.qty <= 0) continue;
    final l = lots.putIfAbsent(t.asset, () => []);
    fees[t.asset] = (fees[t.asset] ?? 0) + t.fee;
    if (t.isBuy) {
      l.add(_Lot(t.qty, (t.total + t.fee) / t.qty));
    } else {
      var left = t.qty;
      var cost = 0.0;
      while (left > 1e-12 && l.isNotEmpty) {
        final lot = l.first;
        final take = lot.q < left ? lot.q : left;
        cost += take * lot.unit;
        lot.q -= take;
        left -= take;
        if (lot.q <= 1e-12) l.removeAt(0);
      }
      final isOver = left > 1e-9;
      if (isOver) over[t.asset] = true;
      // nadwyżka sprzedaży bez pokrycia nie liczy się jako zysk
      final gain = (t.total - t.fee) - cost - (isOver ? left * (t.total / t.qty) : 0);
      realized[t.asset] = (realized[t.asset] ?? 0) + gain;
      sells[t.id] = TxResult(gain, isOver);
    }
  }

  final rows = <PositionRow>[];
  var tv = 0.0, tc = 0.0, tu = 0.0, tr = 0.0, tf = 0.0;
  for (final code in lots.keys) {
    final l = lots[code]!;
    final qty = l.fold<double>(0, (s, x) => s + x.q);
    final cost = l.fold<double>(0, (s, x) => s + x.q * x.unit);
    final r = rateOf(code);
    final value = r == null ? null : qty * r;
    final row = PositionRow(
      code: code,
      qty: qty,
      cost: cost,
      value: value,
      realized: realized[code] ?? 0,
      fees: fees[code] ?? 0,
      oversold: over[code] ?? false,
    );
    rows.add(row);
    tv += value ?? 0;
    tc += cost;
    tu += row.unrealized ?? 0;
    tr += row.realized;
    tf += row.fees;
  }
  rows.sort((a, b) {
    final c = (b.value ?? 0).compareTo(a.value ?? 0);
    return c != 0 ? c : b.realized.compareTo(a.realized);
  });
  return Portfolio(rows, sells, tv, tc, tu, tr, tf);
}

// ---------- lokaty ----------

DateTime _day(String iso) => DateTime.parse('${iso}T12:00:00Z');
int daysBetween(String a, String b) => (_day(b).difference(_day(a)).inHours / 24).round();

class DepositCalc {
  final double? net; // wynik netto (null = nieznany)
  final double value; // bieżąca wartość (tylko trwające)
  final double? annual; // netto r/r jako ułamek
  final int? days;
  final double? atMaturity; // odsetki netto na koniec (trwająca, z terminem)
  final bool matured;
  const DepositCalc({this.net, this.value = 0, this.annual, this.days, this.atMaturity, this.matured = false});
}

DepositCalc depositCalc(Deposit d, {String? today}) {
  final now = today ?? todayIso();
  final p = d.principal;
  if (d.status == 'closed') {
    double? net;
    if (d.payout != null) {
      net = d.payout! - p;
    } else if (d.interest != null) {
      net = d.interest! - (d.tax ?? d.interest! * belka);
    }
    final n = (d.start != null && d.end != null) ? daysBetween(d.start!, d.end!) : null;
    final ann = (net != null && n != null && n > 0 && p > 0 && !d.noAnn) ? net / p * 365 / n : null;
    return DepositCalc(net: net, annual: ann, days: n);
  }
  if (d.status == 'open') {
    final until = (d.end != null && d.end!.compareTo(now) < 0) ? d.end! : now;
    final raw = d.start != null ? daysBetween(d.start!, until) : 0;
    final int n = raw < 0 ? 0 : raw;
    final r = d.rate;
    final net = r != null ? p * r / 100 * n / 365 * (1 - belka) : 0.0;
    final full = (r != null && d.start != null && d.end != null)
        ? p * r / 100 * daysBetween(d.start!, d.end!) / 365 * (1 - belka)
        : null;
    return DepositCalc(
      net: net,
      value: p + net,
      annual: r != null ? r / 100 * (1 - belka) : null,
      days: n,
      atMaturity: full,
      matured: d.end != null && d.end!.compareTo(now) <= 0,
    );
  }
  return const DepositCalc();
}

class DepositTotals {
  final double net, value, principalOpen;
  final int open, closed, unknown;
  const DepositTotals(this.net, this.value, this.principalOpen, this.open, this.closed, this.unknown);
}

DepositTotals depositTotals(List<Deposit> ds, {String? today}) {
  var net = 0.0, value = 0.0, po = 0.0;
  var o = 0, c = 0, u = 0;
  for (final d in ds) {
    final r = depositCalc(d, today: today);
    net += r.net ?? 0;
    value += r.value;
    if (d.status == 'open') {
      o++;
      po += d.principal;
    } else if (d.status == 'closed') {
      c++;
    } else {
      u++;
    }
  }
  return DepositTotals(net, value, po, o, c, u);
}

// ---------- gotówka i nieruchomości ----------

/// Wartość gotówki w PLN (null, gdy brak kursu waluty).
double? cashValue(CashEntry c, double? Function(String code) rateOf) {
  if (c.currency == 'PLN') return c.amount;
  final r = rateOf(c.currency);
  return r == null ? null : c.amount * r;
}

class CashTotals {
  final double value;
  final bool missingRate;
  final Map<String, double> byCurrency;
  const CashTotals(this.value, this.missingRate, this.byCurrency);
}

CashTotals cashTotals(List<CashEntry> cs, double? Function(String code) rateOf) {
  var v = 0.0;
  var missing = false;
  final by = <String, double>{};
  for (final c in cs) {
    by[c.currency] = (by[c.currency] ?? 0) + c.amount;
    final x = cashValue(c, rateOf);
    if (x == null) {
      missing = true;
    } else {
      v += x;
    }
  }
  return CashTotals(v, missing, by);
}

class PropertyCalc {
  final double cost; // cena zakupu + koszty
  final double value; // wartość dziś (0 po sprzedaży)
  final double change; // zmiana wartości: niezrealizowana albo zrealizowana przy sprzedaży
  final double net; // zmiana wartości + najem
  final double? annual; // wynik r/r od kosztu
  const PropertyCalc(this.cost, this.value, this.change, this.net, this.annual);
}

PropertyCalc propertyCalc(Property p, {String? today}) {
  final cost = p.buyPrice + p.buyCosts;
  final now = today ?? todayIso();
  double value, change;
  String? until;
  if (p.sold) {
    value = 0;
    change = (p.sellPrice ?? 0) - (p.sellCosts ?? 0) - cost;
    until = p.sellDate;
  } else {
    value = p.value ?? cost;
    change = value - cost;
    until = now;
  }
  final net = change + p.income;
  double? annual;
  if (p.buyDate != null && until != null && cost > 0) {
    final n = daysBetween(p.buyDate!, until);
    if (n >= 30) annual = net / cost * 365 / n;
  }
  return PropertyCalc(cost, value, change, net, annual);
}

class PropertyTotals {
  final double value, net, cost;
  final int owned, sold;
  const PropertyTotals(this.value, this.net, this.cost, this.owned, this.sold);
}

PropertyTotals propertyTotals(List<Property> ps) {
  var v = 0.0, n = 0.0, c = 0.0;
  var o = 0, s = 0;
  for (final p in ps) {
    final r = propertyCalc(p);
    v += r.value;
    n += r.net;
    if (p.sold) {
      s++;
    } else {
      o++;
      c += r.cost;
    }
  }
  return PropertyTotals(v, n, c, o, s);
}
