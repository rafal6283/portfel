import 'package:flutter/material.dart';

import '../calc.dart';
import '../main.dart';
import '../models.dart';
import 'alerts_screen.dart';
import 'assets_tab.dart';
import 'deposit_form.dart';
import 'format.dart';
import 'settings.dart';
import 'tx_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  String? filter;

  void _add() {
    if (tab == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DepositForm()));
    } else if (tab == 2) {
      addAssetSheet(context);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TxForm(initialAsset: filter)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Portfel', style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [
              app.refreshing
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      tooltip: 'Odśwież kursy',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => app.refreshRates(force: true)),
              IconButton(
                  tooltip: 'Alerty cenowe',
                  icon: Icon(app.alerts.any((a) => a.active) ? Icons.notifications_active_outlined : Icons.notifications_none),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsScreen()))),
              IconButton(
                  tooltip: 'Ustawienia i kopia',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            ],
          ),
          body: IndexedStack(index: tab, children: [
            PortfolioTab(onPick: (code) => setState(() {
                  filter = code;
                  tab = 3;
                })),
            const DepositsTab(),
            const AssetsTab(),
            HistoryTab(filter: filter, onFilter: (f) => setState(() => filter = f)),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(switch (tab) { 1 => 'Lokata', 2 => 'Dodaj', _ => 'Transakcja' }),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Portfel'),
              NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Lokaty'),
              NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work), label: 'Majątek'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Historia'),
            ],
          ),
        );
      },
    );
  }
}

// ======================= PORTFEL =======================

class PortfolioTab extends StatelessWidget {
  final void Function(String code) onPick;
  const PortfolioTab({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = app.portfolio;
    final d = app.depositSummary;
    final c = app.cashSummary;
    final re = app.propertySummary;
    return RefreshIndicator(
      onRefresh: () => app.refreshRates(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (app.rateError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(app.rateError!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                ),
              ),
            ),
          _Summary(p: p, d: d, c: c, re: re),
          const SizedBox(height: 16),
          const _RateBoard(),
          const SizedBox(height: 20),
          Text('Pozycje', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (p.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Brak transakcji. Dodaj pierwsze kupno przyciskiem „Transakcja” albo zaimportuj kopię w Ustawieniach.'),
            ),
          for (final r in p.rows) _PositionTile(r: r, onTap: () => onPick(r.code)),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final Portfolio p;
  final DepositTotals d;
  final CashTotals c;
  final PropertyTotals re;
  const _Summary({required this.p, required this.d, required this.c, required this.re});

  @override
  Widget build(BuildContext context) {
    final total = p.unrealized + p.realized + d.net + re.net;
    final cs = Theme.of(context).colorScheme;
    Widget tile(String label, String value, {Color? color, String? sub}) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color, fontFeatures: tabular)),
            ),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ]),
        );
    return Column(children: [
      tile('Wartość dziś', pln(p.value + d.value + c.value + re.value),
          sub: [
            'waluty i kruszce ${pln(p.value)}',
            if (d.value > 0) 'lokaty ${pln(d.value)}',
            if (c.value > 0) 'gotówka ${pln(c.value)}',
            if (re.value > 0) 'nieruchomości ${pln(re.value)}',
          ].join(' · ')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: tile('Niezrealizowany', signedPln(p.unrealized),
                color: Palette.pl(context, p.unrealized), sub: p.cost > 0 ? '${pct(p.unrealized / p.cost)} od kosztu' : ' ')),
        const SizedBox(width: 8),
        Expanded(child: tile('Zrealizowany', signedPln(p.realized), color: Palette.pl(context, p.realized), sub: 'FIFO, po prowizjach')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: tile('Lokaty', signedPln(d.net), color: Palette.pl(context, d.net), sub: 'odsetki netto')),
        const SizedBox(width: 8),
        Expanded(
            child: tile('Nieruchomości', signedPln(re.net),
                color: Palette.pl(context, re.net), sub: re.owned + re.sold > 0 ? 'wartość i najem' : 'brak')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: tile('Wynik łącznie', signedPln(total), color: Palette.pl(context, total), sub: 'waluty, kruszce, lokaty, nieruchomości')),
      ]),
    ]);
  }
}

class _RateBoard extends StatelessWidget {
  const _RateBoard();

