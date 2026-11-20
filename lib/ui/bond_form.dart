import 'package:flutter/material.dart';

import '../bonds.dart';
import '../main.dart';
import '../models.dart';
import 'format.dart';

/// Zakup obligacji skarbowych jednej serii (EDO, COI, ROD, TOS…).
class BondForm extends StatefulWidget {
  final Bond? existing;
  const BondForm({super.key, this.existing});
  @override
  State<BondForm> createState() => _BondFormState();
}

class _BondFormState extends State<BondForm> {
  final series = TextEditingController();
  final date = TextEditingController();
  final count = TextEditingController();
  final rates = TextEditingController();
  final margin = TextEditingController();
  final redeemed = TextEditingController();
  final note = TextEditingController();
  String? error;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      series.text = b.series;
      date.text = b.date;
      count.text = '${b.count}';
      rates.text = b.rates.map(numInput).join('; ');
      margin.text = numInput(b.margin);
      redeemed.text = b.redeemed ?? '';
      note.text = b.note;
    } else {
      date.text = todayIso();
    }
  }

  @override
  void dispose() {
    for (final c in [series, date, count, rates, margin, redeemed, note]) {
      c.dispose();
    }
    super.dispose();
  }

  BondType? get _type => bondTypeOf(series.text);

  List<double>? _rates() {
    final parts = rates.text.split(RegExp(r'[;\s]+')).where((s) => s.trim().isNotEmpty);
    final out = <double>[];
    for (final p in parts) {
      final v = parseNum(p);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  void _fillOffer() {
    final t = _type;
    if (t == null) return;
    if (rates.text.trim().isEmpty && t.offerRate != null) rates.text = numInput(t.offerRate);
    if (margin.text.trim().isEmpty && t.offerMargin != null) margin.text = numInput(t.offerMargin);
  }

  Future<void> _save() async {
    final t = _type;
    final n = int.tryParse(count.text.trim());
    final r = _rates();
    final d = DateTime.tryParse(date.text.trim());
    final red = redeemed.text.trim();
    if (t == null) {
      setState(() => error = 'Podaj serię, np. EDO1136 albo COI0730 (pierwsze trzy litery to rodzaj).');
      return;
    }
    if (d == null) {
      setState(() => error = 'Podaj datę zakupu (rrrr-mm-dd).');
      return;
    }
    if (n == null || n <= 0) {
      setState(() => error = 'Podaj liczbę obligacji (każda po 100 zł).');
      return;
    }
    if (r == null || r.isEmpty) {
      setState(() => error = 'Podaj oprocentowanie co najmniej pierwszego roku, np. 5,35.');
      return;
    }
    if (red.isNotEmpty && DateTime.tryParse(red) == null) {
      setState(() => error = 'Data wykupu: rrrr-mm-dd.');
      return;
    }
    final old = widget.existing;
    await app.upsertBond(Bond(
      id: old?.id ?? newId('b'),
      series: series.text.trim().toUpperCase(),
      date: date.text.trim(),
      count: n,
      rates: r,
      margin: t.inflation ? parseNum(margin.text) : null,
      redeemed: red.isEmpty ? null : red,
      note: note.text.trim(),
      extra: old?.extra,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Usunąć obligacje?', 'Tej operacji nie można cofnąć.')) return;
    await app.deleteBond(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5);
    final t = _type;
    final n = int.tryParse(count.text.trim());
    final r = _rates();
    BondCalc? preview;
    if (t != null && n != null && n > 0 && r != null && r.isNotEmpty && DateTime.tryParse(date.text.trim()) != null) {
      preview = bondCalc(
        Bond(id: '-', series: series.text, date: date.text.trim(), count: n, rates: r, margin: parseNum(margin.text),
            redeemed: redeemed.text.trim().isEmpty ? null : redeemed.text.trim()),
        inflationYoY: app.inflationYoY,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edytuj obligacje' : 'Obligacje skarbowe'),
        actions: [if (editing) IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: series,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Seria (np. EDO1136, COI0730, ROD1138)'),
            onChanged: (_) => setState(_fillOffer),
          ),
          if (t != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Obligacje ${t.name}', style: small)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: date,
                decoration: const InputDecoration(labelText: 'Data zakupu (rrrr-mm-dd)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextField(
                controller: count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sztuk (×100 zł)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: rates,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
                labelText: 'Oprocentowanie kolejnych lat, %',
                helperText: 'Np. „5,35; 6,9” — z historii oprocentowania w banku. Brakujące lata: szacunek.'),
            onChanged: (_) => setState(() {}),
          ),
          if (t?.inflation == true) ...[
            const SizedBox(height: 12),
            TextField(
              controller: margin,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Marża ponad inflację, %'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: redeemed,
            decoration: const InputDecoration(labelText: 'Wykupione dnia (puste = trwają)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Notatka (np. IKE, dla dziecka)')),
          if (preview != null) ...[
            const SizedBox(height: 16),
            Text(
              [
                'Wartość z odsetkami: ${pln(preview.grossValue)} (okres ${preview.period}, ${n2(preview.currentRate)}%'
                    '${preview.estimated ? ', szacunek' : ''})',
                if (preview.paidOut > 0) 'Wypłacone odsetki netto: ${pln(preview.paidOut)}',
                if (preview.matured) 'Wykup w terminie ${dateFmt(preview.maturity)} — bez opłaty'
                else 'Przy wykupie dziś: opłata ${pln(preview.fee)}, podatek ${pln(preview.tax)} → ${pln(preview.netIfRedeemed)}',
                'Wynik netto: ${signedPln(preview.net)} · termin wykupu ${dateFmt(preview.maturity)}',
              ].join('\n'),
              style: small,
            ),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Zapisz')),
          const SizedBox(height: 8),
          Text(
              'Wpisz stopy z historii oprocentowania w banku — wtedy wynik jest dokładny. Brakujące lata obligacji '
              'indeksowanych aplikacja szacuje: inflacja (HICP z Eurostatu, bliska GUS) + marża. '
              'Podpowiedzi oprocentowania to oferta z listopada 2026 — sprawdź swoją serię.',
              style: small.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
