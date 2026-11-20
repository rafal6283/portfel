import 'dart:math';

import 'models.dart';

/// Rodzaj obligacji oszczędnościowych Skarbu Państwa.
class BondType {
  final String code, name;
  final int months; // czas trwania
  final bool capitalized; // odsetki doliczane co rok (EDO, ROD, ROS, TOS) czy wypłacane (COI, DOR, ROR, OTS)
  final bool inflation; // od drugiego roku inflacja GUS + marża
  final double fee; // opłata za wcześniejszy wykup, zł za obligację (nie więcej niż narosłe odsetki)

  /// Oferta z listopada 2026 (pkobp.pl, obligacjeskarbowe.pl) — tylko podpowiedź w formularzu.
  final double? offerRate, offerMargin;

  const BondType(this.code, this.name, this.months, this.capitalized, this.inflation, this.fee,
      [this.offerRate, this.offerMargin]);

  int get years => (months / 12).ceil();
}

const bondTypes = <BondType>[
  BondType('OTS', '3-miesięczne', 3, false, false, 0, 2.00),
  BondType('ROR', 'roczne (stopa NBP)', 12, false, false, 0.5),
  BondType('DOR', '2-letnie (stopa NBP)', 24, false, false, 0.7, 4.15, 0.15),
  BondType('TOS', '3-letnie stałe', 36, true, false, 1, 4.40),
  BondType('COI', '4-letnie (inflacja)', 48, false, true, 2, 4.75, 1.50),
  BondType('ROS', '6-letnie rodzinne', 72, true, true, 2, 5.00, 2.00),
  BondType('EDO', '10-letnie emerytalne', 120, true, true, 3, 5.35, 2.00),
  BondType('ROD', '12-letnie rodzinne', 144, true, true, 3, 5.60, 2.50),
];

/// Rodzaj z nazwy serii, np. „EDO1136” → EDO.
BondType? bondTypeOf(String series) {
  final s = series.trim().toUpperCase();
  for (final t in bondTypes) {
    if (s.startsWith(t.code)) return t;
  }
  return null;
}

/// Zakup obligacji jednej serii.
class Bond {
  String id;
  String series; // np. EDO1136
  String date; // dzień zakupu (yyyy-mm-dd)
  int count; // liczba obligacji po 100 zł
  List<double> rates; // oprocentowanie kolejnych okresów (%), [0] = pierwszy rok
  double? margin; // marża (%) dla obligacji indeksowanych
  String? redeemed; // data wykupu (wcześniejszego lub w terminie)
  String note;
  Map<String, dynamic> extra;

  Bond({
    required this.id,
    required this.series,
    required this.date,
    required this.count,
    List<double>? rates,
    this.margin,
    this.redeemed,
    this.note = '',
    Map<String, dynamic>? extra,
  })  : rates = rates ?? [],
        extra = extra ?? {};

  BondType? get type => bondTypeOf(series);
  double get principal => count * 100.0;

  static const _known = {'id', 'series', 'date', 'count', 'rates', 'margin', 'redeemed', 'note'};

  factory Bond.fromJson(Map<String, dynamic> j) => Bond(
        id: '${j['id'] ?? newId('b')}',
        series: '${j['series'] ?? ''}',
        date: '${j['date'] ?? ''}',
        count: (j['count'] as num?)?.toInt() ?? 0,
        rates: [for (final r in (j['rates'] as List? ?? const [])) if (r is num) r.toDouble()],
        margin: (j['margin'] as num?)?.toDouble(),
        redeemed: j['redeemed'] as String?,
        note: '${j['note'] ?? ''}',
        extra: {for (final e in j.entries) if (!_known.contains(e.key)) e.key: e.value},
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'series': series,
        'date': date,
        'count': count,
        'rates': rates,
        if (margin != null) 'margin': margin,
        if (redeemed != null) 'redeemed': redeemed,
        'note': note,
      };
}

/// Wycena obligacji na dany dzień (wszystko w zł, za cały zakup).
class BondCalc {
  final double principal;
  final double grossValue; // wartość z narosłymi odsetkami (bez opłaty i podatku)
  final double paidOut; // odsetki już wypłacone (COI, DOR, ROR) — netto, po podatku
  final double fee; // opłata, gdyby wykupić dziś (0 w terminie)
  final double tax; // podatek od zysku przy wykupie dziś
  final double netIfRedeemed; // ile wpłynie na konto przy wykupie dziś
  final int period; // bieżący okres odsetkowy (1 = pierwszy rok)
  final double currentRate; // oprocentowanie bieżącego okresu (%)
  final bool estimated; // bieżąca lub wcześniejsza stopa oszacowana z inflacji (nie wpisana)
  final bool matured;
  final String? maturity; // dzień wykupu w terminie

  const BondCalc({
    required this.principal,
    required this.grossValue,
    required this.paidOut,
    required this.fee,
    required this.tax,
    required this.netIfRedeemed,
    required this.period,
    required this.currentRate,
    required this.estimated,
    required this.matured,
    required this.maturity,
  });

  /// Zysk netto (po podatku i ewentualnej opłacie), z odsetkami już wypłaconymi.
  double get net => netIfRedeemed + paidOut - principal;
}

