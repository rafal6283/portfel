import 'package:flutter/material.dart';

import '../calc.dart';
import '../main.dart';
import '../models.dart';
import 'cash_form.dart';
import 'format.dart';
import 'property_form.dart';

Future<void> addAssetSheet(BuildContext context) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Gotówka'),
          subtitle: const Text('Złotówki lub waluta: sejf, portfel, konto'),
          onTap: () => Navigator.pop(c, 'cash'),
        ),
        ListTile(
          leading: const Icon(Icons.home_work_outlined),
          title: const Text('Nieruchomość'),
          subtitle: const Text('Mieszkanie, dom, działka, garaż'),
          onTap: () => Navigator.pop(c, 'property'),
        ),
      ]),
    ),
  );
  if (!context.mounted || pick == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => pick == 'cash' ? const CashForm() : const PropertyForm()),
  );
}

class AssetsTab extends StatelessWidget {
  const AssetsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ct = app.cashSummary;
    final pt = app.propertySummary;
    final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    final cash = [...app.cash]..sort((a, b) => (cashValue(b, app.rateOf) ?? 0).compareTo(cashValue(a, app.rateOf) ?? 0));
    final props = [...app.properties]
      ..sort((a, b) {
        if (a.sold != b.sold) return a.sold ? 1 : -1;
        return (b.buyDate ?? '').compareTo(a.buyDate ?? '');
      });
    Widget header(String title, String right) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(right, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
          ]),
        );
    BoxDecoration line() => BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        header('Gotówka', pln(ct.value)),
        if (ct.byCurrency.length > 1 || (ct.byCurrency.isNotEmpty && !ct.byCurrency.containsKey('PLN')))
          Text(ct.byCurrency.entries.map((e) => '${qtyFmt(e.value)} ${e.key}').join(' · '), style: small),
        if (ct.missingRate) Text('Brak kursu dla części walut – nie są wliczone.', style: TextStyle(fontSize: 12.5, color: Palette.warn(context))),
        if (cash.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Brak gotówki. Dodaj np. „Sejf – 5 000 PLN” albo „Portfel – 300 EUR”. Waluta liczy się po bieżącym kursie NBP.'),
          ),
        for (final c in cash)
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CashForm(existing: c))),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: line(),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name.isEmpty ? 'Gotówka' : c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        '${qtyFmt(c.amount)} ${c.currency}${c.updated != null ? ' · stan z ${dateFmt(c.updated)}' : ''}'
                        '${c.note.isNotEmpty ? ' · ${c.note}' : ''}',
                        style: small),
                  ]),
                ),
                Text(cashValue(c, app.rateOf) != null ? pln(cashValue(c, app.rateOf)!) : 'brak kursu',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        header('Nieruchomości', pln(pt.value)),
        if (props.isNotEmpty)
          Text('Wynik: ${signedPln(pt.net)} (zmiana wartości i najem)', style: small.copyWith(color: Palette.pl(context, pt.net))),
        if (props.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Brak nieruchomości. Wpisz cenę zakupu z kosztami i aktualną szacowaną wartość, a aplikacja policzy zysk lub stratę.'),
          ),
        for (final p in props) _PropertyTile(p: p, line: line()),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Gotówka w walucie liczy się po kursie NBP, bez wyniku. Jeśli tę samą walutę masz też w transakcjach kupna, nie wpisuj jej drugi raz, bo policzy się podwójnie.',
            style: small.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _PropertyTile extends StatelessWidget {
  final Property p;
  final BoxDecoration line;
  const _PropertyTile({required this.p, required this.line});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = propertyCalc(p);
    final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PropertyForm(existing: p))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: line,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (p.sold) Pill('sprzedana', cs.onSurfaceVariant),
                Text(p.name.isEmpty ? 'Nieruchomość' : p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              if (p.location.isNotEmpty) Text(p.location, style: small),
              Text(
                  'kupno ${dateFmt(p.buyDate)} za ${pln(c.cost)}'
                  '${p.sold ? ' · sprzedaż ${dateFmt(p.sellDate)} za ${pln(p.sellPrice ?? 0)}' : (p.value != null ? ' · wycena ${p.valueDate != null ? dateFmt(p.valueDate) : ''}' : ' · bez wyceny')}',
                  style: small),
              if (p.income != 0) Text('najem ${signedPln(p.income)}', style: small),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(p.sold ? 'sprzedana' : pln(c.value), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
            Text(signedPln(c.net), style: TextStyle(color: Palette.pl(context, c.net), fontFeatures: tabular)),
            if (c.annual != null) Text('${pct(c.annual!, signed: true)} r/r', style: small.copyWith(fontSize: 11.5)),
          ]),
        ]),
      ),
    );
  }
}
