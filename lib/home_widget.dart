// Widżet na ekranie głównym (Android): wartość majątku, zmiana od poprzedniego notowania, wynik łączny.
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import 'store.dart';
import 'ui/format.dart';

Future<void> updateHomeWidget(AppState app) async {
  if (!Platform.isAndroid) return;
  try {
    final p = app.portfolio;
    final d = app.depositSummary, c = app.cashSummary, re = app.propertySummary;
    final total = p.value + d.value + c.value + re.value;
    // zmiana wartości walut i kruszców od poprzedniego notowania
    var prevValue = 0.0;
    for (final r in p.rows) {
      final prev = app.rates.prev[r.code] ?? app.rateOf(r.code);
      if (prev != null) prevValue += r.qty * prev;
    }
    final change = p.value - prevValue;
    final result = p.unrealized + p.realized + d.net + re.net;
    await HomeWidget.saveWidgetData<String>('w_value', pln(total));
    await HomeWidget.saveWidgetData<String>('w_change', '${change >= 0 ? '+' : '−'}${pln(change.abs())} od poprz. notowania');
    await HomeWidget.saveWidgetData<String>('w_result', 'wynik łącznie ${signedPln(result)}');
    await HomeWidget.saveWidgetData<String>('w_date', app.rates.asOf != null ? 'kursy z ${dateFmt(app.rates.asOf)}' : '');
    await HomeWidget.updateWidget(androidName: 'PortfelWidget');
  } catch (_) {}
}
