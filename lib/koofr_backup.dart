import 'dart:convert';

import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'history.dart';
import 'main.dart' show app;
import 'models.dart';

/// Kopia Portfela na rodzinnym Koofr (ten sam plik JSON co „Zapisz kopię”, zaszyfrowany).
class PortfelBackup extends BackupAdapter {
  @override
  String get appId => 'portfel';
  @override
  String get appName => 'Portfel';
  @override
  String get contentNote => 'W kopii są transakcje, lokaty, gotówka, nieruchomości i ręczne kursy.';

  @override
  ExchangeAdapter get exchange => _PortfelExchange();

  @override
  Future<BackupContent> export() async => BackupContent(app.exportBytes());

  @override
  Future<void> import(RestoredBackup r, void Function(String step) progress) async {
    try {
      await app.replaceFromBytes(r.data);
    } on FormatException catch (e) {
      throw KoofrException(e.message);
    }
  }
}

/// Wartość majątku dzień po dniu (90 dni) – do podsumowania tygodnia w Dobie.
class _PortfelExchange extends ExchangeAdapter {
  @override
  String get publishes => 'Wartość majątku dzień po dniu (bez szczegółów transakcji) – do podsumowania tygodnia w Dobie';

  @override
  Future<Map<String, List<int>?>> export() async {
    final hist = await RateHistoryStore.load();
    final now = DateTime.now();
    final other = app.depositSummary.value + app.cashSummary.value + app.propertySummary.value;
    final series = valueSeries(app.txs, hist, now.subtract(const Duration(days: 90)), now, app.rateOf);
    return {'czynniki-portfel': portfelFactors(series, other, now)};
  }
}

/// Plik „czynniki-portfel” (czynniki-dnia v1, kontrakt w WYMIANA.md Rytmu Snu): jedna wartość na dzień.
List<int> portfelFactors(List<ValuePoint> series, double other, DateTime now) {
  final byDay = <String, int>{}; // przy kilku punktach z jednego dnia liczy się ostatni
  for (final p in series) {
    byDay[todayIso(p.day)] = (p.value + other).round();
  }
  if (byDay.isEmpty && other > 0) byDay[todayIso(now)] = other.round();
  final keys = byDay.keys.toList()..sort();
  return utf8.encode(jsonEncode({
    'format': 'czynniki-dnia',
    'version': 1,
    'source': 'portfel',
    'exported_at': now.millisecondsSinceEpoch,
    'days': [for (final k in keys) {'date': k, 'value': byDay[k]}],
  }));
}