  Future<void> _edit(BuildContext context, Asset a) async {
    final ctrl = TextEditingController(text: numInput(app.rateOf(a.code)));
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${a.name} – kurs ręczny'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'PLN za 1 ${a.metal ? 'g' : a.code}'),
          ),
          const SizedBox(height: 8),
          const Text('Obowiązuje do następnego notowania NBP.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          if (app.isManual(a.code)) TextButton(onPressed: () => Navigator.pop(c, 'clear'), child: const Text('Wróć do NBP')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, 'set'), child: const Text('Ustaw')),
        ],
      ),
    );
    if (res == 'clear') await app.setManual(a.code, null);
    if (res == 'set') {
      final v = parseNum(ctrl.text);
      if (v != null && v > 0) await app.setManual(a.code, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = app.rates;
    final held = app.txs.map((t) => t.asset).toSet();
    final order = [...assets.where((a) => held.contains(a.code)), ...assets.where((a) => !held.contains(a.code))];
    String meta = r.asOf != null ? 'notowanie z ${dateFmt(r.asOf)}' : 'brak notowań';
    if (r.updatedAt != null) {
      final t = DateTime.tryParse(r.updatedAt!)?.toLocal();
      if (t != null) meta += ' · pobrano ${t.day}.${t.month.toString().padLeft(2, '0')} ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: Palette.board, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Kursy średnie',
            style: TextStyle(color: Palette.boardInk, fontWeight: FontWeight.w700, fontSize: 16)),
        Text('$meta · kruszce za 1 g', style: const TextStyle(color: Palette.boardDim, fontSize: 11.5)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 560 ? 5 : 3;
          const gap = 6.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final a in order) SizedBox(width: w, child: _RateChip(a: a, onTap: () => _edit(context, a))),
          ]);
        }),
      ]),
    );
  }
}

class _RateChip extends StatelessWidget {
  final Asset a;
  final VoidCallback onTap;
  const _RateChip({required this.a, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = app.rateOf(a.code);
    final manual = app.isManual(a.code);
    final prev = app.rates.prev[a.code];
    double? ch;
    if (!manual && prev != null && v != null && prev > 0) ch = (v - prev) / prev;
    final codeColor = a.code == 'XAU' ? Palette.gold : (a.code == 'XAG' ? Palette.silver : Palette.boardInk);
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(a.code, style: TextStyle(color: codeColor, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
              const Spacer(),
              if (manual) const Text('ręczny', style: TextStyle(color: Palette.gold, fontSize: 9.5)),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(rateFmt(a.code, v),
                  style: const TextStyle(color: Palette.boardInk, fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular)),
            ),
            Text(
              a.metal
                  ? (v != null ? '${n2(v * ozGrams)} /oz' : ' ')
                  : (ch != null ? pct(ch) : ' '),
              style: TextStyle(
                  fontSize: 10.5,
                  color: a.metal || ch == null
                      ? Palette.boardDim
                      : (ch > 0.0005 ? const Color(0xFF4CC98A) : (ch < -0.0005 ? const Color(0xFFF07A6A) : Palette.boardDim))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PositionTile extends StatelessWidget {
  final PositionRow r;
  final VoidCallback onTap;
  const _PositionTile({required this.r, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = assetOf(r.code);
    final cs = Theme.of(context).colorScheme;
    final u = r.unrealized;
    final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontFeatures: tabular);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: CircleAvatar(radius: 5, backgroundColor: Palette.assetDot(context, r.code)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a.name}  ${r.code}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (!r.closed)
                Text('${qtyLabel(r.code, r.qty)} · śr. ${rateFmt(r.code, r.avg)} zł${a.metal ? '/g' : ''}', style: small),
              if (r.oversold)
                Text('Sprzedano więcej, niż kupiono – sprawdź historię', style: TextStyle(fontSize: 12, color: Palette.loss(context))),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(r.closed ? 'zamknięta' : (r.value != null ? pln(r.value!) : 'brak kursu'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
            if (!r.closed && u != null)
              Text('${signedPln(u)}${r.cost > 0 ? '  ${pct(u / r.cost)}' : ''}',
                  style: TextStyle(fontSize: 12.5, color: Palette.pl(context, u), fontFeatures: tabular)),
            if (r.realized.abs() > 0.005)
              Text('zreal. ${signedPln(r.realized)}',
                  style: TextStyle(fontSize: 12, color: Palette.pl(context, r.realized), fontFeatures: tabular)),
          ]),
        ]),
      ),
    );
  }
}

// ======================= LOKATY =======================

class DepositsTab extends StatelessWidget {
  const DepositsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = app.depositSummary;
    const order = {'open': 0, 'unknown': 1, 'closed': 2};
    final list = [...app.deposits]
      ..sort((a, b) {
        final c = (order[a.status] ?? 3) - (order[b.status] ?? 3);
        if (c != 0) return c;
        return (b.start ?? b.end ?? '').compareTo(a.start ?? a.end ?? '');
      });
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10)),
          child: Wrap(spacing: 16, runSpacing: 4, children: [
            Text('Trwające: ${t.open}${t.principalOpen > 0 ? ' · ${pln(t.principalOpen)}' : ''}'),
            Text('Zakończone: ${t.closed}'),
            if (t.unknown > 0) Text('Bez wyniku: ${t.unknown}'),
            Text('Odsetki netto: ${signedPln(t.net)}',
                style: TextStyle(fontWeight: FontWeight.w700, color: Palette.pl(context, t.net))),
          ]),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Brak lokat. Dodaj trwającą lokatę z oprocentowaniem, a aplikacja doliczy odsetki narosłe do dziś (po 19% podatku).'),
          ),
        for (final d in list) _DepositTile(d: d),
      ],
    );
  }
}

