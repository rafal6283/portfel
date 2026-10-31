import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../tax.dart';
import 'format.dart';

/// Zestawienie roczne: wynik sprzedaży walut i kruszców (FIFO) oraz odsetki z lokat – pomoc przy zeznaniu.
class TaxScreen extends StatefulWidget {
  const TaxScreen({super.key});
  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final years = taxYears(app.txs, app.deposits);
    final keys = years.keys.toList()..sort((a, b) => b.compareTo(a));
    final prev = DateTime.now().year - 1;
    final sel = _year ?? (keys.contains(prev) ? prev : (keys.isEmpty ? null : keys.first));
    final y = sel == null ? null : years[sel];
    final small = TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5);

    Widget row(String label, double v, {bool bold = false, bool signed = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)),
            Text(signed ? signedPln(v) : pln(v),
                style: TextStyle(fontFeatures: tabular, fontWeight: bold ? FontWeight.w700 : null, color: signed && v < -0.005 ? cs.error : null)),
          ]),
        );

    Widget sum(TaxSum s) => Column(children: [
          row('Przychód (sprzedaż)', s.revenue),
          row('Koszty (zakup FIFO + prowizje)', s.cost),
          row(s.income >= 0 ? 'Dochód' : 'Strata', s.income, bold: true, signed: true),
        ]);

    Widget card(String title, List<Widget> body) => Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ...body,
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Zestawienie roczne')),
      body: y == null
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Brak sprzedaży i zakończonych lokat.')))
          : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(spacing: 8, children: [
                  for (final k in keys) ChoiceChip(label: Text('$k'), selected: k == sel, onSelected: (_) => setState(() => _year = k)),
                ]),
              ),
              if (y.oversold)
                card('Uwaga', [Text('W tym roku jest sprzedaż bez pokrycia w zapisanych zakupach – ta część została pominięta. Uzupełnij historię zakupów.', style: small)]),
              if (y.currencies.isNotEmpty)
                card('Waluty', [
                  for (final e in y.currencies.entries) ...[
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(assetOf(e.key).name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    sum(e.value),
                  ],
                  if (y.currencies.length > 1) ...[const Divider(), Text('Razem', style: const TextStyle(fontWeight: FontWeight.w600)), sum(y.currencyTotal)],
                  const SizedBox(height: 6),
                  Text('Sposób opodatkowania zysku ze sprzedaży walut przez osobę prywatną bywa różnie interpretowany – '
                      'kwoty pomogą przy zeznaniu, a formularz i stawkę warto potwierdzić z księgowym lub w KIS.', style: small),
                ]),
              if (y.metalsTaxable.revenue > 0)
                card('Kruszce sprzedane przed upływem pół roku', [
                  sum(y.metalsTaxable),
                  const SizedBox(height: 6),
                  Text('Sprzedaż złota i srebra (rzeczy ruchomych) przed upływem pół roku od końca miesiąca zakupu: '
                      'dochód wykazuje się w PIT-36 (skala podatkowa); strata nie zmniejsza innych dochodów.', style: small),
                ]),
              if (y.metalsExempt.revenue > 0)
                card('Kruszce – sprzedaż wolna od podatku', [
                  sum(y.metalsExempt),
                  const SizedBox(height: 6),
                  Text('Sprzedane po upływie pół roku od końca miesiąca zakupu – nie wykazuje się w zeznaniu.', style: small),
                ]),
              if (y.depositInterest > 0)
                card('Lokaty zakończone w roku', [
                  row('Odsetki brutto', y.depositInterest),
                  row('Podatek Belki (pobrany przez bank)', y.depositTax),
                  const SizedBox(height: 6),
                  Text('Bank pobiera podatek sam – odsetek z lokat nie wpisuje się do zeznania.', style: small),
                ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('Wyliczenie metodą FIFO z Twoich transakcji. Nie jest poradą podatkową – przed złożeniem zeznania sprawdź kwoty z dokumentami.', style: small),
              ),
            ]),
    );
  }
}
