import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import 'format.dart';

class CashForm extends StatefulWidget {
  final CashEntry? existing;
  const CashForm({super.key, this.existing});
  @override
  State<CashForm> createState() => _CashFormState();
}

class _CashFormState extends State<CashForm> {
  final name = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  String currency = 'PLN';
  String? error;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      name.text = c.name;
      amount.text = numInput(c.amount);
      note.text = c.note;
      currency = cashCurrencies.contains(c.currency) ? c.currency : 'PLN';
    }
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = parseNum(amount.text);
    if (a == null || a < 0) {
      setState(() => error = 'Podaj kwotę.');
      return;
    }
    final old = widget.existing;
    await app.upsertCash(CashEntry(
      id: old?.id ?? newId('c'),
      name: name.text.trim(),
      currency: currency,
      amount: double.parse(a.toStringAsFixed(2)),
      updated: todayIso(),
      note: note.text.trim(),
      extra: old?.extra,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Usunąć gotówkę?', 'Tej operacji nie można cofnąć.')) return;
    await app.deleteCash(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = parseNum(amount.text);
    final r = currency == 'PLN' ? 1.0 : app.rateOf(currency);
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edytuj gotówkę' : 'Gotówka'),
        actions: [if (editing) IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Gdzie (np. sejf, portfel, konto)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kwota'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Waluta'),
                items: [for (final c in cashCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => currency = v ?? 'PLN'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (currency != 'PLN' && a != null)
            Text(r != null ? '= ${pln(a * r)} po kursie ${rateFmt(currency, r)}' : 'Brak kursu $currency',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Notatka')),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Zapisz')),
          const SizedBox(height: 8),
          Text('Zapisanie ustawia datę stanu na dziś. Gdy kwota się zmieni, po prostu ją popraw.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}
