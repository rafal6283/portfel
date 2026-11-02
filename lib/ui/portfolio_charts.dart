import 'package:flutter/material.dart';
import 'package:rodzina_wykresy/rodzina_wykresy.dart';

import '../history.dart';
import '../main.dart';
import '../models.dart';
import 'format.dart';

String _zl(double v) => '${plNum(v)} zł';

Color assetColor(String code, int i) => switch (code) {
      'XAU' => Palette.gold,
      'XAG' => const Color(0xFF9AA7B1),
      'USD' => const Color(0xFF2E7D32),
      'EUR' => const Color(0xFF1565C0),
      'CHF' => const Color(0xFFC62828),
      'GBP' => const Color(0xFF6A1B9A),
      _ => Colors.primaries[(i * 3) % Colors.primaries.length],
    };

/// Wartość walut i kruszców w czasie (kursy archiwalne NBP) wobec kosztu otwartych pozycji.
class ValueHistoryCard extends StatefulWidget {
  const ValueHistoryCard({super.key});
  @override
  State<ValueHistoryCard> createState() => _ValueHistoryCardState();
}

class _ValueHistoryCardState extends State<ValueHistoryCard> {
  int _days = 90;
  RateHistory? _hist;
  bool _loading = true;
  ChartPoint? _sel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _first {
    final d = app.txs.map((t) => t.date).fold<String?>(null, (a, b) => a == null || b.compareTo(a) < 0 ? b : a);
    return d == null ? DateTime.now() : DateTime.parse(d);
  }

