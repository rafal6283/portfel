import 'package:flutter/material.dart';

import '../security/lock.dart';
import 'format.dart';
import 'lock_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  LockConfig? c;
  bool bioAvailable = false;
  bool deviceAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = await Lock.load();
    final b = await Lock.biometricAvailable();
    final d = await Lock.deviceAuthAvailable();
    if (mounted) {
      setState(() {
        c = x;
        bioAvailable = b;
        deviceAvailable = d;
      });
    }
  }

  /// Zmiana zabezpieczenia wymaga potwierdzenia obecnym (jeśli jakieś jest).
  Future<bool> _confirmCurrent() async {
    final cur = c!;
    if (cur.method == LockMethod.none) return true;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (ctx) => LockScreen(config: cur, onUnlocked: () => Navigator.pop(ctx, true))),
    );
    return ok ?? false;
  }

  Future<void> _choose(LockMethod m) async {
    if (m == c!.method && (m == LockMethod.none || m == LockMethod.device)) return;
    if (!await _confirmCurrent()) return;
    if (!mounted) return;
    switch (m) {
      case LockMethod.none:
        await Lock.setMethod(LockMethod.none);
      case LockMethod.device:
        if (!await Lock.systemAuth(biometricOnly: false, reason: 'Potwierdź blokadę ekranu telefonu')) {
          if (mounted) toast(context, 'Nie udało się potwierdzić');
          return;
        }
        await Lock.setMethod(LockMethod.device);
      case LockMethod.pin:
      case LockMethod.pattern:
        final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => LockSetupScreen(method: m)));
        if (ok != true) return;
        if (mounted) toast(context, m == LockMethod.pin ? 'PIN ustawiony' : 'Wzór ustawiony');
    }
    await _load();
  }

  Future<void> _toggleBio(bool v) async {
    if (v && !await Lock.systemAuth(biometricOnly: true, reason: 'Potwierdź odcisk palca lub twarz')) {
      if (mounted) toast(context, 'Nie udało się potwierdzić biometrii');
      return;
    }
    await Lock.setBiometric(v);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final x = c;
    if (x == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    Widget option(LockMethod m, IconData icon, String title, String sub, {bool enabled = true}) => RadioListTile<LockMethod>(
          value: m,
          groupValue: x.method,
          onChanged: enabled ? (v) => _choose(v!) : null,
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(sub),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Logowanie do aplikacji')),
      body: ListView(children: [
        const SectionTitle('Sposób odblokowania'),
        option(LockMethod.none, Icons.lock_open, 'Brak', 'Aplikacja otwiera się bez logowania'),
        option(LockMethod.pin, Icons.pin_outlined, 'PIN', '4–8 cyfr, osobny od PIN-u telefonu'),
        option(LockMethod.pattern, Icons.pattern, 'Wzór', 'Połączenie co najmniej 4 punktów na siatce 3×3'),
        option(LockMethod.device, Icons.phonelink_lock, 'Blokada ekranu telefonu', 'PIN/wzór/hasło lub biometria ustawione w telefonie',
            enabled: deviceAvailable),
        if (x.method == LockMethod.pin || x.method == LockMethod.pattern) ...[
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(x.method == LockMethod.pin ? 'Zmień PIN' : 'Zmień wzór'),
            onTap: () async {
              if (!await _confirmCurrent() || !context.mounted) return;
              final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => LockSetupScreen(method: x.method)));
              if (ok == true && context.mounted) toast(context, 'Zmieniono');
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Odblokowanie odciskiem palca / twarzą'),
            subtitle: Text(bioAvailable ? 'Szybciej niż wpisywanie – PIN lub wzór zostaje jako zapasowy' : 'Biometria nie jest skonfigurowana w telefonie'),
            value: x.biometric,
            onChanged: bioAvailable ? _toggleBio : null,
          ),
        ],
        if (x.method != LockMethod.none) ...[
          const SectionTitle('Kiedy pytać ponownie'),
          for (final t in const [(15, 'Zaraz po wyjściu z aplikacji'), (60, 'Po 1 minucie w tle'), (300, 'Po 5 minutach w tle'), (1800, 'Po 30 minutach w tle')])
            RadioListTile<int>(
              value: t.$1,
              groupValue: x.timeoutSec,
              onChanged: (v) async {
                await Lock.setTimeout(v!);
                await _load();
              },
              title: Text(t.$2),
            ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Text(
            'PIN i wzór nie są nigdzie zapisywane wprost – aplikacja przechowuje tylko ich zabezpieczony skrót. Po 5 błędnych próbach '
            'logowanie jest czasowo blokowane. Jeśli zapomnisz PIN-u lub wzoru, odblokujesz aplikację blokadą ekranu telefonu.',
          ),
        ),
      ]),
    );
  }
}