/// Daty jako UTC — bez przesunięć przy zmianie czasu (liczymy pełne dni).
DateTime? _date(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}
String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime _addMonths(DateTime d, int m) {
  final y = d.year + (d.month - 1 + m) ~/ 12, mo = (d.month - 1 + m) % 12 + 1;
  return DateTime.utc(y, mo, min(d.day, DateTime.utc(y, mo + 1, 0).day));
}

/// Stopa okresu [i] (0 = pierwszy): wpisana, a gdy jej brak — inflacja (GUS, r/r, ogłoszona w miesiącu przed
/// początkiem okresu, czyli za miesiąc dwa wcześniej) + marża; bez inflacji — ostatnia znana stopa.
(double, bool) bondRate(Bond b, int i, DateTime periodStart, double? Function(String yyyyMm)? inflationYoY) {
  if (i < b.rates.length) return (b.rates[i], false);
  final t = b.type;
  if (t != null && t.inflation && i > 0) {
    final m = _addMonths(DateTime(periodStart.year, periodStart.month), -2);
    final inf = inflationYoY?.call('${m.year}-${m.month.toString().padLeft(2, '0')}');
    if (inf != null) return (max(0.0, inf) + (b.margin ?? t.offerMargin ?? 0), true);
  }
  return (b.rates.isNotEmpty ? b.rates.last : (t?.offerRate ?? 0), true);
}

/// Wycena zakupu [b] na dzień [today] (domyślnie dziś albo dzień wykupu).
BondCalc bondCalc(Bond b, {String? today, double? Function(String yyyyMm)? inflationYoY}) {
  final t = b.type;
  final start = _date(b.date);
  final p = b.principal;
  if (t == null || start == null || b.count <= 0) {
    return BondCalc(principal: p, grossValue: p, paidOut: 0, fee: 0, tax: 0, netIfRedeemed: p, period: 1,
        currentRate: 0, estimated: false, matured: false, maturity: null);
  }
  final end = _addMonths(start, t.months);
  var at = _date(b.redeemed ?? today ?? _iso(DateTime.now()))!;
  if (at.isAfter(end)) at = end;
  final matured = !at.isBefore(end);
  // okresy odsetkowe: rok (OTS: 3 miesiące, ROR/DOR: miesiąc — liczone uproszczenie: jedna stopa na rok)
  final periodMonths = t.months < 12 ? t.months : 12;
  var base = p; // kapitał z doliczonymi odsetkami (obligacje kapitalizowane)
  var paid = 0.0; // odsetki wypłacone brutto
  var estimated = false;
  var i = 0;
  var ps = start;
  var rate = 0.0;
  var accrued = 0.0;
  while (true) {
    final pe = _addMonths(start, (i + 1) * periodMonths);
    final (r, est) = bondRate(b, i, ps, inflationYoY);
    rate = r;
    if (est) estimated = true;
    if (!at.isBefore(pe)) {
      final interest = (base * r / 100 * 100).round() / 100; // do grosza
      if (t.capitalized) {
        base += interest;
      } else {
        paid += interest;
      }
      i++;
      ps = pe;
      if (!ps.isBefore(end)) break;
      continue;
    }
    // bieżący okres: odsetki narosłe proporcjonalnie do dni
    final days = at.difference(ps).inDays, len = pe.difference(ps).inDays;
    accrued = (base * r / 100 * days / len * 100).floor() / 100;
    break;
  }
  final gross = base + accrued;
  // opłata nie większa niż należne odsetki (przy kapitalizacji — wszystkie narosłe od zakupu)
  final fee = matured ? 0.0 : min(t.fee * b.count, t.capitalized ? gross - p : accrued);
  // podatek Belki 19% od odsetek (przy kapitalizacji — od całego zysku przy wykupie)
  final taxable = (t.capitalized ? gross - p : accrued) - fee;
  final tax = taxable > 0 ? (taxable * 0.19).roundToDouble() : 0.0; // zaokrąglenie do pełnych złotych
  final paidNet = t.capitalized ? 0.0 : paid - (paid * 0.19);
  return BondCalc(
    principal: p,
    grossValue: gross,
    paidOut: paidNet,
    fee: fee,
    tax: tax,
    netIfRedeemed: gross - fee - tax,
    period: i + 1,
    currentRate: rate,
    estimated: estimated,
    matured: matured,
    maturity: _iso(end),
  );
}

class BondTotals {
  final double principal, value, net;
  final int open;
  final bool estimated;
  const BondTotals(this.principal, this.value, this.net, this.open, this.estimated);
}

/// Podsumowanie obligacji jeszcze niewykupionych: wartość netto przy wykupie dziś.
BondTotals bondTotals(List<Bond> bonds, {String? today, double? Function(String)? inflationYoY}) {
  var principal = 0.0, value = 0.0, net = 0.0, open = 0;
  var est = false;
  for (final b in bonds) {
    if (b.redeemed != null) continue;
    final c = bondCalc(b, today: today, inflationYoY: inflationYoY);
    principal += c.principal;
    value += c.netIfRedeemed;
    net += c.net;
    open++;
    est |= c.estimated;
  }
  return BondTotals(principal, value, net, open, est);
}