  Future<void> _load() async {
    final cached = await RateHistoryStore.load();
    if (mounted) setState(() => _hist = cached);
    final codes = {for (final t in app.txs) t.asset};
    final from = _first.isBefore(DateTime.now().subtract(const Duration(days: 1100)))
        ? DateTime.now().subtract(const Duration(days: 1100))
        : _first.subtract(const Duration(days: 7));
    final h = await RateHistoryStore.update(codes, from);
    if (mounted) {
      setState(() {
        _hist = h;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (app.txs.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final from = _days == 0 ? _first : now.subtract(Duration(days: _days));
    final pts = _hist == null ? const <ValuePoint>[] : valueSeries(app.txs, _hist!, from.isBefore(_first) ? _first : from, now, app.rateOf);
    final value = [for (final p in pts) ChartPoint(p.day, p.value)];
    final cost = [for (final p in pts) ChartPoint(p.day, p.cost)];
    final change = pts.length >= 2 ? pts.last.value - pts.first.value : 0.0;
    final sel = _sel;
    final selPt = sel == null ? null : pts.where((p) => p.day == sel.x).firstOrNull;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Wartość w czasie', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              key: ValueKey(selPt?.day),
              selPt == null
                  ? 'Waluty i kruszce · zmiana w okresie ${change >= 0 ? '+' : ''}${_zl(change)}'
                  : '${plDayYear(selPt.day)} · wartość ${_zl(selPt.value)} · wynik ${selPt.value - selPt.cost >= 0 ? '+' : ''}${_zl(selPt.value - selPt.cost)}',
              style: t.bodySmall?.copyWith(color: selPt == null ? Palette.pl(context, change) : cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          InteractiveLineChart(
            series: [
              LineSeries('Wartość', cs.primary, value, area: true),
              LineSeries('Koszt', cs.outline, cost, dashed: true),
            ],
            yFormat: (v) => v.abs() >= 10000 ? '${plNum(v / 1000)} tys.' : plNum(v),
            height: 200,
            onSelect: (p) => setState(() => _sel = p),
          ),
          const SizedBox(height: 8),
          Center(child: RangeSelector(days: _days, onChanged: (d) => setState(() {
                _days = d;
                _sel = null;
              }))),
          const SizedBox(height: 4),
          Text('Kursy archiwalne NBP; srebro – kurs bieżący (NBP nie publikuje archiwum srebra).',
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Podział majątku i wynik na pozycjach.
class AllocationCard extends StatelessWidget {
  const AllocationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final p = app.portfolio;
    final d = app.depositSummary, c = app.cashSummary, re = app.propertySummary;
    final slices = <DonutSlice>[
      for (var i = 0; i < p.rows.length; i++)
        if ((p.rows[i].value ?? 0) > 0) DonutSlice(assetOf(p.rows[i].code).name, p.rows[i].value!, assetColor(p.rows[i].code, i)),
      if (d.value > 0) DonutSlice('Lokaty', d.value, const Color(0xFF00897B)),
      if (c.value > 0) DonutSlice('Gotówka', c.value, const Color(0xFF78909C)),
      if (re.value > 0) DonutSlice('Nieruchomości', re.value, const Color(0xFF8D6E63)),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final bars = [
      for (final r in p.rows)
        if ((r.unrealized ?? 0) != 0 || r.realized != 0)
          BarItem(r.code, (r.unrealized ?? 0) + r.realized,
              detail: '${assetOf(r.code).name}: niezrealizowany ${signedPln(r.unrealized ?? 0)}, zrealizowany ${signedPln(r.realized)}'),
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (slices.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Podział majątku', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Center(child: DonutChart(slices: slices, format: _zl, centerLabel: 'majątek')),
          if (bars.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Wynik na pozycjach', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('Niezrealizowany + zrealizowany (FIFO). Dotknij, by zobaczyć rozbicie.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            InteractiveBarChart(
              bars: bars,
              horizontal: true,
              format: (v) => '${v >= 0 ? '+' : ''}${_zl(v)}',
              color: Palette.gain(context),
              negativeColor: Palette.loss(context),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Wynik po inflacji: koszt zakupów przeliczony na dzisiejsze złote (HICP Polska, Eurostat).
class InflationCard extends StatefulWidget {
  const InflationCard({super.key});
  @override
  State<InflationCard> createState() => _InflationCardState();
}

class _InflationCardState extends State<InflationCard> {
  PriceIndex? _ix;

  @override
  void initState() {
    super.initState();
    InflationStore.load(refresh: false).then((c) {
      if (mounted && c.isNotEmpty) setState(() => _ix = c);
      return InflationStore.load();
    }).then((f) {
      if (mounted) setState(() => _ix = f);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ix = _ix;
    if (ix == null || ix.isEmpty || app.txs.isEmpty) return const SizedBox.shrink();
    final r = realResult(app.txs, app.rateOf, ix);
    if (r == null || r.cost <= 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget col(String label, double v, {bool big = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            AnimatedNumber(
              value: v,
              format: (x) => '${x >= 0 ? '+' : ''}${_zl(x)}',
              style: TextStyle(fontSize: big ? 19 : 16, fontWeight: FontWeight.w700, color: Palette.pl(context, v), fontFeatures: tabular),
            ),
          ]),
        );
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Wynik po inflacji', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [col('Nominalnie', r.nominal), col('Realnie', r.real, big: true)]),
          const SizedBox(height: 8),
          Text(
            'Otwarte pozycje walut i kruszców. Koszt zakupów w dzisiejszych złotych: ${_zl(r.realCost)} '
            '(inflacja od zakupów średnio ${plNum(r.inflationPct * 100, decimals: 1)}%). '
            '${r.real >= 0 ? 'Oszczędności zachowały siłę nabywczą.' : 'Wartość nie nadąża za inflacją.'}',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Text('Inflacja: HICP Polska (Eurostat), ostatni opublikowany miesiąc.', style: t.labelSmall?.copyWith(color: cs.outline)),
        ]),
      ),
    );
  }
}

/// Lokaty na osi czasu: od założenia do końca, z dzisiejszą datą; dotknięcie pokazuje szczegóły.
class DepositTimeline extends StatefulWidget {
  const DepositTimeline({super.key});
  @override
  State<DepositTimeline> createState() => _DepositTimelineState();
}

class _DepositTimelineState extends State<DepositTimeline> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final list = [
      for (final d in app.deposits)
        if (d.status == 'open' && d.start != null && d.end != null) d
    ]..sort((a, b) => a.end!.compareTo(b.end!));
    if (list.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final t0 = list.map((d) => DateTime.parse(d.start!)).reduce((a, b) => a.isBefore(b) ? a : b);
    final t1 = list.map((d) => DateTime.parse(d.end!)).reduce((a, b) => a.isAfter(b) ? a : b);
    final span = t1.difference(t0).inDays.clamp(1, 100000);
    double frac(DateTime d) => (d.difference(t0).inDays / span).clamp(0.0, 1.0);
    final next = list.firstWhere((d) => !DateTime.parse(d.end!).isBefore(DateTime(now.year, now.month, now.day)), orElse: () => list.first);
    final days = DateTime.parse(next.end!).difference(DateTime(now.year, now.month, now.day)).inDays;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(top: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kalendarz lokat', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(days >= 0 ? 'Najbliższa kończy się ${days == 0 ? 'dziś' : 'za $days ${days == 1 ? 'dzień' : 'dni'}'} (${dateFmt(next.end)})' : 'Wszystkie trwające lokaty mają minioną datę końca',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, p, _) => Stack(children: [
                Column(children: [
                  for (var i = 0; i < list.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _sel = _sel == i ? null : i),
                      child: SizedBox(
                        height: 30,
                        child: Stack(children: [
                          Positioned(
                            left: w * frac(DateTime.parse(list[i].start!)),
                            width: (w * (frac(DateTime.parse(list[i].end!)) - frac(DateTime.parse(list[i].start!))) * p).clamp(4.0, w),
                            top: 5,
                            height: 20,
                            child: Container(
                              decoration: BoxDecoration(
                                color: (_sel == null || _sel == i ? cs.primary : cs.primary.withValues(alpha: 0.35)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.centerLeft,
                              child: Text(list[i].bank.isEmpty ? pln(list[i].principal) : list[i].bank,
                                  maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(color: cs.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
                if (!now.isBefore(t0) && !now.isAfter(t1))
                  Positioned(left: w * frac(now), top: 0, bottom: 0, child: Container(width: 2, color: cs.tertiary)),
              ]),
            );
          }),
          Row(children: [
            Text(dateFmt(todayIso(t0)), style: t.labelSmall),
            const Spacer(),
            Text('dziś', style: t.labelSmall?.copyWith(color: cs.tertiary)),
            const Spacer(),
            Text(dateFmt(todayIso(t1)), style: t.labelSmall),
          ]),
          if (_sel != null && _sel! < list.length) ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final d = list[_sel!];
              return Text(
                '${d.bank.isEmpty ? 'Lokata' : d.bank}${d.ref.isEmpty ? '' : ' · ${d.ref}'}: ${pln(d.principal)}'
                '${d.rate != null ? ' · ${plNum(d.rate!, decimals: 2)}%' : ''} · ${dateFmt(d.start)} – ${dateFmt(d.end)}',
                style: t.bodyMedium,
              );
            }),
          ],
        ]),
      ),
    );
  }
}
