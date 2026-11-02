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
