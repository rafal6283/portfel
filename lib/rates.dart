// Pobieranie kursów: NBP (tabela A, ceny złota) i srebro ze spotu USD (gold-api.com).
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const _nbp = 'https://api.nbp.pl/api';
const _silverUrl = 'https://api.gold-api.com/price/XAG';
const _timeout = Duration(seconds: 15);

Future<dynamic> _getJson(String url) async {
  final r = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(_timeout);
  if (r.statusCode != 200) throw RateError('HTTP ${r.statusCode} – $url');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

class RateError implements Exception {
  final String message;
  RateError(this.message);
  @override
  String toString() => message;
}

double? _num(dynamic v) => v is num ? v.toDouble() : null;

/// Pobiera bieżące kursy. Gdy srebro jest niedostępne, zostawia poprzednią wartość.
Future<RatesSnapshot> fetchLatestRates(RatesSnapshot previous) async {
  final tables = await _getJson('$_nbp/exchangerates/tables/A/last/2/?format=json') as List;
  if (tables.isEmpty) throw RateError('NBP nie zwrócił tabeli kursów');
  Map<String, double> parse(dynamic t) {
    final out = <String, double>{};
    for (final r in (t['rates'] as List)) {
      final code = r['code']?.toString();
      final mid = _num(r['mid']);
      if (code != null && mid != null && assets.any((a) => a.code == code)) out[code] = mid;
    }
    return out;
  }

  final cur = tables.last;
  final rates = parse(cur);
  final prev = tables.length > 1 ? parse(tables.first) : <String, double>{};
  final asOf = cur['effectiveDate']?.toString();
  final tableNo = cur['no']?.toString() ?? '';

  // złoto: PLN za 1 g
  try {
    final gold = await _getJson('$_nbp/cenyzlota/last/2/?format=json') as List;
    if (gold.isNotEmpty) {
      final g = _num(gold.last['cena']);
      if (g != null) rates['XAU'] = g;
      if (gold.length > 1) {
        final gp = _num(gold.first['cena']);
        if (gp != null) prev['XAU'] = gp;
      }
    }
  } catch (_) {
    final old = previous.rates['XAU'];
    if (old != null) rates['XAU'] = old;
  }

  // srebro: spot USD/oz × USD z NBP / 31,1035
  String silverNote = '';
  try {
    final s = await _getJson(_silverUrl);
    final usdOz = _num(s['price']);
    final usd = rates['USD'];
    if (usdOz != null && usd != null) {
      final pln = double.parse((usdOz * usd / ozGrams).toStringAsFixed(4));
      final old = previous.rates['XAG'];
      if (old != null && (old - pln).abs() > 1e-6) {
        prev['XAG'] = old;
      } else if (previous.prev['XAG'] != null) {
        prev['XAG'] = previous.prev['XAG']!;
      }
      rates['XAG'] = pln;
      silverNote = '; srebro: spot ${usdOz.toStringAsFixed(2)} USD/oz × kurs NBP';
    }
  } catch (_) {
    final old = previous.rates['XAG'];
    if (old != null) rates['XAG'] = old;
    silverNote = '; srebro: ostatnia znana cena (brak połączenia)';
  }

  return RatesSnapshot(
    asOf: asOf,
    updatedAt: DateTime.now().toUtc().toIso8601String(),
    source: 'NBP tabela A $tableNo, NBP ceny złota$silverNote',
    rates: rates,
    prev: prev,
  );
}

String _minusDays(String iso, int n) {
  final d = DateTime.parse('${iso}T12:00:00Z').subtract(Duration(days: n));
  return todayIso(d);
}

class HistRate {
  final double value;
  final String date;
  const HistRate(this.value, this.date);
}

/// Kurs średni NBP z dnia transakcji (albo ostatni wcześniejszy dzień roboczy).
/// Dla złota PLN za 1 g. Srebro – brak notowań NBP (null).
Future<HistRate?> nbpRateOn(String code, String date) async {
  if (code == 'XAG') return null;
  final from = _minusDays(date, 7);
  try {
    if (code == 'XAU') {
      final list = await _getJson('$_nbp/cenyzlota/$from/$date/?format=json') as List;
      if (list.isEmpty) return null;
      final v = _num(list.last['cena']);
      return v == null ? null : HistRate(v, list.last['data'].toString());
    }
    final j = await _getJson('$_nbp/exchangerates/rates/A/$code/$from/$date/?format=json');
    final rs = j['rates'] as List;
    if (rs.isEmpty) return null;
    final v = _num(rs.last['mid']);
    return v == null ? null : HistRate(v, rs.last['effectiveDate'].toString());
  } catch (_) {
    return null;
  }
}
