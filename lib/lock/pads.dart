// Klawiatura PIN i siatka wzoru 3×3.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PinPad extends StatefulWidget {
  /// PIN zatwierdza się sam po wpisaniu [length] cyfr – bez przycisku „OK”.
  final int length;
  final bool enabled;
  final Future<void> Function(String pin) onSubmit;
  /// Opcjonalny przycisk w lewym dolnym rogu (np. odcisk palca).
  final Widget? leftKey;
  const PinPad({super.key, required this.length, this.enabled = true, required this.onSubmit, this.leftKey});

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String pin = '';
  bool busy = false;

  void clear() => setState(() => pin = '');

  Future<void> _submit() async {
    if (busy) return;
    busy = true;
    final v = pin;
    // krótka chwila, żeby była widoczna ostatnia kropka
    await Future.delayed(const Duration(milliseconds: 120));
    try {
      await widget.onSubmit(v);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          pin = '';
        });
      }
    }
  }

  void _tap(String d) {
    if (!widget.enabled || busy || pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => pin += d);
    if (pin.length == widget.length) _submit();
  }

  void _back() {
    if (pin.isEmpty || busy) return;
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => SizedBox(
          width: 76,
          height: 64,
          child: TextButton(
            onPressed: widget.enabled ? onTap : null,
            style: TextButton.styleFrom(shape: const CircleBorder()),
            child: child ?? Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < widget.length; i++)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < pin.length ? cs.primary : Colors.transparent,
              border: Border.all(color: cs.primary, width: 1.6),
            ),
          ),
      ]),
      const SizedBox(height: 24),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9']
      ])
        Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d, onTap: () => _tap(d))]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 76, height: 64, child: widget.leftKey),
        key('0', onTap: () => _tap('0')),
        key('', onTap: _back, child: const Icon(Icons.backspace_outlined)),
      ]),
    ]);
  }
}

class PatternPad extends StatefulWidget {
  final bool enabled;
  final int minPoints;
  final Future<void> Function(List<int> points) onSubmit;
  const PatternPad({super.key, this.enabled = true, this.minPoints = 4, required this.onSubmit});

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> pts = [];
  Offset? finger;
  bool error = false;
  static const double size = 270;

  Offset _center(int i) {
    const cell = size / 3;
    return Offset(cell * (i % 3) + cell / 2, cell * (i ~/ 3) + cell / 2);
  }

  void _hit(Offset p) {
    for (var i = 0; i < 9; i++) {
      if (pts.contains(i)) continue;
      if ((p - _center(i)).distance < size / 9) {
        // punkt pośrodku linii (np. 0→2 przez 1) dodaje się sam, jak w Androidzie
        if (pts.isNotEmpty) {
          final a = pts.last;
          final ax = a % 3, ay = a ~/ 3, bx = i % 3, by = i ~/ 3;
          if ((ax + bx) % 2 == 0 && (ay + by) % 2 == 0) {
            final mid = ((ay + by) ~/ 2) * 3 + (ax + bx) ~/ 2;
            if (!pts.contains(mid)) pts.add(mid);
          }
        }
        pts.add(i);
        HapticFeedback.selectionClick();
        break;
      }
    }
  }

  Future<void> _end() async {
    final v = List<int>.from(pts);
    setState(() => finger = null);
    if (v.isEmpty) return;
    if (v.length < widget.minPoints) {
      setState(() => error = true);
    } else {
      await widget.onSubmit(v);
    }
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      setState(() {
        pts.clear();
        error = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onPanStart: widget.enabled
            ? (d) => setState(() {
                  pts.clear();
                  error = false;
                  finger = d.localPosition;
                  _hit(d.localPosition);
                })
            : null,
        onPanUpdate: widget.enabled
            ? (d) => setState(() {
                  finger = d.localPosition;
                  _hit(d.localPosition);
                })
            : null,
        onPanEnd: widget.enabled ? (_) => _end() : null,
        child: CustomPaint(
          size: const Size(size, size),
          painter: _PatternPainter(pts, finger, _center, error ? cs.error : cs.primary, cs.outline),
        ),
      ),
      const SizedBox(height: 8),
      Text(error ? 'Połącz co najmniej ${widget.minPoints} punkty' : ' ',
          style: TextStyle(color: cs.error, fontSize: 13)),
    ]);
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> pts;
  final Offset? finger;
  final Offset Function(int) center;
  final Color active;
  final Color idle;
  _PatternPainter(this.pts, this.finger, this.center, this.active, this.idle);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = active.withValues(alpha: 0.55)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < pts.length; i++) {
      canvas.drawLine(center(pts[i - 1]), center(pts[i]), line);
    }
    if (pts.isNotEmpty && finger != null) canvas.drawLine(center(pts.last), finger!, line);
    for (var i = 0; i < 9; i++) {
      final on = pts.contains(i);
      canvas.drawCircle(center(i), on ? 11 : 7, Paint()..color = on ? active : idle);
      if (on) {
        canvas.drawCircle(
            center(i),
            24,
            Paint()
              ..color = active.withValues(alpha: 0.15)
              ..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => true;
}
