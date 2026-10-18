// Modele danych. Pola nieznane (np. "src") są zachowywane w [extra],
// żeby import → eksport nie gubił informacji.

const double ozGrams = 31.1034768;
const double belka = 0.19;

class Asset {
  final String code;
  final String name;
  final bool metal;
  const Asset(this.code, this.name, {this.metal = false});
}

const List<Asset> assets = [
  Asset('USD', 'Dolar amerykański'),
  Asset('EUR', 'Euro'),
  Asset('CHF', 'Frank szwajcarski'),
  Asset('GBP', 'Funt brytyjski'),
  Asset('XAU', 'Złoto', metal: true),
  Asset('XAG', 'Srebro', metal: true),
  Asset('NOK', 'Korona norweska'),
  Asset('SEK', 'Korona szwedzka'),
  Asset('DKK', 'Korona duńska'),
  Asset('CZK', 'Korona czeska'),
  Asset('JPY', 'Jen japoński'),
  Asset('CAD', 'Dolar kanadyjski'),
  Asset('AUD', 'Dolar australijski'),
];

Asset assetOf(String code) =>
    assets.firstWhere((a) => a.code == code, orElse: () => Asset(code, code));

bool isMetal(String code) => code == 'XAU' || code == 'XAG';

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
String? _s(dynamic v) => v?.toString();

Map<String, dynamic> _extra(Map<String, dynamic> j, Set<String> known) =>
    {for (final e in j.entries) if (!known.contains(e.key)) e.key: e.value};

class Tx {
  String id;
  String date; // yyyy-mm-dd
  String side; // buy | sell
  String asset;
  double qty; // jednostki waluty albo gramy kruszcu
  double total; // PLN bez prowizji
  double fee; // PLN
  String note;
  int createdAt;
  bool check;
  Map<String, dynamic> extra;

