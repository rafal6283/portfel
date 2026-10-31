// Alerty cenowe i przypomnienia o końcu lokat (logika bez Fluttera – testowana w CI).
import 'models.dart';

class PriceAlert {
  String id;
  String asset; // kod waluty / XAU / XAG
  bool above; // true: kurs ≥ price, false: kurs ≤ price
  double price; // PLN za 1 jednostkę (kruszce: za 1 g)
  bool active;
  String? firedAt; // ISO – kiedy alert zadziałał
  double? firedRate;

  PriceAlert({required this.id, required this.asset, required this.above, required this.price, this.active = true, this.firedAt, this.firedRate});

  factory PriceAlert.fromJson(Map<String, dynamic> j) => PriceAlert(
        id: j['id']?.toString() ?? newId('a'),
        asset: j['asset']?.toString() ?? 'USD',
        above: j['above'] != false,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        active: j['active'] != false,
        firedAt: j['firedAt']?.toString(),
        firedRate: (j['firedRate'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'asset': asset,
        'above': above,
        'price': price,
        'active': active,
        if (firedAt != null) 'firedAt': firedAt,
        if (firedRate != null) 'firedRate': firedRate,
      };

  bool hit(double rate) => above ? rate >= price : rate <= price;
}

/// Alerty, które właśnie zadziałały (aktywne i spełnione); oznacza je jako wykonane (jednorazowe).
List<PriceAlert> fireAlerts(List<PriceAlert> alerts, double? Function(String code) rateOf, {DateTime? now}) {
  final fired = <PriceAlert>[];
  for (final a in alerts) {
    if (!a.active || a.price <= 0) continue;
    final r = rateOf(a.asset);
    if (r == null || !a.hit(r)) continue;
    a.active = false;
    a.firedAt = (now ?? DateTime.now()).toIso8601String();
    a.firedRate = r;
    fired.add(a);
  }
  return fired;
}

/// Przypomnienie o lokacie: (kiedy, treść). Lokaty trwające z datą końca w przyszłości.
List<(DateTime, String, String)> depositReminders(List<Deposit> deposits, {int daysBefore = 3, int hour = 9, DateTime? now}) {
  final t = now ?? DateTime.now();
  final out = <(DateTime, String, String)>[];
  for (final d in deposits) {
    if (d.status != 'open' || d.end == null) continue;
    final end = DateTime.tryParse(d.end!);
    if (end == null) continue;
    final name = [if (d.bank.isNotEmpty) d.bank, if (d.ref.isNotEmpty) d.ref].join(' · ');
    final what = name.isEmpty ? 'Lokata' : 'Lokata $name';
    final before = DateTime(end.year, end.month, end.day, hour).subtract(Duration(days: daysBefore));
    if (daysBefore > 0 && before.isAfter(t)) {
      out.add((before, 'Za $daysBefore ${daysBefore == 1 ? 'dzień' : 'dni'} kończy się lokata', '$what – zdecyduj, czy odnowić, czy przenieść środki.'));
    }
    final onDay = DateTime(end.year, end.month, end.day, hour);
    if (onDay.isAfter(t)) out.add((onDay, 'Dziś kończy się lokata', '$what – sprawdź wypłatę i wpisz wynik w Portfelu.'));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}
