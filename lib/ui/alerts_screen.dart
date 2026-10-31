import 'dart:io';

import 'package:flutter/material.dart';

import '../alerts.dart';
import '../main.dart';
import '../models.dart';
import '../notify.dart';
import 'format.dart';

/// Alerty cenowe: powiadomienie, gdy kurs waluty lub kruszcu przekroczy ustawiony poziom.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final active = app.alerts.where((a) => a.active).toList();
        final done = app.alerts.where((a) => !a.active).toList()..sort((a, b) => (b.firedAt ?? '').compareTo(a.firedAt ?? ''));
        return Scaffold(
          appBar: AppBar(title: const Text('Alerty cenowe')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => editAlert(context),
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Nowy alert'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                Platform.isAndroid
                    ? 'Kursy są sprawdzane co ok. 2 godziny także przy zamkniętej aplikacji (NBP publikuje kursy raz dziennie w dni robocze, srebro – na bieżąco).'
                    : 'Kursy są sprawdzane przy każdym odświeżeniu w aplikacji.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
            ),
            if (app.alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Brak alertów. Np. „złoto powyżej 550 zł/g” albo „euro poniżej 4,20 zł”.', textAlign: TextAlign.center)),
              ),
            if (active.isNotEmpty) const SectionTitle('Aktywne'),
            for (final a in active) _AlertTile(a),
            if (done.isNotEmpty) const SectionTitle('Zadziałały'),
            for (final a in done) _AlertTile(a),
          ]),
        );
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  final PriceAlert a;
  const _AlertTile(this.a);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unit = isMetal(a.asset) ? 'zł/g' : 'zł';
    final now = app.rateOf(a.asset);
    final dist = now == null || now == 0 ? null : (a.price - now) / now;
    return ListTile(
      leading: Icon(a.above ? Icons.trending_up : Icons.trending_down, color: a.active ? cs.primary : cs.outline),
      title: Text('${assetOf(a.asset).name} ${a.above ? '≥' : '≤'} ${rateFmt(a.asset, a.price)} $unit'),
      subtitle: Text(a.active
          ? 'Teraz ${rateFmt(a.asset, now)} $unit${dist == null ? '' : ' · brakuje ${pct(dist.abs(), signed: false)}'}'
          : 'Zadziałał ${dateFmt(a.firedAt?.substring(0, 10))} przy ${rateFmt(a.asset, a.firedRate)} $unit'),
      trailing: a.active
          ? IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: () => app.deleteAlert(a.id))
          : TextButton(
              onPressed: () => app.upsertAlert(a
                ..active = true
                ..firedAt = null
                ..firedRate = null),
              child: const Text('Włącz ponownie')),
      onTap: () => editAlert(context, a),
      onLongPress: () async {
        if (await confirm(context, 'Usunąć alert?', 'Alert zostanie usunięty.')) app.deleteAlert(a.id);
      },
    );
  }
}

Future<void> editAlert(BuildContext context, [PriceAlert? edit]) async {
  var asset = edit?.asset ?? 'XAU';
  var above = edit?.above ?? true;
  final ctrl = TextEditingController(text: edit == null ? '' : numInput(edit.price));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final now = app.rateOf(asset);
      final unit = isMetal(asset) ? 'zł/g' : 'zł';
      return AlertDialog(
        title: Text(edit == null ? 'Nowy alert' : 'Alert'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            initialValue: asset,
            decoration: const InputDecoration(labelText: 'Waluta / kruszec'),
            items: [for (final a in assets) DropdownMenuItem(value: a.code, child: Text('${a.name} (${a.code})'))],
            onChanged: (v) => set(() => asset = v ?? asset),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Powyżej'), icon: Icon(Icons.trending_up)),
              ButtonSegment(value: false, label: Text('Poniżej'), icon: Icon(Icons.trending_down)),
            ],
            selected: {above},
            onSelectionChanged: (v) => set(() => above = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Kurs', suffixText: unit, helperText: 'Teraz: ${rateFmt(asset, now)} $unit'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zapisz')),
        ],
      );
    }),
  );
  if (ok != true) return;
  final price = parseNum(ctrl.text);
  if (price == null || price <= 0) {
    if (context.mounted) toast(context, 'Podaj kurs większy od zera');
    return;
  }
  final now = app.rateOf(asset);
  if (now != null && (above ? now >= price : now <= price) && context.mounted) {
    toast(context, 'Kurs już teraz spełnia ten warunek – alert zadziała przy najbliższym sprawdzeniu');
  }
  await Notify.requestPermission();
  await app.upsertAlert(PriceAlert(id: edit?.id ?? newId('a'), asset: asset, above: above, price: price));
}
