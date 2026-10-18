import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../rates.dart';
import 'format.dart';

class TxForm extends StatefulWidget {
  final Tx? existing;
  final String? initialAsset;
  const TxForm({super.key, this.existing, this.initialAsset});
  @override
  State<TxForm> createState() => _TxFormState();
}

class _TxFormState extends State<TxForm> {
  late String side;
  late String asset;
  late String date;
  String unit = 'g';
  final qty = TextEditingController();
  final price = TextEditingController();
  final total = TextEditingController();
  final fee = TextEditingController();
  final note = TextEditingController();
  bool lastEditedTotal = false;
  bool check = false;
  String? error;
  bool saving = false;
  HistRate? hist;
  bool histLoading = false;
  String _histKey = '';

  bool get editing => widget.existing != null;
  bool get metal => isMetal(asset);
  double get factor => metal && unit == 'oz' ? ozGrams : 1;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    if (t != null) {
      side = t.side;
      asset = t.asset;
      date = t.date;
      qty.text = numInput(t.qty);
      total.text = numInput(t.total);
      price.text = numInput(double.parse(t.unitPrice.toStringAsFixed(6)));
      fee.text = t.fee > 0 ? numInput(t.fee) : '';
      note.text = t.note;
      check = t.check;
    } else {
      side = 'buy';
      asset = widget.initialAsset ?? 'USD';
      date = todayIso();
    }
    _loadHist();
  }

  @override
  void dispose() {
    for (final c in [qty, price, total, fee, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHist() async {
    final key = '$asset|$date';
    if (key == _histKey) return;
    _histKey = key;
    if (asset == 'XAG') {
      setState(() => hist = null);
      return;
    }
    setState(() {
      histLoading = true;
      hist = null;
    });
    final r = await nbpRateOn(asset, date);
    if (!mounted || _histKey != key) return;
    setState(() {
      hist = r;
      histLoading = false;
    });
  }

  void _recalc() {
    final q = parseNum(qty.text), p = parseNum(price.text), t = parseNum(total.text);
    if (!lastEditedTotal && q != null && q > 0 && p != null && p > 0) {
      total.text = numInput(double.parse((q * p).toStringAsFixed(2)));
    } else if (lastEditedTotal && q != null && q > 0 && t != null && t > 0) {
      price.text = numInput(double.parse((t / q).toStringAsFixed(6)));
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(date) ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      locale: const Locale('pl'),
    );
    if (d != null) {
      setState(() => date = todayIso(d));
      _loadHist();
    }
  }

  Future<void> _save() async {
    final q = parseNum(qty.text), t = parseNum(total.text), f = parseNum(fee.text) ?? 0;
    String? err;
    if (q == null || q <= 0) {
      err = 'Podaj ilość większą od zera.';
    } else if (t == null || t <= 0) {
      err = 'Podaj kurs albo kwotę łączną w PLN.';
    } else if (f < 0) {
      err = 'Prowizja nie może być ujemna.';
    }
    if (err != null) {
      setState(() => error = err);
      return;
    }
    setState(() => saving = true);
    final old = widget.existing;
    final tx = Tx(
      id: old?.id ?? newId('t'),
      date: date,
      side: side,
      asset: asset,
      qty: double.parse((q! * factor).toStringAsFixed(6)),
      total: double.parse(t!.toStringAsFixed(2)),
      fee: double.parse(f.toStringAsFixed(2)),
      note: note.text.trim(),
      createdAt: old?.createdAt,
      check: check,
      extra: old?.extra,
    );
    await app.upsertTx(tx);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Usunąć transakcję?', 'Tej operacji nie można cofnąć.')) return;
    await app.deleteTx(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = assetOf(asset);
    final cur = app.rateOf(asset);
    final p = parseNum(price.text);
    final cs = Theme.of(context).colorScheme;
    String hint = '';
    if (cur != null) {
      hint = 'Kurs bieżący: ${rateFmt(asset, cur * factor)} zł za 1 ${metal ? unit : asset}.';
      if (p != null && p > 0) {
        final d = (cur * factor - p) / p;
        hint += ' Różnica od ceny transakcji: ${pct(d)}.';
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edytuj transakcję' : 'Nowa transakcja'),
        actions: [if (editing) IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'buy', label: Text('Kupno'), icon: Icon(Icons.south_west)),
              ButtonSegment(value: 'sell', label: Text('Sprzedaż'), icon: Icon(Icons.north_east)),
            ],
            selected: {side},
            onSelectionChanged: (s) => setState(() => side = s.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: asset,
            decoration: const InputDecoration(labelText: 'Aktywo'),
            items: [for (final x in assets) DropdownMenuItem(value: x.code, child: Text('${x.code} — ${x.name}'))],
            onChanged: (v) {
              if (v == null) return;
              setState(() => asset = v);
              _loadHist();
            },
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Data transakcji', suffixIcon: Icon(Icons.calendar_today, size: 18)),
              child: Text(dateFmt(date)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: metal ? 'Ilość (czysty kruszec)' : 'Ilość ($asset)'),
                onChanged: (_) => _recalc(),
              ),
            ),
            if (metal) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Jednostka'),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('gramy')),
                    DropdownMenuItem(value: 'oz', child: Text('uncje')),
                  ],
                  onChanged: (v) => setState(() => unit = v ?? 'g'),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: metal ? 'Cena (PLN za 1 $unit)' : 'Kurs (PLN za 1 $asset)'),
                onChanged: (_) {
                  lastEditedTotal = false;
                  _recalc();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: total,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kwota łączna (PLN)'),
                onChanged: (_) {
                  lastEditedTotal = true;
                  _recalc();
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _HistHint(
            asset: asset,
            hist: hist,
            loading: histLoading,
            factor: factor,
            unit: metal ? unit : asset,
            onUse: (v) {
              price.text = numInput(double.parse((v * factor).toStringAsFixed(6)));
              lastEditedTotal = false;
              _recalc();
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: fee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Prowizja (PLN)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(controller: note, decoration: const InputDecoration(labelText: 'Notatka')),
            ),
          ]),
          if (check || editing)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: check,
              onChanged: (v) => setState(() => check = v ?? false),
              title: const Text('Do sprawdzenia'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
          if (a.metal)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Ilość zapisuje się w gramach czystego kruszcu (1 oz = 31,1035 g).',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ),
          if (error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: saving ? null : _save, child: const Text('Zapisz')),
        ],
      ),
    );
  }
}

class _HistHint extends StatelessWidget {
  final String asset;
  final HistRate? hist;
  final bool loading;
  final double factor;
  final String unit;
  final ValueChanged<double> onUse;
  const _HistHint({required this.asset, required this.hist, required this.loading, required this.factor, required this.unit, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5);
    if (asset == 'XAG') return Text('NBP nie publikuje cen srebra – wpisz cenę z faktury.', style: style);
    if (loading) return Text('Sprawdzam kurs NBP z tego dnia…', style: style);
    if (hist == null) return Text('Brak kursu NBP z tego dnia (albo brak internetu).', style: style);
    return Row(children: [
      Expanded(
        child: Text('Średni NBP z ${dateFmt(hist!.date)}: ${rateFmt(asset, hist!.value * factor)} zł za 1 $unit', style: style),
      ),
      TextButton(onPressed: () => onUse(hist!.value), child: const Text('Użyj')),
    ]);
  }
}
