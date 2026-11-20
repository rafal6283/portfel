import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';
import 'package:portfel/history.dart';
import 'package:portfel/koofr_backup.dart';

/// Kontrakt wymiany (WYMIANA.md w repozytorium Rytmu Snu) z perspektywy Portfela.
void main() {
  test('czynniki-portfel: zgodne z kontraktem, jedna wartość na dzień', () {
    final now = DateTime(2026, 11, 20, 19);
    final bytes = portfelFactors([
      ValuePoint(DateTime(2026, 11, 18), 1000, 900),
      ValuePoint(DateTime(2026, 11, 19, 8), 1100, 900),
      ValuePoint(DateTime(2026, 11, 19, 20), 1200, 900), // ten sam dzień — liczy się ostatni
    ], 500, now);
    expect(sprawdzWymiane('czynniki-portfel', bytes), isEmpty);
    final days = jsonDecode(utf8.decode(bytes))['days'] as List;
    expect(days, [
      {'date': '2026-11-18', 'value': 1500},
      {'date': '2026-11-19', 'value': 1700},
    ]);
  });

  test('bez transakcji: same lokaty i gotówka z dzisiejszą datą', () {
    final bytes = portfelFactors(const [], 2500.4, DateTime(2026, 11, 20));
    expect(sprawdzWymiane('czynniki-portfel', bytes), isEmpty);
    expect(jsonDecode(utf8.decode(bytes))['days'], [
      {'date': '2026-11-20', 'value': 2500},
    ]);
    expect(jsonDecode(utf8.decode(portfelFactors(const [], 0, DateTime(2026, 11, 20))))['days'], isEmpty);
  });
}