  Tx({
    required this.id,
    required this.date,
    required this.side,
    required this.asset,
    required this.qty,
    required this.total,
    this.fee = 0,
    this.note = '',
    int? createdAt,
    this.check = false,
    Map<String, dynamic>? extra,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        extra = extra ?? {};

  bool get isBuy => side == 'buy';
  double get unitPrice => qty > 0 ? total / qty : 0;

  static const _known = {'id', 'date', 'side', 'asset', 'qty', 'total', 'fee', 'note', 'createdAt', 'check'};

  factory Tx.fromJson(Map<String, dynamic> j) => Tx(
        id: _s(j['id']) ?? newId('t'),
        date: _s(j['date']) ?? '',
        side: _s(j['side']) == 'sell' ? 'sell' : 'buy',
        asset: _s(j['asset']) ?? 'USD',
        qty: _d(j['qty']) ?? 0,
        total: _d(j['total']) ?? 0,
        fee: _d(j['fee']) ?? 0,
        note: _s(j['note']) ?? '',
        createdAt: (j['createdAt'] is num) ? (j['createdAt'] as num).toInt() : null,
        check: j['check'] == true,
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'date': date,
        'side': side,
        'asset': asset,
        'qty': qty,
        'total': total,
        'fee': fee,
        'note': note,
        'createdAt': createdAt,
        if (check) 'check': true,
      };
}

class Deposit {
  String id;
  String bank;
  String ref;
  String? start;
  String? end;
  double principal;
  double? rate; // % r/r brutto
  String status; // open | closed | unknown
  double? payout; // wypłacono łącznie (kapitał + odsetki netto)
  double? interest; // odsetki brutto
  double? tax;
  String note;
  bool noAnn; // nie pokazuj % r/r (wiele wpłat/wypłat)
  bool check;
  bool principalGuess;
  Map<String, dynamic> extra;

  Deposit({
    required this.id,
    this.bank = '',
    this.ref = '',
    this.start,
    this.end,
    required this.principal,
    this.rate,
    this.status = 'open',
    this.payout,
    this.interest,
    this.tax,
    this.note = '',
    this.noAnn = false,
    this.check = false,
    this.principalGuess = false,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const _known = {
    'id', 'bank', 'ref', 'start', 'end', 'principal', 'rate', 'status', 'payout',
    'interest', 'tax', 'note', 'noAnn', 'check', 'principalGuess'
  };

  factory Deposit.fromJson(Map<String, dynamic> j) {
    final st = _s(j['status']);
    return Deposit(
      id: _s(j['id']) ?? newId('d'),
      bank: _s(j['bank']) ?? '',
      ref: _s(j['ref']) ?? '',
      start: _s(j['start']),
      end: _s(j['end']),
      principal: _d(j['principal']) ?? 0,
      rate: _d(j['rate']),
      status: (st == 'closed' || st == 'unknown') ? st! : 'open',
      payout: _d(j['payout']),
      interest: _d(j['interest']),
      tax: _d(j['tax']),
      note: _s(j['note']) ?? '',
      noAnn: j['noAnn'] == true,
      check: j['check'] == true,
      principalGuess: j['principalGuess'] == true,
      extra: _extra(j, _known),
    );
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'bank': bank,
        'ref': ref,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        'principal': principal,
        if (rate != null) 'rate': rate,
        'status': status,
        if (payout != null) 'payout': payout,
        if (interest != null) 'interest': interest,
        if (tax != null) 'tax': tax,
        'note': note,
        if (noAnn) 'noAnn': true,
        if (check) 'check': true,
        if (principalGuess) 'principalGuess': true,
      };
}

class ManualRate {
  final double price;
  final String date;
  const ManualRate(this.price, this.date);
  Map<String, dynamic> toJson() => {'price': price, 'date': date};
  static ManualRate? fromJson(dynamic j) {
    if (j is! Map) return null;
    final p = _d(j['price']);
    final d = _s(j['date']);
    if (p == null || p <= 0 || d == null) return null;
    return ManualRate(p, d);
  }
}

class RatesSnapshot {
  final String? asOf; // data notowania NBP
  final String? updatedAt; // ISO czas pobrania
  final String source;
  final Map<String, double> rates; // PLN za 1 jednostkę; kruszce PLN za 1 g
  final Map<String, double> prev;

  const RatesSnapshot({this.asOf, this.updatedAt, this.source = '', this.rates = const {}, this.prev = const {}});

  static Map<String, double> _map(dynamic m) {
    if (m is! Map) return {};
    final out = <String, double>{};
    m.forEach((k, v) {
      final d = _d(v);
      if (d != null && d > 0) out[k.toString()] = d;
    });
    return out;
  }

  factory RatesSnapshot.fromJson(dynamic j) {
    if (j is! Map) return const RatesSnapshot();
    return RatesSnapshot(
      asOf: _s(j['asOf']),
      updatedAt: _s(j['updatedAt']),
      source: _s(j['source']) ?? '',
      rates: _map(j['rates']),
      prev: _map(j['prev']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (asOf != null) 'asOf': asOf,
        if (updatedAt != null) 'updatedAt': updatedAt,
        'source': source,
        'rates': rates,
        'prev': prev,
      };
}

/// Kursy z 15.10.2026 – używane tylko do pierwszego pobrania.
const RatesSnapshot fallbackRates = RatesSnapshot(
  asOf: '2026-10-15',
  source: 'NBP tabela A 201/A/NBP/2026 (zapisane w aplikacji)',
  rates: {
    'USD': 3.8952, 'EUR': 4.3691, 'CHF': 4.6949, 'GBP': 5.1647, 'NOK': 0.4093,
    'SEK': 0.3906, 'DKK': 0.5845, 'CZK': 0.1794, 'JPY': 0.024678, 'CAD': 2.7435,
    'AUD': 2.6992, 'XAU': 520.0, 'XAG': 7.2523,
  },
);

int _seq = 0;
String newId(String prefix) {
  _seq = (_seq + 1) % 1000;
  return '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$_seq';
}

String todayIso([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
