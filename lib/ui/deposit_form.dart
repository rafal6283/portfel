import 'package:flutter/material.dart';

import '../calc.dart';
import '../main.dart';
import '../models.dart';
import 'format.dart';

class DepositForm extends StatefulWidget {
  final Deposit? existing;
  const DepositForm({super.key, this.existing});
  @override
  State<DepositForm> createState() => _DepositFormState();
}

class _DepositFormState extends State<DepositForm> {
  final bank = TextEditingController();
  final ref = TextEditingController();
  final principal = TextEditingController();
  final rate = TextEditingController();
  final payout = TextEditingController();
  final interest = TextEditingController();
  final note = TextEditingController();
  String? start;
  String? end;
  String status = 'open';
  bool check = false;
  bool noAnn = false;
  String? error;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    if (d != null) {
      bank.text = d.bank;
      ref.text = d.ref;
      principal.text = numInput(d.principal);
      rate.text = numInput(d.rate);
      payout.text = numInput(d.payout);
      interest.text = numInput(d.interest);
      note.text = d.note;
      start = d.start;
      end = d.end;
      status = d.status;
      check = d.check;
      noAnn = d.noAnn;
    } else {
      start = todayIso();
    }
  }

  @override
  void dispose() {
    for (final c in [bank, ref, principal, rate, payout, interest, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _pick(String? current, {bool future = false}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current ?? '') ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(Duration(days: future ? 3650 : 0)),
      locale: const Locale('pl'),
    );
    return d == null ? null : todayIso(d);
  }

  Deposit? _build({bool forPreview = false}) {
    final p = parseNum(principal.text);
    if (p == null || p <= 0) return null;
    final old = widget.existing;
    final pay = parseNum(payout.text);
    final intr = parseNum(interest.text);
    final r = parseNum(rate.text);
    final d = Deposit(
      id: old?.id ?? newId('d'),
      bank: bank.text.trim(),
      ref: ref.text.trim(),
      start: start,
      end: end,
      principal: double.parse(p.toStringAsFixed(2)),
      rate: r != null && r > 0 ? r : null,
      status: status,
      payout: status == 'closed' && pay != null && pay > 0 ? double.parse(pay.toStringAsFixed(2)) : null,
      interest: status == 'closed' && intr != null && intr >= 0 ? double.parse(intr.toStringAsFixed(2)) : null,
      tax: old?.tax,
      note: note.text.trim(),
      noAnn: noAnn,
      check: check,
      principalGuess: old?.principalGuess ?? false,
      extra: old?.extra,
    );
    // zmieniona wypłata bez odsetek → stary podatek nieaktualny
    if (old != null && old.payout != d.payout && d.interest == null) d.tax = null;
    return d;
  }

  Future<void> _save() async {
    final p = parseNum(principal.text);
    String? err;
    if (p == null || p <= 0) {
      err = 'Podaj kwotę lokaty.';
    } else if (start != null && end != null && end!.compareTo(start!) < 0) {
      err = 'Koniec lokaty nie może być przed datą założenia.';
    } else if (status == 'open' && start == null) {
      err = 'Podaj datę założenia trwającej lokaty.';
    } else if (status == 'closed' && parseNum(payout.text) == null && parseNum(interest.text) == null) {
      err = 'Podaj kwotę wypłaconą albo odsetki.';
    }
    if (err != null) {
      setState(() => error = err);
      return;
    }
    await app.upsertDeposit(_build()!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Usunąć lokatę?', 'Tej operacji nie można cofnąć.')) return;
    await app.deleteDeposit(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = _build(forPreview: true);
    String hint = '';
    if (preview != null) {
      final c = depositCalc(preview);
      if (status == 'open' && preview.rate != null) {
        hint = 'Narosło do dziś: ${signedPln(c.net ?? 0)} netto';
        if (c.atMaturity != null) hint += ' · na koniec ${signedPln(c.atMaturity!)} netto';
      } else if (status == 'open') {
        hint = 'Bez oprocentowania odsetki nie są doliczane.';
      } else if (status == 'closed' && c.net != null) {
        hint = 'Zysk netto: ${signedPln(c.net!)}${c.annual != null ? ' · ${pct(c.annual!, signed: false)} r/r' : ''}';
      }
    }
    Widget dateField(String label, String? v, ValueChanged<String?> set, {bool future = false}) => InkWell(
          onTap: () async {
            final d = await _pick(v, future: future);
            if (d != null) setState(() => set(d));
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: v != null
                  ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => set(null)))
                  : const Icon(Icons.calendar_today, size: 18),
            ),
            child: Text(v != null ? dateFmt(v) : '—'),
          ),
        );
    num2(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edytuj lokatę' : 'Nowa lokata'),
        actions: [if (editing) IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [
            Expanded(child: TextField(controller: bank, decoration: const InputDecoration(labelText: 'Bank'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: ref, decoration: const InputDecoration(labelText: 'Numer (opcjonalnie)'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: dateField('Założona', start, (v) => start = v)),
            const SizedBox(width: 10),
            Expanded(child: dateField('Koniec / termin', end, (v) => end = v, future: true)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: num2(principal, 'Kwota (PLN)')),
            const SizedBox(width: 10),
            Expanded(child: num2(rate, 'Oprocentowanie % r/r')),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Stan'),
            items: const [
              DropdownMenuItem(value: 'open', child: Text('Trwa')),
              DropdownMenuItem(value: 'closed', child: Text('Zakończona')),
              DropdownMenuItem(value: 'unknown', child: Text('Zakończona, wynik nieznany')),
            ],
            onChanged: (v) => setState(() => status = v ?? 'open'),
          ),
          if (status == 'closed') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: num2(payout, 'Wypłacono łącznie (PLN)')),
              const SizedBox(width: 10),
              Expanded(child: num2(interest, 'Odsetki brutto (opcj.)')),
            ]),
          ],
          const SizedBox(height: 12),
          TextField(controller: note, maxLines: null, decoration: const InputDecoration(labelText: 'Notatka')),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: noAnn,
            onChanged: (v) => setState(() => noAnn = v ?? false),
            title: const Text('Wiele wpłat i wypłat'),
            subtitle: const Text('Nie pokazuj oprocentowania w skali roku'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: check,
            onChanged: (v) => setState(() => check = v ?? false),
            title: const Text('Do sprawdzenia'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (hint.isNotEmpty) Text(hint, style: TextStyle(color: cs.onSurfaceVariant)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Zapisz')),
        ],
      ),
    );
  }
}
