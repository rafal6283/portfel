import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

final _pln = NumberFormat.currency(locale: 'pl_PL', symbol: 'zł', decimalDigits: 2);
final _n2 = NumberFormat('#,##0.00', 'pl_PL');
final _n4 = NumberFormat('#,##0.0000', 'pl_PL');
final _q = NumberFormat('#,##0.####', 'pl_PL');
final _pct = NumberFormat('0.0', 'pl_PL');

String pln(double v) => _pln.format(v);
String signedPln(double v) => (v > 0.005 ? '+' : '') + _pln.format(v);
String n2(double v) => _n2.format(v);
String qtyFmt(double v) => _q.format(v);
String pct(double fraction, {bool signed = true}) {
  final s = _pct.format(fraction * 100);
  return (signed && fraction > 0.0005 ? '+' : '') + s + '%';
}

String rateFmt(String code, double? v) {
  if (v == null) return '–';
  if (v < 0.1) return _q.format(v);
  return isMetal(code) ? _n2.format(v) : _n4.format(v);
}

String qtyLabel(String code, double q) {
  if (isMetal(code)) return '${_q.format(q)} g · ${_q.format(q / ozGrams)} oz';
  return '${_q.format(q)} $code';
}

const _months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
String dateFmt(String? iso) {
  if (iso == null || iso.length < 10) return '?';
  final y = iso.substring(0, 4), m = int.tryParse(iso.substring(5, 7)) ?? 1, d = int.tryParse(iso.substring(8, 10)) ?? 1;
  final int mi = m < 1 ? 0 : (m > 12 ? 11 : m - 1);
  return '$d ${_months[mi]} $y';
}

/// Parsuje liczbę wpisaną po polsku: "1 234,56" albo "1234.56".
double? parseNum(String s) {
  final t = s.trim().replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String numInput(double? v) {
  if (v == null) return '';
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

// ---------- kolory ----------

class Palette {
  static const board = Color(0xFF14201C);
  static const boardInk = Color(0xFFE9EFE9);
  static const boardDim = Color(0xFF8FA39A);
  static const gold = Color(0xFFE3B552);
  static const silver = Color(0xFFC5CFD6);
  static const seed = Color(0xFF0F5D4C);

  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color gain(BuildContext c) => _dark(c) ? const Color(0xFF4CC98A) : const Color(0xFF17804A);
  static Color loss(BuildContext c) => _dark(c) ? const Color(0xFFF07A6A) : const Color(0xFFC23A2B);
  static Color warn(BuildContext c) => _dark(c) ? const Color(0xFFE0B04F) : const Color(0xFFA8791C);

  static Color? pl(BuildContext c, double? v) {
    if (v == null) return null;
    if (v > 0.005) return gain(c);
    if (v < -0.005) return loss(c);
    return null;
  }

  static Color assetDot(BuildContext c, String code) {
    if (code == 'XAU') return gold;
    if (code == 'XAG') return silver;
    return Theme.of(c).colorScheme.primary;
  }
}

const tabular = [FontFeature.tabularFigures()];

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Usuń'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Mała etykieta-pastylka.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      );
}
