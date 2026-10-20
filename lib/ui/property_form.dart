import 'package:flutter/material.dart';

import '../calc.dart';
import '../main.dart';
import '../models.dart';
import 'format.dart';

class PropertyForm extends StatefulWidget {
  final Property? existing;
  const PropertyForm({super.key, this.existing});
  @override
  State<PropertyForm> createState() => _PropertyFormState();
}

class _PropertyFormState extends State<PropertyForm> {
  final name = TextEditingController();
  final location = TextEditingController();
  final buyPrice = TextEditingController();
  final buyCosts = TextEditingController();
  final value = TextEditingController();
  final sellPrice = TextEditingController();
  final sellCosts = TextEditingController();
  final income = TextEditingController();
  final note = TextEditingController();
  String? buyDate;
  String? valueDate;
  String? sellDate;
  bool sold = false;
  String? error;

  bool get editing => widget.existing != null;
  List<TextEditingController> get _all => [name, location, buyPrice, buyCosts, value, sellPrice, sellCosts, income, note];

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      name.text = p.name;
      location.text = p.location;
      buyPrice.text = numInput(p.buyPrice);
      buyCosts.text = p.buyCosts > 0 ? numInput(p.buyCosts) : '';
      value.text = numInput(p.value);
      sellPrice.text = numInput(p.sellPrice);
      sellCosts.text = numInput(p.sellCosts);
      income.text = p.income != 0 ? numInput(p.income) : '';
      note.text = p.note;
      buyDate = p.buyDate;
      valueDate = p.valueDate;
      sellDate = p.sellDate;
      sold = p.sold;
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Property? _build() {
    final bp = parseNum(buyPrice.text);
    if (bp == null || bp <= 0) return null;
    final old = widget.existing;
    final v = parseNum(value.text);
    final oldValue = old?.value;
    return Property(
      id: old?.id ?? newId('n'),
      name: name.text.trim(),
      location: location.text.trim(),
      buyDate: buyDate,
      buyPrice: bp,
      buyCosts: parseNum(buyCosts.text) ?? 0,
      value: v,
      // nowa wycena = dzisiejsza data, chyba że wartość się nie zmieniła
      valueDate: v == null ? null : (v == oldValue ? (valueDate ?? todayIso()) : todayIso()),
      sold: sold,
      sellDate: sold ? sellDate : null,
      sellPrice: sold ? parseNum(sellPrice.text) : null,
      sellCosts: sold ? parseNum(sellCosts.text) : null,
      income: parseNum(income.text) ?? 0,
      note: note.text.trim(),
      extra: old?.extra,
    );
  }

  Future<void> _save() async {
    final p = _build();
    String? err;
    if (p == null) {
      err = 'Podaj cenę zakupu.';
    } else if (sold && (p.sellPrice == null || p.sellPrice! <= 0)) {
      err = 'Podaj cenę sprzedaży.';
    } else if (sold && p.sellDate != null && p.buyDate != null && p.sellDate!.compareTo(p.buyDate!) < 0) {
      err = 'Data sprzedaży nie może być przed datą zakupu.';
    }
    if (err != null) {
      setState(() => error = err);
      return;
    }
    await app.upsertProperty(p!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Usunąć nieruchomość?', 'Tej operacji nie można cofnąć.')) return;
    await app.deleteProperty(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate(String? current, ValueChanged<String> set) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current ?? '') ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      locale: const Locale('pl'),
    );
    if (d != null) setState(() => set(todayIso(d)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = _build();
    String hint = '';
    if (preview != null) {
      final c = propertyCalc(preview);
      hint = 'Koszt zakupu: ${pln(c.cost)} · ${sold ? 'zysk ze sprzedaży' : 'zmiana wartości'}: ${signedPln(c.change)}'
          '${preview.income != 0 ? ' · z najmem: ${signedPln(c.net)}' : ''}'
          '${c.annual != null ? ' · ${pct(c.annual!)} r/r' : ''}';
    }
    Widget numField(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        );
    Widget date(String label, String? v, ValueChanged<String> set) => InkWell(
          onTap: () => _pickDate(v, set),
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
            child: Text(v != null ? dateFmt(v) : '—'),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edytuj nieruchomość' : 'Nieruchomość'),
        actions: [if (editing) IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nazwa (np. Mieszkanie Mokotów)')),
          const SizedBox(height: 12),
          TextField(controller: location, decoration: const InputDecoration(labelText: 'Adres / opis (opcjonalnie)')),
          const SizedBox(height: 16),
          const SectionHeader('Zakup'),
          date('Data zakupu', buyDate, (v) => buyDate = v),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: numField(buyPrice, 'Cena zakupu (PLN)')),
            const SizedBox(width: 10),
            Expanded(child: numField(buyCosts, 'Koszty zakupu (PLN)')),
          ]),
          const SizedBox(height: 4),
          Text('Koszty: notariusz, PCC, prowizja, remont podnoszący wartość.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: sold,
            onChanged: (v) => setState(() => sold = v),
            title: const Text('Sprzedana'),
          ),
          if (!sold) ...[
            const SectionHeader('Wartość dziś'),
            numField(value, 'Szacowana wartość (PLN)'),
            const SizedBox(height: 4),
            Text(
              valueDate != null ? 'Ostatnia wycena: ${dateFmt(valueDate)}. Zmiana kwoty zapisze dzisiejszą datę.' : 'Bez wyceny liczy się cena zakupu z kosztami.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ] else ...[
            const SectionHeader('Sprzedaż'),
            date('Data sprzedaży', sellDate, (v) => sellDate = v),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: numField(sellPrice, 'Cena sprzedaży (PLN)')),
              const SizedBox(width: 10),
              Expanded(child: numField(sellCosts, 'Koszty sprzedaży (PLN)')),
            ]),
          ],
          const SizedBox(height: 16),
          const SectionHeader('Najem (opcjonalnie)'),
          numField(income, 'Dochód z najmu netto łącznie (PLN)'),
          const SizedBox(height: 12),
          TextField(controller: note, maxLines: null, decoration: const InputDecoration(labelText: 'Notatka')),
          if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(hint, style: TextStyle(color: cs.onSurfaceVariant))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Zapisz')),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}