class _DepositTile extends StatelessWidget {
  final Deposit d;
  const _DepositTile({required this.d});

  @override
  Widget build(BuildContext context) {
    final c = depositCalc(d);
    final cs = Theme.of(context).colorScheme;
    final (String lbl, Color col) = switch (d.status) {
      'open' => (c.matured ? 'po terminie' : 'trwa', cs.primary),
      'closed' => ('zakończona', cs.onSurfaceVariant),
      _ => ('brak wyniku', Palette.warn(context)),
    };
    final period = '${dateFmt(d.start)} → ${d.end != null ? dateFmt(d.end) : '?'}'
        '${c.days != null && d.status != 'open' ? ' · ${c.days} dni' : ''}';
    final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DepositForm(existing: d))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Pill(lbl, col),
                Text(d.bank.isEmpty ? 'Lokata' : d.bank, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (d.check) Pill('do sprawdzenia', Palette.warn(context)),
              ]),
              if (d.ref.isNotEmpty) Text(d.ref, style: small.copyWith(fontSize: 11.5)),
              Text(
                  '$period${d.rate != null ? ' · ${n2(d.rate!)}% brutto' : ''}'
                  '${d.status == 'open' && c.atMaturity != null ? ' · na koniec ${signedPln(c.atMaturity!)}' : ''}',
                  style: small),
              if (d.note.isNotEmpty) Text(d.note, style: small.copyWith(fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${d.noAnn ? 'wpłacono ' : ''}${pln(d.principal)}${d.principalGuess ? ' ?' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
            if (c.net != null)
              Text(signedPln(c.net!), style: TextStyle(color: Palette.pl(context, c.net), fontFeatures: tabular))
            else
              Text('–', style: small),
            if (c.annual != null) Text('${pct(c.annual!, signed: false)} netto r/r', style: small.copyWith(fontSize: 11.5)),
          ]),
        ]),
      ),
    );
  }
}

// ======================= HISTORIA =======================

class HistoryTab extends StatelessWidget {
  final String? filter;
  final ValueChanged<String?> onFilter;
  const HistoryTab({super.key, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final p = app.portfolio;
    final held = <String>{for (final t in app.txs) t.asset};
    var list = [...app.txs]..sort((a, b) => compareTx(b, a));
    if (filter != null) list = list.where((t) => t.asset == filter).toList();
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            ChoiceChip(label: Text('Wszystkie (${app.txs.length})'), selected: filter == null, onSelected: (_) => onFilter(null)),
            for (final a in assets.where((a) => held.contains(a.code)))
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(label: Text(a.code), selected: filter == a.code, onSelected: (_) => onFilter(a.code)),
              ),
          ],
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tu pojawią się zakupy i sprzedaże, także z przeszłych lat – wpisz datę i kurs z dnia transakcji.'),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final t = list[i];
                  final info = p.sells[t.id];
                  final metal = isMetal(t.asset);
                  final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
                  return InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxForm(existing: t))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)))),
                      child: Row(children: [
                        SizedBox(
                          width: 62,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Pill(t.isBuy ? 'KUPNO' : 'SPRZED.', t.isBuy ? Palette.gain(context) : Palette.loss(context)),
                          ),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Text(qtyLabel(t.asset, t.qty), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                              if (t.check) Pill('do sprawdzenia', Palette.warn(context)),
                            ]),
                            Text(
                              '${dateFmt(t.date)} · po ${rateFmt(t.asset, t.unitPrice)} zł${metal ? '/g' : ''}'
                              '${t.fee > 0 ? ' · prow. ${n2(t.fee)} zł' : ''}',
                              style: small,
                            ),
                            if (t.note.isNotEmpty)
                              Text(t.note, style: small.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(pln(t.total), style: const TextStyle(fontFeatures: tabular)),
                          if (info != null)
                            Text(signedPln(info.gain),
                                style: TextStyle(fontSize: 12.5, color: Palette.pl(context, info.gain), fontFeatures: tabular)),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
