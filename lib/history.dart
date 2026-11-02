// Historia wartości walut i kruszców: kursy archiwalne NBP (waluty – tabela A, złoto – ceny NBP),
// zapisane w pamięci podręcznej. Srebro nie ma archiwum NBP – przyjmujemy kurs bieżący.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'calc.dart';
import 'models.dart';

/// data (RRRR-MM-DD) → kod → kurs PLN (kruszce za 1 g)
typedef RateHistory = Map<String, Map<String, double>>;

class ValuePoint {
  final DateTime day;
  final double value, cost;
  const ValuePoint(this.day, this.value, this.cost);
}

/// Wartość i koszt otwartych pozycji dzień po dniu (kurs z ostatniego notowania przed dniem).
List<ValuePoint> valueSeries(List<Tx> txs, RateHistory hist, DateTime from, DateTime to, double? Function(String) currentRate) {
  if (txs.isEmpty) return const [];
  final sorted = [...txs]..sort(compareTx);
  final dates = hist.keys.toList()..sort();
  final last = <String, double>{};
  var di = 0;
  final out = <ValuePoint>[];
  for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final iso = todayIso(d);
    while (di < dates.length && dates[di].compareTo(iso) <= 0) {
      last.addAll(hist[dates[di]]!);
      di++;
    }
    final upTo = [for (final t in sorted) if (t.date.compareTo(iso) <= 0) t];
    if (upTo.isEmpty) continue;
    final p = computePortfolio(upTo, (c) => last[c] ?? currentRate(c));
    out.add(ValuePoint(d, p.value, p.cost));
  }
  return out;
}

const _nbp = 'https://api.nbp.pl/api';

Future<List<dynamic>> _get(String url) async {
  final r = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
  if (r.statusCode == 404) return const []; // brak notowań w zakresie
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes));
  return j is Map ? (j['rates'] as List? ?? const []) : (j as List);
}

class RateHistoryStore {
  static Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/kursy_historia.json');

  static Future<RateHistory> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString()) as Map;
      return {
        for (final e in (j['rates'] as Map).entries)
          '${e.key}': {for (final r in (e.value as Map).entries) '${r.key}': (r.value as num).toDouble()}
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(RateHistory h) async =>
      (await _file()).writeAsString(jsonEncode({'rates': h}));

  /// Uzupełnia brakujące kursy od [from] do dziś dla [codes]. Zapytania po ≤ 360 dni.
  static Future<RateHistory> update(Set<String> codes, DateTime from) async {
    final h = await load();
    final today = DateTime.now();
    for (final code in codes) {
      if (code == 'XAG') continue;
      // od ostatniego zapisanego notowania tego kodu
      final have = [for (final e in h.entries) if (e.value.containsKey(code)) e.key]..sort();
      var start = have.isEmpty ? from : DateTime.parse(have.last).add(const Duration(days: 1));
      while (start.isBefore(today)) {
        final end = DateTime.fromMillisecondsSinceEpoch(min(today.millisecondsSinceEpoch, start.add(const Duration(days: 360)).millisecondsSinceEpoch));
        final a = todayIso(start), b = todayIso(end);
        try {
          final rows = code == 'XAU'
              ? await _get('$_nbp/cenyzlota/$a/$b/?format=json')
              : await _get('$_nbp/exchangerates/rates/A/$code/$a/$b/?format=json');
          for (final r in rows) {
            final d = (r['effectiveDate'] ?? r['data'])?.toString();
            final v = (r['mid'] ?? r['cena']) as num?;
            if (d != null && v != null) (h[d] ??= {})[code] = v.toDouble();
          }
        } catch (_) {
          break; // bez internetu – zostaje to, co jest
        }
        start = end.add(const Duration(days: 1));
      }
    }
    await _save(h);
    return h;
  }
}
