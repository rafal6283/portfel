// Stan aplikacji i zapis do pliku JSON w katalogu dokumentów aplikacji.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'calc.dart';
import 'models.dart';
import 'rates.dart';

class AppState extends ChangeNotifier {
  List<Tx> txs = [];
  List<Deposit> deposits = [];
  Map<String, ManualRate> manual = {};
  RatesSnapshot rates = fallbackRates;
  bool loaded = false;
  bool refreshing = false;
  String? rateError;

  File? _file;

  Future<File> _dataFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/portfel.json');
    return _file!;
  }

  Future<void> load() async {
    try {
      final f = await _dataFile();
      if (await f.exists()) {
        _apply(jsonDecode(await f.readAsString()), replace: true);
      }
    } catch (e) {
      debugPrint('load error $e');
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'app': 'portfel',
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'transactions': txs.map((t) => t.toJson()).toList(),
        'deposits': deposits.map((d) => d.toJson()).toList(),
        'manualRates': manual.map((k, v) => MapEntry(k, v.toJson())),
        'rates': rates.toJson(),
      };

  Future<void> _save() async {
    final f = await _dataFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(f.path);
  }

  /// Wczytuje dane z JSON. replace=false scala po id (import kopii).
  ImportSummary _apply(dynamic j, {required bool replace}) {
    if (j is! Map) throw const FormatException('To nie jest plik kopii Portfela');
    final rawTx = j['transactions'] ?? j['tx'];
    final rawDep = j['deposits'];
    if (rawTx is! List && rawDep is! List) throw const FormatException('W pliku nie ma transakcji ani lokat');
    final newTx = <Tx>[for (final e in (rawTx is List ? rawTx : const [])) if (e is Map) Tx.fromJson(Map<String, dynamic>.from(e))]
        .where((t) => t.qty > 0 && t.total >= 0 && t.date.length == 10)
        .toList();
    final newDep = <Deposit>[for (final e in (rawDep is List ? rawDep : const [])) if (e is Map) Deposit.fromJson(Map<String, dynamic>.from(e))]
        .where((d) => d.principal > 0)
        .toList();
    final newManual = <String, ManualRate>{};
    final m = j['manualRates'];
    if (m is Map) {
      m.forEach((k, v) {
        final r = ManualRate.fromJson(v);
        if (r != null) newManual[k.toString()] = r;
      });
    }
    final snap = j['rates'] != null ? RatesSnapshot.fromJson(j['rates']) : null;

    var added = 0, updated = 0;
    if (replace) {
      txs = newTx;
      deposits = newDep;
      manual = newManual;
      added = newTx.length + newDep.length;
    } else {
      final ti = {for (var i = 0; i < txs.length; i++) txs[i].id: i};
      for (final t in newTx) {
        if (ti.containsKey(t.id)) {
          txs[ti[t.id]!] = t;
          updated++;
        } else {
          txs.add(t);
          added++;
        }
      }
      final di = {for (var i = 0; i < deposits.length; i++) deposits[i].id: i};
      for (final d in newDep) {
        if (di.containsKey(d.id)) {
          deposits[di[d.id]!] = d;
          updated++;
        } else {
          deposits.add(d);
          added++;
        }
      }
      manual.addAll(newManual);
    }
    if (snap != null && snap.rates.isNotEmpty) {
      final cur = rates.asOf ?? '';
      if (replace || (snap.asOf ?? '').compareTo(cur) > 0) rates = snap;
    }
    return ImportSummary(added, updated, newTx.length, newDep.length);
  }

  Future<ImportSummary> importBytes(Uint8List bytes) async {
    final s = _apply(jsonDecode(utf8.decode(bytes)), replace: false);
    await _save();
    notifyListeners();
    return s;
  }

  Uint8List exportBytes() => Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(toJson())));

  // ---------- kursy ----------

  double? rateOf(String code) {
    final m = manual[code];
    final asOf = rates.asOf;
    if (m != null && (asOf == null || m.date.compareTo(asOf) >= 0)) return m.price;
    return rates.rates[code];
  }

  bool isManual(String code) {
    final m = manual[code];
    final asOf = rates.asOf;
    return m != null && (asOf == null || m.date.compareTo(asOf) >= 0);
  }

  Future<void> setManual(String code, double? price) async {
    if (price == null) {
      manual.remove(code);
    } else {
      manual[code] = ManualRate(price, todayIso());
    }
    await _save();
    notifyListeners();
  }

  /// Odświeża kursy, jeśli ostatnie pobranie jest starsze niż [maxAge] (albo zawsze, gdy force).
  Future<void> refreshRates({bool force = false, Duration maxAge = const Duration(hours: 1)}) async {
    if (refreshing) return;
    if (!force && rates.updatedAt != null) {
      final t = DateTime.tryParse(rates.updatedAt!);
      if (t != null && DateTime.now().toUtc().difference(t) < maxAge) return;
    }
    refreshing = true;
    rateError = null;
    notifyListeners();
    try {
      rates = await fetchLatestRates(rates);
      await _save();
    } catch (e) {
      rateError = 'Nie udało się pobrać kursów. Sprawdź internet i spróbuj ponownie.';
      debugPrint('rates $e');
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  // ---------- transakcje i lokaty ----------

  Future<void> upsertTx(Tx t) async {
    final i = txs.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      txs[i] = t;
    } else {
      txs.add(t);
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteTx(String id) async {
    txs.removeWhere((x) => x.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> upsertDeposit(Deposit d) async {
    final i = deposits.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      deposits[i] = d;
    } else {
      deposits.add(d);
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteDeposit(String id) async {
    deposits.removeWhere((x) => x.id == id);
    await _save();
    notifyListeners();
  }

  Portfolio get portfolio => computePortfolio(txs, rateOf);
  DepositTotals get depositSummary => depositTotals(deposits);
}

class ImportSummary {
  final int added, updated, txCount, depCount;
  const ImportSummary(this.added, this.updated, this.txCount, this.depCount);
}
